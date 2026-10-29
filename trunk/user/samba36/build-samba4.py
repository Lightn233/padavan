"""Samba 与新增私有依赖在同一工作目录构建，不复制固件源码树。"""
from pathlib import Path
import hashlib,json,os,re,shlex,shutil,subprocess,sys
root=Path(sys.argv[1]).resolve();task=sys.argv[2];source=root/'samba-4.25.1';stage=root/'stage'
external=Path(os.environ['SAMBA_EXTERNAL_STAGE']).resolve();cc=os.environ['SAMBA_CC'];cross=os.environ['SAMBA_CROSS'];jobs=os.environ.get('SAMBA_JOBS','4')
qemu=os.environ.get('SAMBA_QEMU') or shutil.which('qemu-mipsel')
if not qemu:raise SystemExit('Samba 交叉构建需要 qemu-mipsel，可用 SAMBA_QEMU 指定已有程序')
sysroot=subprocess.check_output(shlex.split(cc)+['--print-sysroot'],text=True).strip()
env={**os.environ,'CC':cc,'CXX':cross+'g++','AR':cross+'ar','RANLIB':cross+'ranlib','CFLAGS':os.environ.get('SAMBA_CFLAGS','-O2')+' -std=gnu17 -fPIC','CXXFLAGS':'-O2 -std=gnu++17 -fPIC','CPPFLAGS':f'-I{stage}/include -I{external}/include','LDFLAGS':f'-L{stage}/lib -L{external}/lib -Wl,-rpath-link,{stage}/lib -Wl,-rpath-link,{external}/lib -latomic','PKG_CONFIG_LIBDIR':f'{stage}/lib/pkgconfig:{external}/lib/pkgconfig','PKG_CONFIG_PATH':'','LC_ALL':'C','WAF_NO_PREFORK':'1'}
def run(cmd,cwd,extra=None):
 print('+',shlex.join(list(map(str,cmd))),flush=True);subprocess.run(list(map(str,cmd)),cwd=cwd,env={**env,**(extra or {})},check=True)
def signature():return hashlib.sha256(json.dumps({'root':str(root),'cc':subprocess.check_output(shlex.split(cc)+['--version'],text=True),'flags':env['CFLAGS'],'recipe':Path(__file__).read_text()},sort_keys=True).encode()).hexdigest()
sig=signature()
wrapper=root/'cross-run';wrapper.write_text('#!/bin/sh\nexec '+shlex.quote(qemu)+' -cpu 24Kf -L '+shlex.quote(sysroot)+' -E '+shlex.quote(f'LD_LIBRARY_PATH={stage}/lib:{external}/lib')+' "$@"\n');wrapper.chmod(0o755);env['SAMBA_CROSS_RUN']=str(wrapper)
if task=='configure':
 stage.mkdir(exist_ok=True)
 for name,opts in [
  ('gmp-6.3.0',['--disable-cxx']),('nettle-3.10.2',['--disable-documentation','--disable-openssl']),
  ('libtasn1-4.21.0',['--disable-doc','--disable-tests','--disable-gcc-warnings']),
  ('gnutls-3.8.12',['--disable-doc','--disable-tests','--disable-tools','--disable-guile','--without-p11-kit','--without-tpm','--without-idn','--with-included-unistring','--disable-nls','--disable-cxx','--without-brotli','--without-zstd','--without-zlib'])]:
  sub=root/name;stamp=root/(name+'.dependency-signature')
  if stamp.exists() and stamp.read_text()==sig:continue
  if (sub/'Makefile').exists():run(['make','distclean'],sub)
  run(['./configure','--host=mipsel-linux-musl','--prefix='+str(stage),'--enable-shared','--disable-static',*opts],sub)
  run(['make','-j'+jobs],sub);run(['make','install'],sub);stamp.write_text(sig)
 run(['perl','-MParse::Yapp::Driver','-e','1'],root)
 opts=['--cross-compile','--cross-execute='+str(wrapper),'--cross-answers='+str(root/'cross-answers.txt'),'--hostcc=gcc','--prefix=/usr','--sysconfdir=/etc','--localstatedir=/var','--enable-fhs','--disable-python','--disable-fault-handling','--disable-cephfs','--disable-cephrgw','--disable-cups','--disable-glusterfs','--disable-iprint','--disable-spotlight','--disable-avahi','--without-ad-dc','--without-ads','--without-ldap','--without-winbind','--without-quotas','--without-systemd','--without-systemd-userdb','--without-regedit','--without-gpgme','--without-kernel-keyring','--without-pam','--without-utmp','--without-acl-support','--without-json','--without-libarchive','--without-ldb-lmdb','--without-iconv','--with-configdir=/etc','--with-privatedir=/etc/samba','--with-lockdir=/var/locks','--with-statedir=/etc/samba','--with-cachedir=/var/cache/samba','--with-piddir=/var/run','--bundled-libraries=talloc,tevent,tevent-util,texpect,tdb,ldb,tdr,cmocka,replace,com_err','--private-libraries=talloc,tevent,tevent-util,texpect,tdb,ldb,tdr,cmocka,replace,com_err','--with-static-modules=vfs_default,auth_builtin,auth_sam,auth_unix,pdb_smbpasswd,pdb_tdbsam,!DEFAULT,!FORCED','--with-shared-modules=!DEFAULT,!FORCED']
 run(['./configure',*opts],source)
