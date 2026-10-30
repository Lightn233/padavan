"""在隔离网络验证 PPP 默认回调、DNS 文件和断线重连，不接触家庭接口。"""
from pathlib import Path
import argparse, json, os, signal, subprocess, sys, time

ap=argparse.ArgumentParser()
ap.add_argument('--binary',required=True)
ap.add_argument('--tag',required=True)
ap.add_argument('--lab-root',required=True,help='新测试目录的父目录，必须位于 /tmp 之外')
ap.add_argument('--pppoe-server',required=True,help='本机原生 pppoe-server 的绝对路径')
ap.add_argument('--expect-bug',action='store_true')
ap.add_argument('--inner',action='store_true')
a=ap.parse_args();P=Path(a.binary).resolve()
assert a.tag.replace('-', '').replace('_', '').isalnum()
L=Path(a.lab_root).resolve()/a.tag
SERVER=Path(a.pppoe_server).resolve()
assert P.is_file() and SERVER.is_file()
assert not L.is_relative_to(Path('/tmp')) and not P.is_relative_to(Path('/tmp')) and not SERVER.is_relative_to(Path('/tmp'))
# 这些挂载点应由虚拟机中的 PPP 依赖包提供；测试不在宿主目录补建它们。
assert all(Path(p).exists() for p in ['/run','/etc/ppp','/usr/lib/pppd','/usr/sbin/pppd'])
def run(cmd,check=True,timeout=20):
    p=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=timeout)
    if check and p.returncode:raise RuntimeError((list(map(str,cmd)),p.returncode,p.stdout,p.stderr))
    return p
if not a.inner:
    assert os.geteuid()==0 and not L.exists()
    L.mkdir(parents=True)
    env={**os.environ,'PPP_PARENT_NET':str(os.stat('/proc/self/ns/net').st_ino)}
    raise SystemExit(subprocess.run(['unshare','--net','--mount','--propagation','private',sys.executable,__file__,*sys.argv[1:],'--inner'],env=env).returncode)
assert str(os.stat('/proc/self/ns/net').st_ino)!=os.environ['PPP_PARENT_NET']
for d in ['run/netns','etc','runtime','plugins/2.4.9']:(L/d).mkdir(parents=True,exist_ok=True)
run(['mount','-t','tmpfs','-o','size=16m,mode=1777','tmpfs','/tmp'])
Path('/tmp/ppp').mkdir()
for name in ['pppoe','pptp','pppol2tp']:
    (L/'plugins'/(name+'.so')).symlink_to(P.parent/'plugins'/name/'.libs'/(name+'.so'))
(L/'plugins/rp-pppoe.so').symlink_to('pppoe.so')
(L/'plugins/2.4.9/rp-pppoe.so').symlink_to('../pppoe.so')
for source,dest in [(L/'run','/run'),(L/'etc','/etc/ppp'),(L/'runtime','/tmp/ppp'),(L/'plugins','/usr/lib/pppd'),(P,'/usr/sbin/pppd')]:
    run(['mount','--bind',source,dest])
# 两组版本均可认证，仅 /tmp/ppp 提供 Padavan 实际生成的默认回调。
for root in [L/'etc',L/'runtime']:
    for name in ['options','chap-secrets','pap-secrets']:
        f=root/name;f.write_text('' if name=='options' else '"lab-client" "lab-server" "test-only-password" *\n');f.chmod(0o600)
for action in ['ip-up','ip-down','ipv6-up','ipv6-down']:
    f=L/'runtime'/action
    text='#!/bin/sh\nprintf "'+action+'|%s|%s|%s|%s|%s|%s\\n" "$IFNAME" "$LINKNAME" "$IPLOCAL" "$IPREMOTE" "$DNS1" "$DNS2" >> "'+str(L/'events.log')+'"\n'
    if action=='ip-up':text+='if [ "$LINKNAME" = wan0 ]; then ip route replace default dev "$IFNAME"; fi\n'
    if action=='ip-down':text+='if [ "$LINKNAME" = wan0 ]; then ip route del default dev "$IFNAME" 2>/dev/null || :; fi\n'
    f.write_text(text);f.chmod(0o755)
names=['pppath-isp','pppath-wan'];children=[];handles=[];results=[];state={}
def inside(ns,args,check=True):return run(['ip','netns','exec',ns,*args],check)
def hasip(ns,addr):
    return any(x.get('local')==addr for d in json.loads(inside(ns,['ip','-j','addr']).stdout) for x in d.get('addr_info',[]))
def wait(fn,seconds=25):
    end=time.monotonic()+seconds
    while time.monotonic()<end:
        if fn():return True
        time.sleep(.2)
    return False
def events():
    return [x.split('|') for x in (L/'events.log').read_text().splitlines()] if (L/'events.log').exists() else []
def count(action):return sum(x[0]==action and x[2]=='wan0' for x in events())
def launch(ns,cmd,log):
    h=(L/log).open('w');handles.append(h)
    p=subprocess.Popen(['ip','netns','exec',ns,*map(str,cmd)],stdout=h,stderr=subprocess.STDOUT,start_new_session=True)
    children.append(p);return p
def stop_namespace(ns):
    for pid in run(['ip','netns','pids',ns],False).stdout.split():
        try:os.kill(int(pid),signal.SIGTERM)
        except ProcessLookupError:pass
