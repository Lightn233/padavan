#!/usr/bin/env python3
"""工具链入口：固定来源校验、源码构建、保留旧目录与离线兼容。"""
from pathlib import Path
import argparse,datetime,fcntl,hashlib,json,os,shutil,subprocess,tempfile,urllib.request
HERE=Path(__file__).resolve().parent
TARGET='mipsel-linux-musl'
def digest(p,algorithm='sha256'):
 h=hashlib.new(algorithm)
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def output(args):return subprocess.check_output(list(map(str,args)),text=True,stderr=subprocess.STDOUT,timeout=30).strip()
def signature(spec):
 return {key:([{k:v for k,v in x.items() if k not in ('path','url')} for x in val] if isinstance(val,list) else {k:v for k,v in val.items() if k not in ('path','url')}) for key,val in spec.items()}
def check_versions(p):
 assert output([p/'bin'/f'{TARGET}-gcc','-dumpfullversion'])=='16.2.0','GCC 版本不符'
 assert output([p/'bin'/f'{TARGET}-gcc','-dumpmachine'])==TARGET,'目标架构不符'
 assert output([p/'bin'/f'{TARGET}-ld','--version']).splitlines()[0].endswith(' 2.47'),'binutils 版本不符'
 assert (p/TARGET/'sysroot/usr/include/sys/queue.h').is_file(),'缺少 queue.h'
def verify_source(p,spec):
 check_versions(p)
 info=json.loads((p/'padavan-source-build.json').read_text())
 assert info['inputs']==signature(spec),'源码或补丁清单不一致'
 assert info['builder_sha256']==digest(HERE/'build_musl_toolchain.py'),'构建脚本版本不一致'
 for rel,expected in info['files'].items():
  assert (p/rel).resolve().is_relative_to(p.resolve()),rel
  assert digest(p/rel)==expected,'工具链文件摘要变化：'+rel
 return info
def smoke(p,work):
 work.mkdir(parents=True,exist_ok=True)
 src=work/'abi.c';exe=work/'abi'
 src.write_text('#include <time.h>\n#include <sys/types.h>\n#include <pthread.h>\n#include <stdio.h>\n_Static_assert(sizeof(void*)==4,"o32");\n_Static_assert(sizeof(time_t)==8,"time64");\n_Static_assert(sizeof(off_t)==8,"off64");\nstatic void *f(void *p){return p;}\nint main(void){pthread_t t;void *r;int a=3;if(pthread_create(&t,0,f,&a)||pthread_join(t,&r)||r!=&a)return 1;puts("ABI_PASS");return 0;}\n')
 subprocess.run([str(p/'bin'/f'{TARGET}-gcc'),'-O2','-pthread',str(src),'-o',str(exe)],check=True,timeout=30)
 elf=output([p/'bin'/f'{TARGET}-readelf','-h',exe]);assert 'ELF32' in elf and 'little endian' in elf and 'MIPS' in elf
 runtime=False
 if shutil.which('qemu-mipsel'):
  assert 'ABI_PASS' in output(['qemu-mipsel','-L',p/TARGET/'sysroot',exe]);runtime=True
 return {'compile_abi':True,'qemu_runtime':runtime}
def prepare(spec,cache,old=None,offline=False):
 cache.mkdir(parents=True,exist_ok=True)
 manifest=json.loads(json.dumps(spec))
 for key,value in manifest.items():
  entries=value if isinstance(value,list) else [value]
  olds=old.get(key,[]) if old else []
  if isinstance(olds,dict):olds=[olds]
  for i,e in enumerate(entries):
   algorithm=e.get('algorithm','sha256');expected=e.get('hash',e.get('sha256'))
   if i<len(olds):p=Path(olds[i]['path'])
   elif e['path'].startswith('files/'):p=HERE/e['path']
   else:p=cache/Path(e['path']).name
   if p.exists():assert digest(p,algorithm)==expected,'输入摘要不符：'+str(p)
   else:
    assert not old and not offline and e.get('url'),'缺少离线输入：'+str(p)
    partial=p.with_name(p.name+'.part')
    try:
     with urllib.request.urlopen(e['url'],timeout=60) as src,partial.open('wb') as dst:shutil.copyfileobj(src,dst)
     assert digest(partial,algorithm)==expected,'下载摘要不符：'+str(p)
     partial.replace(p)
    finally:
     if partial.exists():partial.unlink()
   e['path']=str(p);e.pop('url',None)
 return manifest
