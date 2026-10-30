#!/usr/bin/env python3
"""使用临时目录和模拟 NVRAM 检查服务启动入口；不启动网络服务。"""
from pathlib import Path
import argparse, json, os, shlex, stat, subprocess, tempfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-root',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
parser.add_argument('--shell',default='/bin/sh')
a=parser.parse_args();a.out.mkdir(parents=True,exist_ok=True)
results=[]

def check(name,package,values,expected=0,password=None,old=None,manual=None,hold=False,stale=False,daemon_fail=False,check_args=None):
    with tempfile.TemporaryDirectory(prefix='campus-launch-') as directory:
        root=Path(directory);bindir=root/'bin';bindir.mkdir()
        record=root/'args.json';fixture=root/'nvram.json';fixture.write_text(json.dumps(values))
        fake='''#!/usr/bin/python3
import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name
if name=='nvram':
    assert sys.argv[1]=='get', 'unexpected NVRAM write'
    sys.stdout.write(json.loads(Path(os.environ['FIXTURE']).read_text()).get(sys.argv[2],''))
elif name=='start-stop-daemon':
    Path(os.environ['RECORD']).write_text(json.dumps(sys.argv[1:]))
    sys.exit(int(os.environ.get('DAEMON_FAIL','0')))
elif name=='killall':
    raise SystemExit('unexpected service stop')
'''
        for n in ['nvram','start-stop-daemon','logger','killall']:
            p=bindir/n;p.write_text(fake);p.chmod(0o755)
        pid=root/'service.pid';lock=Path(str(pid)+'.lock');conf=root/'generated.conf';persistent=root/'storage.conf'
        if old is not None:conf.write_text(old)
        if manual is not None:persistent.write_text(manual)
        if hold:lock.mkdir()
        if stale:
            lock.mkdir();(lock/'999999999').touch()
        source=a.source_root/'trunk/user'/package/'scripts'/(package+'.sh')
        text=source.read_text()
        if package=='mentohust':
            text=text.replace('/var/sh_mentohust.pid',str(pid)).replace('/var/mentohust.conf',str(conf)).replace('/etc/storage/mentohust.conf',str(persistent))
        else:text=text.replace('/var/scutclient.sh.pid',str(pid))
        script=root/'service.sh';script.write_text(text)
        env={**os.environ,'PATH':str(bindir)+':'+os.environ['PATH'],'FIXTURE':str(fixture),'RECORD':str(record),'DAEMON_FAIL':str(int(daemon_fail))}
        r=subprocess.run(shlex.split(a.shell)+[str(script),'start','nolog'],env=env,capture_output=True,text=True,timeout=10)
        errors=[]
        if r.returncode!=expected:errors.append('exit '+str(r.returncode))
        if hold:
            if record.exists() or not lock.is_dir():errors.append('lock ownership')
        elif lock.exists():errors.append('lock not released')
        if password is not None:
            if '\nPassword='+password+'\n' not in conf.read_text():errors.append('password changed')
            if stat.S_IMODE(conf.stat().st_mode)!=0o600:errors.append('configuration mode')
            if not persistent.is_symlink() or persistent.resolve()!=conf:errors.append('runtime link')
            if '\nNic=eth-test\n' not in conf.read_text():errors.append('interface fallback')
        if old is not None and conf.read_text()!=old:errors.append('old configuration changed')
        if manual is not None and (persistent.is_symlink() or persistent.read_text()!=manual):errors.append('manual configuration changed')
        if check_args is not None:
            argv=json.loads(record.read_text()) if record.exists() else []
            if argv[:6]!=['-S','-b','-x','bin_scutclient','--','-u']:errors.append('service arguments')
            try:check_args(argv[5:])
            except (AssertionError,ValueError,IndexError):errors.append('application arguments')
        passed=not errors
        results.append({'case':name,'passed':passed,'errors':errors})
        (a.out/(name+'.log')).write_text(r.stdout+r.stderr)

base={'mentohust_username':'lab','wan_ifname':'eth-test'}
for i,password in enumerate(['p&word',r'p\\word/next',' p word ','p"word\'tail']):
    check('mento-password-'+str(i),'mentohust',{**base,'mentohust_password':password},password=password)
for n,value in [('newline','line1\nline2'),('cr','line1\rline2')]:
    check('mento-'+n,'mentohust',{**base,'mentohust_password':value},expected=1,old='previous\n')
check('mento-manual','mentohust',base,manual='[MentoHUST]\nPassword=keep\n')
check('mento-start-failed','mentohust',base,expected=1,daemon_fail=True)
check('mento-busy','mentohust',base,expected=1,hold=True)
check('mento-stale-lock','mentohust',base,stale=True)

scut={'scutclient_username':'lab','scutclient_password':' p & \\ " q ','wan_ifname':'eth-test'}
def defaults(argv):
    assert '' not in argv
    assert argv[argv.index('-p')+1]==scut['scutclient_password']
    assert all(flag not in argv for flag in ['-D','-b','-H','-s','-c','-h'])
    assert argv[-4:]==['-E','echo 0 > /tmp/scutclient_status','-Q','echo 1 > /tmp/scutclient_status']
check('scut-defaults','scutclient',scut,check_args=defaults)
def full(argv):
    assert '' not in argv and '-D' in argv and '-b' in argv
    assert argv[argv.index('-H')+1]=='test host'
    assert argv[argv.index('-h')+1]=='abcd'
    assert argv[argv.index('-c')+1]=='0102'
    assert argv[argv.index('-s')+1]=='192.0.2.1'
check('scut-full','scutclient',{**scut,'scutclient_hostname':'test host','scutclient_hash':'abcd','scutclient_version':'0102','scutclient_server_auth_ip':'192.0.2.1','scutclient_debug':'1','scutclient_skip_udp_hb':'1'},check_args=full)
check('scut-start-failed','scutclient',scut,expected=1,daemon_fail=True)
check('scut-busy','scutclient',scut,expected=1,hold=True)
check('scut-stale-lock','scutclient',scut,stale=True)
(a.out/'results.json').write_text(json.dumps(results,indent=2))
print(json.dumps({'passed':all(r['passed'] for r in results),'cases':len(results),'failed':[r for r in results if not r['passed']]}))
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