try:
    for mod in ['ppp_generic','pppoe']:run(['modprobe',mod])
    for ns in names:run(['ip','netns','add',ns]);run(['ip','-n',ns,'link','set','lo','up'])
    run(['ip','link','add','pa','type','veth','peer','name','pb'])
    for dev,ns in zip(['pa','pb'],names):
        run(['ip','link','set',dev,'netns',ns]);inside(ns,['ip','link','set',dev,'name','eth3']);inside(ns,['ip','link','set','eth3','up'])
    for auth in ['pap','chap']:
        start_counts={name:count(name) for name in ['ip-up','ip-down','ipv6-up','ipv6-down']}
        server_options=['debug','noipdefault','+ipv6','minunit','11','auth','require-'+auth,'name','lab-server','linkname','lab-isp','ipv6','::1,::2','nomppe','nomppc','nobsdcomp','nodeflate','ms-dns','198.18.3.53','ms-dns','198.18.3.54','logfile',str(L/(auth+'-isp-ppp.log'))]
        opt=L/(auth+'-server.options');opt.write_text('\n'.join(server_options)+'\n');opt.chmod(0o600)
        server=launch(names[0],[SERVER,'-I','eth3','-C','path-lab','-S','path-lab','-L','198.18.3.1','-R','198.18.3.2','-N','1','-k','-q',P,'-O',opt,'-X',L/(auth+'-server.pid')],auth+'-server.log')
        time.sleep(.3)
        # 故意不传任何 *-script 参数，必须走固件中的默认路径。
        client=launch(names[1],[P,'nodetach','debug','noauth','plugin','rp-pppoe.so','nic-eth3','rp_pppoe_ac','path-lab','rp_pppoe_service','path-lab','user','lab-client','remotename','lab-server','password','test-only-password','refuse-eap','nomppe','nomppc','nobsdcomp','nodeflate','usepeerdns','+ipv6','ipv6','::2,::1','minunit','0','linkname','wan0','persist','holdoff','1','maxfail','0'],auth+'-client.log')
        assert wait(lambda:hasip(names[1],'198.18.3.2')),'IPCP negotiation failed'
        assert wait(lambda:hasip(names[1],'fe80::2')),'IPv6CP negotiation failed'
        inside(names[1],['ping','-c','2','-W','2','198.18.3.1'])
        inside(names[1],['ping','-6','-c','2','-W','2','-I','ppp0','fe80::1'])
        checks={
          'default_ipv4_callback':wait(lambda:count('ip-up')>start_counts['ip-up'],3),
          'default_ipv6_callback':wait(lambda:count('ipv6-up')>start_counts['ipv6-up'],3),
          'dns_runtime_file':(L/'runtime/resolv.conf').exists(),
          'callback_default_route':bool(inside(names[1],['ip','route','show','default']).stdout.strip()),
        }
        if not a.expect_bug:
            assert all(checks.values()),checks
            assert 'nameserver 198.18.3.53' in (L/'runtime/resolv.conf').read_text()
            assert 'nameserver 198.18.3.54' in (L/'runtime/resolv.conf').read_text()
            env_rows=[e for e in events() if e[0]=='ip-up' and e[2]=='wan0']
            assert env_rows[-1][1:]==['ppp0','wan0','198.18.3.2','198.18.3.1','198.18.3.53','198.18.3.54'],env_rows
            client.send_signal(signal.SIGHUP)
            assert wait(lambda:count('ip-down')>start_counts['ip-down'])
            assert wait(lambda:count('ipv6-down')>start_counts['ipv6-down'])
            assert wait(lambda:count('ip-up')>=start_counts['ip-up']+2 and count('ipv6-up')>=start_counts['ipv6-up']+2),'automatic reconnect callbacks missing'
            assert hasip(names[1],'198.18.3.2')
            inside(names[1],['ping','-c','2','-W','2','198.18.3.1'])
            checks['automatic_reconnect']=True
        else:
            assert not any(checks.values()),checks
        client.terminate();client.wait(timeout=12)
        assert wait(lambda:not hasip(names[1],'198.18.3.2'))
        if not a.expect_bug:
            assert wait(lambda:count('ip-down')>=start_counts['ip-down']+2 and count('ipv6-down')>=start_counts['ipv6-down']+2)
            assert not inside(names[1],['ip','route','show','default']).stdout.strip()
            checks['disconnect_route_cleanup']=True
        stop_namespace(names[0]);time.sleep(.4)
        results.append({'authentication':auth,'negotiation_and_dual_stack_ping':True,'checks':checks})
    state={'passed':True,'expected_bug':a.expect_bug,'network_isolated':True,'explicit_callback_override':False,'tests':results,'events':events()}
except Exception as exc:
    state={'passed':False,'tests':results,'error':repr(exc)};raise
finally:
    for ns in names:stop_namespace(ns)
    for p in children:
        try:p.wait(timeout=5)
        except subprocess.TimeoutExpired:p.kill();p.wait()
    for ns in names:run(['ip','netns','del',ns],False)
    for h in handles:h.close()
    (L/'result.json').write_text(json.dumps(state,indent=2));print(json.dumps(state))