def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('action',choices=['build','ensure','prepare','clean','verify'])
 ap.add_argument('--prefix',type=Path,required=True);ap.add_argument('--work',type=Path,required=True)
 ap.add_argument('--kernel',type=Path,required=True);ap.add_argument('--cache',type=Path,required=True)
 ap.add_argument('--archive',type=Path);ap.add_argument('--jobs',type=int,default=4)
 ap.add_argument('--offline',action='store_true');ap.add_argument('--replace-existing',action='store_true')
 a=ap.parse_args();p=a.prefix.absolute();w=a.work.resolve();spec=json.loads((HERE/'source-inputs.json').read_text())
 if a.action=='ensure':
  if (p/'padavan-source-build.json').exists():verify_source(p,spec);print('源码工具链已校验，未改动文件。');return
  if a.archive is not None and a.archive.is_file():
   subprocess.run(['python3',str(HERE/'install_u5_toolchain.py'),'--prefix',str(p),'--archive',str(a.archive)],check=True);return
  if os.path.lexists(p):
   # 仍校验旧版已安装工具链，不能因为缺少归档而覆盖已有目录。
   subprocess.run(['python3',str(HERE/'install_u5_toolchain.py'),'--prefix',str(p),'--archive',str(a.archive or HERE/'downloads/unavailable.tar.xz')],check=True);return
  # 新克隆没有本机离线包时，复用固定来源的源码构建流程。
  a.action='build'
  print('未找到离线工具链归档，开始从固定版本源码准备工具链。',flush=True)
 if a.action=='verify':print(json.dumps(verify_source(p,spec),ensure_ascii=False));return
 w.mkdir(parents=True,exist_ok=True)
 with (w/'entry.lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  if a.action=='clean':
   state=json.loads((w/'build-state.json').read_text());assert Path(state['identity']['prefix']).resolve()==w/'toolchain'
   # 所有待删除路径先完成边界校验，再开始改名或清理。
   cleanup=[]
   for name in ('build','src'):
    q=w/name;assert q.resolve().is_relative_to(w) and not q.is_symlink()
    cleanup.append(q)
   built=w/'toolchain'
   if built.exists():
    verify_source(built,spec)
    backup=w/('toolchain.previous-'+datetime.datetime.now().strftime('%Y%m%d%H%M%S'));assert not backup.exists()
    active=p.resolve()==built.resolve()
    assert not active or p.is_symlink(),'清理时安装入口必须是独立符号链接'
    built.rename(backup)
    if active:
     temp=p.with_name(p.name+'.clean-link');assert not os.path.lexists(temp)
     temp.symlink_to(backup,target_is_directory=True);temp.replace(p)
   for q in cleanup:
    if q.exists():shutil.rmtree(q)
   # 清理后必须重新完整构建，已安装工具链及下载缓存继续保留。
   (w/'build-state.json').rename(w/('cleaned-state-'+datetime.datetime.now().strftime('%Y%m%d%H%M%S')+'.json'))
   print('已清理本工作目录的中间文件；工具链、日志和下载包保留。');return
  statepath=w/'build-state.json';state=json.loads(statepath.read_text()) if statepath.exists() else None
  if state:
   assert signature(state['identity']['manifest'])==signature(spec),'已有工作目录的输入与新入口不符'
  manifest=prepare(spec,a.cache.resolve(),state['identity']['manifest'] if state else None,a.offline)
  manifestpath=w/'resolved-inputs.json';manifestpath.write_text(json.dumps(manifest,indent=2))
  if a.action=='prepare':print(str(manifestpath));return
  built=w/'toolchain'
  if os.path.lexists(p) and p.resolve()!=built.resolve() and not a.replace_existing:
   raise RuntimeError('安装位置已存在。旧工具链保留；明确选择 SOURCE_REPLACE=1 才会改名备份后切换。')
  subprocess.run(['python3',str(HERE/'build_musl_toolchain.py'),'--manifest',str(manifestpath),'--work',str(w),'--prefix',str(built),'--kernel',str(a.kernel.resolve()),'--jobs',str(a.jobs)],check=True)
  check_versions(built);tested=smoke(built,w/'entry-tests')
  files=['bin/'+TARGET+'-'+n for n in ('gcc','g++','ld','as')]+[TARGET+'/sysroot/usr/lib/libc.so',TARGET+'/sysroot/usr/include/sys/queue.h']
  info={'inputs':signature(spec),'builder_sha256':digest(HERE/'build_musl_toolchain.py'),'tests':tested,'files':{r:digest(built/r) for r in files}}
  (built/'padavan-source-build.json').write_text(json.dumps(info,ensure_ascii=False,indent=2));verify_source(built,spec)
  if p.resolve()!=built.resolve():
   p.parent.mkdir(parents=True,exist_ok=True)
   if os.path.lexists(p):
    backup=p.with_name(p.name+'.before-source-'+datetime.datetime.now().strftime('%Y%m%d%H%M%S'));assert not os.path.lexists(backup);p.rename(backup);print('原工具链保留为：'+str(backup))
   p.symlink_to(built,target_is_directory=True)
  print('源码工具链构建与校验完成：'+str(p))
if __name__=='__main__':main()
