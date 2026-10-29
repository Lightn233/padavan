"""仅构建固件使用的 blkid、libblkid 和 libuuid。"""
from pathlib import Path
import argparse,json,os,shlex,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('action',choices=['configure','compile','install']);p.add_argument('--source',required=True);p.add_argument('--stage',required=True);a=p.parse_args()
S=Path(a.source).resolve();B=S/'padavan-build';D=Path(a.stage).resolve()
def run(argv):subprocess.run(argv,check=True)
if a.action=='configure':
 cross=S/'padavan-cross.ini'
 def arr(name,default=''):return repr(shlex.split(os.environ.get(name,default)))
 cross.write_text("[binaries]\nc = "+arr('CC')+"\nar = "+arr('AR')+"\nstrip = "+arr('STRIP')+"\npkgconfig = ['pkg-config']\n[host_machine]\nsystem = 'linux'\ncpu_family = 'mips'\ncpu = 'mips32r2'\nendian = 'little'\n[properties]\nneeds_exe_wrapper = true\n[built-in options]\nc_args = "+arr('CFLAGS')+"\nc_link_args = "+arr('LDFLAGS')+'\n')
 run(['meson','setup',str(B),str(S),'--cross-file',str(cross),'--prefix=/','--libdir=lib','--sbindir=sbin','--sysconfdir=/etc','--buildtype=release','--auto-features=disabled','--default-library=shared','-Dbuild-libblkid=enabled','-Dbuild-libuuid=enabled','-Dprogram-tests=false','-Dbuild-chfn-chsh=disabled'])
elif a.action=='compile':
 targets=json.loads(subprocess.check_output(['meson','introspect','--targets',str(B)]));wanted=[]
 for t in targets:
  if t['name'] in ['blkid','uuid'] and t['type'] in ['shared library','executable']:
   wanted.extend(str(Path(n).relative_to(B)) for n in t['filename'])
 assert len(wanted)==3,wanted
 run(['ninja','-C',str(B),'-j4',*wanted])
else:
 (D/'lib/pkgconfig').mkdir(parents=True,exist_ok=True);(D/'include/blkid').mkdir(parents=True,exist_ok=True);(D/'include/uuid').mkdir(parents=True,exist_ok=True);(D/'sbin').mkdir(parents=True,exist_ok=True)
 for base in ['libblkid','libuuid']:
  files=[f for f in B.rglob(base+'.so*') if f.is_file() or f.is_symlink()];assert files
  for f in files:
   q=D/'lib'/f.name
   if q.exists() or q.is_symlink():q.unlink()
   if f.is_symlink():q.symlink_to(os.readlink(f))
   else:shutil.copy2(f,q)
 for name in ['blkid','uuid']:
  src=next(B.rglob(name+'.h'),None) or next(S.rglob(name+'.h'));shutil.copy2(src,D/'include'/name/(name+'.h'))
  pc=B/'meson-private'/(name+'.pc');assert pc.exists();text=pc.read_text().replace('prefix=/\n','prefix='+str(D)+'\n');(D/'lib/pkgconfig'/pc.name).write_text(text)
 shutil.copy2(B/'blkid',D/'sbin/blkid')
