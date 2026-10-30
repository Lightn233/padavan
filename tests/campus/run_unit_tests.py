#!/usr/bin/env python3
"""针对应用完项目补丁的校园网组件运行真实函数回归；支持本机内存检查和 MIPS 模拟。"""
from pathlib import Path
import argparse,hashlib,json,os,shlex,subprocess

HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--minieap',type=Path,required=True)
parser.add_argument('--gdut-drcom',type=Path,required=True)
parser.add_argument('--mentohust',type=Path)
parser.add_argument('--dogcom',type=Path)
parser.add_argument('--scutclient',type=Path)
parser.add_argument('--out',type=Path,required=True)
parser.add_argument('--cc',default='gcc')
parser.add_argument('--runner',default='')
parser.add_argument('--mips',action='store_true')
a=parser.parse_args();a.out=a.out.resolve();a.out.mkdir(parents=True,exist_ok=True)
mini=a.minieap.resolve();gdut=a.gdut_drcom.resolve()/'src'
fixtures={
    'valid':('valid','  remote_ip = "192.0.2.2"\nremote_port=61440\nkeep_alive1_flag=dc\nenable_crypt=1\n'),
    'blank':('empty','\n  \t\n# comment\n'),
    'empty-assignment':('empty',' = \n'),
    'long-key':('invalid','K'*800+'=value\n'),
    'long-value':('invalid','remote_ip='+'x'*600+'\n'),
    'long-line':('invalid','x'*3000+'=1\n'),
    'bad-address':('invalid','remote_ip=not-an-ip\n'),
    'bad-port':('invalid','remote_port=65536\n'),
    'negative-port':('invalid','remote_port=-1\n'),
    'suffix-port':('invalid','remote_port=80junk\n'),
    'bad-hex':('invalid','keep_alive1_flag=100\n'),
    'bad-crypt':('invalid','enable_crypt=3\n'),
    'atomic-error':('invalid','remote_port=12345\nremote_ip=invalid\n'),
}
tests={
    'minieap-properties':{
        'sources':[HERE/'minieap_properties_test.c',mini/'packet_plugin/rjv3/packet_plugin_rjv3_prop.c',mini/'packet_plugin/rjv3/packet_plugin_rjv3_priv.c',mini/'util/misc.c',mini/'util/linkedlist.c'],
        'includes':[mini/'include',mini/'packet_plugin/rjv3',mini/'packet_plugin/rjv3/rjv3_hashes'],
        'extra':['-DENABLE_ICONV','-Wl,--wrap=malloc,--wrap=calloc'],
        'cases':[[v] for v in ['valid','legacy','truncated','short-header','small-output','negative','transaction','allocation','boundary','remove','echo-key','frame-bounds','fuzz']],
    },
    'minieap-frames':{
        'sources':[HERE/'minieap_frame_test.c',mini/'util/packet_util.c',mini/'util/misc.c'],
        'includes':[mini/'include'],
        'extra':['-DENABLE_ICONV','-DFIXED','-Wl,--wrap=malloc,--wrap=calloc,--wrap=iconv_open'],
        'cases':[[v] for v in ['duplicate-capacity','duplicate-allocation','append-invalid','message-allocation','message-output','message-iconv-failure','receive-bounds']],
    },
    'gdut-config':{
        'sources':[HERE/'gdut_config_test.c',gdut/'config.c',gdut/'logger.c'],
        'includes':[gdut],'extra':[],'cases':[],
    },
    'gdut-packets':{
        'sources':[HERE/'gdut_packet_test.c',gdut/'logger.c'],
        'includes':[gdut],'extra':[],'cases':[['log'],['crc']],
    },
}
for name,(expected,text) in fixtures.items():
    path=a.out/(name+'.conf');path.write_text(text)
    tests['gdut-config']['cases'].append([expected,str(path)])

