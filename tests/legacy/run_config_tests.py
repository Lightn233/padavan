"""同一配置转换器分别用宿主机 Sanitizer 和 MIPS 运行，核对旧字段含义。"""
from pathlib import Path
import json,os,subprocess
import argparse,tempfile
parser=argparse.ArgumentParser()
parser.add_argument('--cc',default='gcc')
parser.add_argument('--mips-cc')
parser.add_argument('--qemu',default='qemu-mipsel')
parser.add_argument('--output',type=Path,default=Path('legacy-config-results.json'))
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
workspace=tempfile.TemporaryDirectory(prefix='padavan-legacy-config-')
L=Path(workspace.name)
source=root/'trunk/user/legacy-compat/legacy-config.c'
native=L/'legacy-config-native';mips=L/'legacy-config-mips'
subprocess.run([args.cc,'-std=c11','-Wall','-Wextra','-Werror','-O1','-g','-fsanitize=address,undefined','-fno-pie','-no-pie',str(source),'-o',str(native)],check=True)
targets=[('native',[str(native)])]
if args.mips_cc:
 subprocess.run([args.mips_cc,'-std=c11','-Wall','-Wextra','-Werror','-Os','-static',str(source),'-o',str(mips)],check=True)
 targets.append(('mips',[args.qemu,'-cpu','24Kf',str(mips)]))
base=['test-key','test-secret-\'"\\\n中文','example.com','@','example.net','www','example.org','*','600']
tests=[]
def add(name,mode,fields,ok,check=lambda s:True):tests.append((name,mode,fields,ok,check))
add('ipv4-upstream','dns',['0.0.0.0','6053','223.5.5.5:53','192.168.2.1/24'],True,lambda s:'server-tcp 223.5.5.5:53' in s)
add('ipv6-upstream','dns',['::','6053','[2001:db8::53]:5353','2001:db8::1/64'],True,lambda s:'server-tcp [2001:db8::53]:5353' in s)
add('scoped-ipv6','dns',['127.0.0.1','6053','[fe80::1%eth3]:53',''],True,lambda s:'%eth3' in s)
add('hash-upstream-port','dns',['127.0.0.1','6053','127.0.0.1#2053',''],True)
for name,bind,port,server,local in [
 ('reserved53','0.0.0.0','53','223.5.5.5',''),('reserved5335','::','5335','223.5.5.5',''),
 ('invalid-port','127.0.0.1','65536','223.5.5.5',''),('invalid-ip','bad','6053','223.5.5.5',''),
 ('self-loop','127.0.0.1','6053','127.0.0.1:6053',''),('local-dnsmasq','0.0.0.0','6053','192.168.2.1:53','192.168.2.1/24'),
 ('local-agh','::','6053','[2001:db8::1]:5335','2001:db8::1/64'),('unspecified-upstream','::','6053','::',''),
 ('multicast-upstream','::','6053','ff02::1','')]:add(name,'dns',[bind,port,server,local],False)
def ali_check(s):
 c=json.loads(s)['dnsconf'][0]
 return c['dns']['id']==base[0] and c['dns']['secret']==base[1] and c['ipv4']['domains']==['example.com','www.example.net'] and c['ipv6']['domains']==['*.example.org'] and c['ttl']=='600'
add('ali-fields-and-special-secret','aliddns',base,True,ali_check)
v=base.copy();v[4:6]=['example.com','@'];add('deduplicate-identical-record','aliddns',v,True,lambda s:len(json.loads(s)['dnsconf'][0]['ipv4']['domains'])==1)
v=base.copy();v[6:8]=['',''];add('keep-ipv6-disabled','aliddns',v,True,lambda s:json.loads(s)['dnsconf'][0]['ipv6']['enable'] is False)
v=base.copy();v[3]='';add('legacy-default-www','aliddns',v,True,lambda s:json.loads(s)['dnsconf'][0]['ipv4']['domains'][0]=='www.example.com')
for name,index,value in [('no-key',0,''),('bad-domain',2,'two words'),('ttl-overflow',8,'999999999999999999999'),('ttl-fraction',8,'1.5')]:
 v=base.copy();v[index]=value;add(name,'aliddns',v,False)
results=[]
for target,cmd in targets:
 for name,mode,fields,ok,check in tests:
  r=subprocess.run(cmd+[mode],input=b''.join(s.encode()+b'\0' for s in fields),capture_output=True,timeout=12)
  passed=(r.returncode==0)==ok and (not ok or check(r.stdout.decode()))
  results.append({'target':target,'case':name,'passed':passed})
  assert passed,(target,name,r.returncode,r.stderr.decode(),r.stdout.decode())
args.output.write_text(json.dumps({'tests':results,'cases_each':len(tests),'passed':True},indent=2))
print('PASS',len(tests),'cases for each selected target')
