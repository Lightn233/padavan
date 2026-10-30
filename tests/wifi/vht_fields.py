#!/usr/bin/env python3
"""从指定源码提取实际 VHT 函数，验证操作元素和切换通告；不控制无线硬件。"""
from pathlib import Path
import argparse
import json
import re
import shlex
import subprocess
import tempfile

def extract(text,start,end=None):
    pos=text.index(start)
    if end:
        return text[pos:text.index(end,pos)+len(end)]
    opened=text.index('{',pos)
    depth=1
    stop=opened+1
    while depth:
        if text[stop]=='{': depth+=1
        elif text[stop]=='}': depth-=1
        stop+=1
    return text[pos:stop]

def read(path):
    return path.read_bytes().decode().replace('\r\r\n','\n').replace('\r\n','\n')

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source',type=Path,default=Path(__file__).resolve().parents[2])
parser.add_argument('--cc',default='gcc')
parser.add_argument('--runner',default='',help='交叉测试时可设为 qemu-mipsel；此时生成静态程序')
parser.add_argument('--output',type=Path)
args=parser.parse_args()
d=args.source/'trunk/linux-4.4.x/drivers/net/wireless/mediatek/mt7615/embedded'
vht=read(d/'common/vht.c')
header=read(d/'include/dot11ac_vht.h')
fixtures=json.loads(Path(__file__).with_name('vht_fixtures.json').read_text(encoding='utf-8'))
tables=extract(vht,'struct vht_ch_layout {','};')+'\n'
for bw in [80,160]:
    match=re.search(r'static\s+struct\s+vht_ch_layout\s+vht_ch_'+str(bw)+r'M\[\]',vht)
    assert match, bw
    tables+=extract(vht,match[0],'};')+'\n'
center=extract(vht,'UCHAR vht_cent_ch_freq(')
types='\n'.join(extract(header,'typedef struct GNU_PACKED '+name,'} '+alias+';')
    for name,alias in [('_VHT_MCS_MAP','VHT_MCS_MAP'),('_VHT_OP_INFO','VHT_OP_INFO'),('_VHT_OP_IE','VHT_OP_IE')])
wide=extract(header,'typedef struct GNU_PACKED _WIDE_BW_CH_SWITCH_ELEMENT','} WIDE_BW_CH_SWITCH_ELEMENT;')
oper=fixtures['operation_prefix']+types+tables+center+extract(vht,'INT build_vht_op_ie(')+fixtures['operation_main']
csa=fixtures['csa_prefix']+wide+tables+center
csa+=extract(read(d/'common/bcn.c'),'VOID MakeChSwitchAnnounceIEandExtend(')
csa+=extract(read(d/'common/spectrum.c'),'static VOID InsertWideBWChSwitchIE(')+fixtures['csa_main']
centers80={ch:center for channels,center in [
    ([36,40,44,48],42),([52,56,60,64],58),([100,104,108,112],106),
    ([116,120,124,128],122),([132,136,140,144],138),([149,153,157,161],155)] for ch in channels}
centers160={ch:50 if ch<100 else 114 for ch in list(centers80)[:16]}
report={'passed':False,'scope':'isolated-real-functions','runner':args.runner or 'native','groups':{}}
with tempfile.TemporaryDirectory(prefix='padavan-vht-') as directory:
    root=Path(directory)
    for name,source,revision in [('operation',oper,0),('csa-r0',csa,0),('csa-r1',csa,1)]:
        cfile=root/(name+'.c');binary=root/name
        cfile.write_text(source,encoding='utf-8')
        command=shlex.split(args.cc)+['-std=c11','-O1','-g','-Wall','-Wextra','-Werror',
                                    '-Wno-implicit-fallthrough','-Wno-unused-function','-Wno-unused-parameter']
        if args.runner:
            command+=['-static']
        else:
            command+=['-fsanitize=address,undefined','-fno-omit-frame-pointer','-fno-pie','-no-pie']
        if revision: command+=['-DDOT11_VHT_R2']
        subprocess.run(command+[str(cfile),'-o',str(binary)],check=True,timeout=120)
        ran=subprocess.run(shlex.split(args.runner)+[str(binary)],capture_output=True,text=True,timeout=30)
        assert ran.returncode==0,ran.stderr
        rows=ran.stdout.splitlines();failures=[]
        for row in rows:
            if name=='operation':
                ch,old,bw,switching,dfs,ht,streams,ie=row.split(',')
                ch,old,bw,switching,dfs=map(int,[ch,old,bw,switching,dfs])
                primary=old if switching and dfs else ch
                kind='operation'
            else:
                kind,ch,old,bw,ie=row.split(',')
                ch,old,bw=map(int,[ch,old,bw]);primary=ch
            expected={0:(0,0,0),1:(1,centers80[primary],0),
                      2:(1,centers80[primary],centers160.get(primary,0)),
                      3:(1,centers80[primary],155)}[bw]
            if kind=='action' and not revision:
                if bw==2: expected=(2,centers160[ch],0)
                elif bw==3: expected=(3,centers80[ch],155)
            actual=tuple(bytes.fromhex(ie)[:3])
            if actual!=expected:
                failures.append({'kind':kind,'channel':ch,'previous':old,'width':bw,'expected':expected,'actual':actual})
        report['groups'][name]={'cases':len(rows),'mismatches':len(failures),'examples':failures[:4]}
report['passed']=all(v['mismatches']==0 for v in report['groups'].values())
rendered=json.dumps(report,ensure_ascii=False,indent=2)
if args.output: args.output.write_text(rendered+'\n',encoding='utf-8')
print(rendered)
raise SystemExit(0 if report['passed'] else 1)