if a.mentohust:
    mento=a.mentohust.resolve()/'src'
    tests['mentohust-packets']={'sources':[HERE/'mentohust_packet_test.c'],'includes':[mento],'extra':[],
        'cases':[[n] for n in ['short','identity','outer-length','challenge','short-challenge','short-success','success','failure','rj-message','cernet-message','saved-request','fuzz']]}
    tests['mentohust-password']={'sources':[HERE/'mentohust_password_test.c',mento/'md5.c'],'includes':[mento],'extra':[],'cases':[[]]}
    tests['mentohust-input']={'sources':[HERE/'mentohust_input_test.c'],'includes':[mento],'extra':[],'cases':[['1'],['0'],['0'],['0']],
        'stdin':{0:'p'*64+'\n',1:'p'*65+'\n',2:'p'*200+'\n',3:''}}
if a.dogcom:
    dog=a.dogcom.resolve()
    base="server = '127.0.0.2'\nusername = 'lab'\npassword = 'password'\nhost_ip = '127.0.0.1'\n"
    dogcases=[('blank',base+'\n  \n# test\n','dhcp','ok'),('flag',base+'keepalive1_mod = True\nhost_name = host\n','dhcp','flag'),('space',base+"host_name = 'test host'\n",'dhcp','space'),('missing',base+'username =\n','dhcp','reject'),('long',base+"username = '"+'A'*200+"'\n",'dhcp','reject'),('hex-short',base+"AUTH_VERSION = '\\x01'\n",'dhcp','reject'),('hex-bad',base+"IPDOG = '\\xgg'\n",'dhcp','reject'),('ip',base+"server = '999.0.0.1'\n",'dhcp','reject'),('ror-long',base+"password = '12345678901234567'\nror_version = True\n",'dhcp','reject'),('quote',base+"host_name = 'unterminated\n",'dhcp','reject'),('pppoe',"server = '127.0.0.2'\npppoe_flag = '\\x18'\nkeep_alive2_flag = '\\xd8'\n",'pppoe','ok'),('sample',(dog/'sample-d.conf').read_text().replace('192.168.1.14','127.0.0.2'),'dhcp','ok')]
    tests['dogcom-config']={'sources':[HERE/'dogcom_config_test.c'],'includes':[dog],'extra':[],'cases':[]}
    for name,body,mode,expected in dogcases:
        path=a.out/('dogcom-'+name+'.conf');path.write_text(body)
        tests['dogcom-config']['cases'].append([str(path),mode,expected])
    tests['dogcom-login']={'sources':[HERE/'dogcom_login_test.c',dog/'libs/md5.c'],'includes':[dog],'extra':[],'cases':[[]]}
if a.scutclient:
    scut=a.scutclient.resolve()/'src'
    tests['scut-packets']={'sources':[HERE/'scut_packet_test.c',*[scut/n for n in ['functions.c','drcom.c','info.c','md5.c']]],'includes':[scut],'extra':[],
        'cases':[[n] for n in ['password','hex','crc','username','eap','udp']],
        'contains':{0:hashlib.md5(b'\x07'+b'a'*200+bytes(16)).hexdigest()}}

results=[]
for name,test in tests.items():
    binary=a.out/name
    cmd=[a.cc,'-O1','-g','-std=gnu11','-D_GNU_SOURCE','-no-pie','-ffunction-sections','-fdata-sections','-Wl,--gc-sections']
    cmd+=(['-static','-march=mips32r2'] if a.mips else ['-fsanitize=address,undefined'])
    cmd+=['-I'+str(i) for i in test['includes']]+test['extra']+[str(s) for s in test['sources']]+['-o',str(binary)]
    with (a.out/(name+'-build.log')).open('w') as log:
        subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=90)
    for i,case in enumerate(test['cases']):
        logpath=a.out/(name+'-'+str(i)+'.log')
        with logpath.open('w') as log:
            r=subprocess.run(shlex.split(a.runner)+[str(binary)]+case,stdout=log,stderr=subprocess.STDOUT,timeout=30,text=True,input=test.get("stdin",{}).get(i),
                env={**os.environ,'ASAN_OPTIONS':'detect_leaks=1:abort_on_error=1','UBSAN_OPTIONS':'halt_on_error=1'})
        passed=r.returncode==0 and test.get('contains',{}).get(i,'') in logpath.read_text(errors='replace')
        results.append({'group':name,'case':case,'exit':r.returncode,'passed':passed})
    (a.out/'results.json').write_text(json.dumps(results,indent=2))
print(json.dumps({'passed':all(r['passed'] for r in results),'cases':len(results),'results':str(a.out/'results.json')}))
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