elif task=='compile':
 run(['make','-j'+jobs],source)
 run(shlex.split(cc)+['-Os','-std=gnu17',str(Path(__file__).with_name('smbpasswd-compat.c')),'-o',str(root/'smbpasswd-compat')],root)
elif task=='install':run(['make','install','DESTDIR='+str(root/'install')],source)
elif task=='romfs':
 dest=Path(os.environ['SAMBA_ROMFS']).resolve();install=root/'install';manifest=[];queue=[];seen=set()
 def copy(src,relative):
  target=dest/relative;target.parent.mkdir(parents=True,exist_ok=True)
  assert target.parent.resolve().is_relative_to(dest),('destination escapes romfs',target)
  machine=subprocess.check_output([cross+'readelf','-h',str(src.resolve())],text=True);assert 'MIPS' in machine,src
  if target.is_symlink():target.unlink()
  shutil.copyfile(src.resolve(),target);target.chmod(0o755);queue.append(target)
  manifest.append({'path':relative,'source':str(src),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
 if os.environ.get('SAMBA_SMBD')=='y':
  for name,relative in [('smbd','sbin/smbd'),('nmbd','sbin/nmbd'),('smbpasswd','usr/bin/smbpasswd4'),('testparm','usr/bin/testparm')]:
   matches=[x for x in install.rglob(name) if x.is_file()];assert len(matches)==1,(name,matches);copy(matches[0],relative)
  copy(root/'smbpasswd-compat','bin/smbpasswd')
  # RPC 按需助手沿用安装路径；禁止遗漏导致浏览共享或管理请求失败。
  for f in install.glob('usr/libexec/samba/*'):
   if f.is_file():copy(f,str(f.relative_to(install)))
 elif os.environ.get('SAMBA_WINS')=='y':
  matches=[x for x in install.rglob('nmbd') if x.is_file()];assert len(matches)==1;copy(matches[0],'sbin/nmbd')
 candidates={}
 for base in [install,stage/'lib',external/'lib',Path(sysroot)/'lib',Path(sysroot)/'usr/lib']:
  if base.exists():
   for f in sorted(base.rglob('*.so*')):
    if f.is_file():candidates.setdefault(f.name,f)
 while queue:
  f=queue.pop();r=subprocess.run([cross+'readelf','-d',str(f)],capture_output=True,text=True,check=True)
  for name in re.findall(r'Shared library: \[([^\]]+)\]',r.stdout):
   if name in seen:continue
   seen.add(name)
   if name=='libc.so':continue
   assert name in candidates,('missing dependency',name)
   copy(candidates[name],'usr/lib/'+name)
 # 只装实际引用的动态库，不把客户端、开发文件和整棵依赖目录塞进固件。
 for item in manifest:
  target=dest/item['path'];run([cross+'strip','--strip-unneeded',target],root);item['sha256']=hashlib.sha256(target.read_bytes()).hexdigest();item['bytes']=target.stat().st_size
 (root/'romfs-manifest.json').write_text(json.dumps(manifest,indent=2))
else:raise SystemExit('未知构建阶段')
