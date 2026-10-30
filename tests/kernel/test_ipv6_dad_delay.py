"""直接提取内核中的 DAD 调度函数，检查时间单位；不模拟完整 IPv6 协议栈。"""
from pathlib import Path
import argparse,json,subprocess,tempfile

parser=argparse.ArgumentParser()
parser.add_argument('--source',required=True)
parser.add_argument('--cc',default='gcc')
parser.add_argument('--mips-cc')
parser.add_argument('--expect-bug',action='store_true')
parser.add_argument('--output',required=True)
args=parser.parse_args()
root=Path(args.source)
raw=(root/'trunk/linux-4.4.x/net/ipv6/addrconf.c').read_text()
start=raw.index('static void addrconf_dad_run(struct inet6_dev *idev, bool restart)\n{')
opening=raw.index('{',start);depth=1;end=opening+1
while depth:
    depth+=(raw[end]=='{')-(raw[end]=='}');end+=1
function=raw[start:end]
header=(root/'trunk/linux-4.4.x/include/linux/jiffies.h').read_text()
assert 'return (m + (MSEC_PER_SEC / HZ) - 1) / (MSEC_PER_SEC / HZ);' in header

stub=r'''
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#define MSEC_PER_SEC 1000
static inline unsigned long msecs_to_jiffies(unsigned int m) {
    return (m + (MSEC_PER_SEC / HZ) - 1) / (MSEC_PER_SEC / HZ);
}
#define IFA_F_TENTATIVE 0x40
#define INET6_IFADDR_STATE_PREDAD 0
#define INET6_IFADDR_STATE_DAD 1
struct inet6_ifaddr { unsigned int flags; int state; int lock; struct inet6_ifaddr *next; };
struct address_list { struct inet6_ifaddr *first; };
struct net_device { const char *name; };
struct inet6_dev { struct net_device *dev; int lock; struct address_list addr_list; };
#define read_lock_bh(x) ((void)(x))
#define read_unlock_bh(x) ((void)(x))
#define spin_lock(x) ((void)(x))
#define spin_unlock(x) ((void)(x))
#define list_for_each_entry(pos,head,member) for(pos=(head)->first;pos;pos=pos->next)
static unsigned long observed;
static unsigned int calls;
static void addrconf_dad_kick(struct inet6_ifaddr *ifp,unsigned long delay) {
    (void)ifp; observed=delay; calls++;
}
'''
tail=r'''
int main(void) {
    const char *names[]={"br0","eth3","eth2","ra0","veth0"};
    unsigned int failed=0,tests=0;
    for(unsigned int i=0;i<sizeof(names)/sizeof(names[0]);i++) {
        struct net_device dev={names[i]};
        struct inet6_ifaddr address={IFA_F_TENTATIVE,INET6_IFADDR_STATE_DAD,0,0};
        struct inet6_dev idev={&dev,0,{&address}};
        unsigned long expected=i<2?6UL*HZ:0;
        unsigned int expected_calls=i==2?0:1;
        observed=0;calls=0;
        addrconf_dad_run(&idev,true);
        int ok=observed==expected && calls==expected_calls &&
               (i==2 || address.state==INET6_IFADDR_STATE_PREDAD) && address.flags==IFA_F_TENTATIVE;
        printf("%s HZ=%d ticks=%lu expected=%lu calls=%u passed=%d\n",names[i],HZ,observed,expected,calls,ok);
        tests++;if(!ok)failed++;
    }
    printf("tests=%u failed=%u\n",tests,failed);
    return failed?1:0;
}
'''
results=[]
with tempfile.TemporaryDirectory(prefix='rm2100-dad-unit-') as tmp:
    p=Path(tmp);c=p/'test.c';c.write_text(stub+function+tail)
    for hz in ([100] if args.expect_bug else [100,250,1000]):
        exe=p/('native-'+str(hz))
        build=subprocess.run([args.cc,'-std=gnu99','-O2','-DHZ='+str(hz),str(c),'-o',str(exe)],capture_output=True,text=True)
        assert build.returncode==0,build.stderr
        run=subprocess.run([str(exe)],capture_output=True,text=True)
        results.append({'target':'native','HZ':hz,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr})
    if args.mips_cc and not args.expect_bug:
        exe=p/'mips-test'
        build=subprocess.run([args.mips_cc,'-std=gnu99','-O2','-static','-DHZ=100',str(c),'-o',str(exe)],capture_output=True,text=True)
        assert build.returncode==0,build.stderr
        run=subprocess.run(['qemu-mipsel',str(exe)],capture_output=True,text=True,timeout=15)
        results.append({'target':'MIPS-QEMU','HZ':100,'exit':run.returncode,'stdout':run.stdout,'stderr':run.stderr})
passed=(results[0]['exit']==1 and 'failed=2' in results[0]['stdout']) if args.expect_bug else all(x['exit']==0 for x in results)
result={'passed':passed,'baseline_bug_expected':args.expect_bug,'scope':'提取实际调度函数，使用模拟计时器；不是完整内核启动或 DAD 报文验收','results':results}
Path(args.output).write_text(json.dumps(result,ensure_ascii=False,indent=2))
print(json.dumps({'passed':passed,'baseline_bug_expected':args.expect_bug,'variants':len(results)},ensure_ascii=False))
raise SystemExit(0 if passed else 1)
