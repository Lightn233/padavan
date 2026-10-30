#!/usr/bin/env python3
"""从固定官方源码生成 MIPS 兼容包；不把大程序内置进固件。"""
from pathlib import Path
import argparse,gzip,hashlib,io,json,os,subprocess,tarfile,tempfile,urllib.request

VERSION='6.17.7'
COMMIT='7aad574de4ba1e4646f07648a38235d34bab6648'
SOURCE_HASH='8c6d55305934fbb2086fcbf3da2b895efff46933d7dfac764a9ce8fb81374f38'
GO_VERSION='go1.27.3'
parser=argparse.ArgumentParser()
parser.add_argument('--cache-dir',type=Path,required=True)
parser.add_argument('--work-dir',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
parser.add_argument('--go',default='go')
args=parser.parse_args()
for directory in [args.cache_dir,args.work_dir,args.output_dir]:directory.mkdir(parents=True,exist_ok=True)
archive=args.cache_dir/('ddns-go-'+COMMIT+'.tar.gz')
url='https://codeload.github.com/jeessy2/ddns-go/tar.gz/'+COMMIT
if not archive.exists():
 data=urllib.request.urlopen(url,timeout=90).read()
 if hashlib.sha256(data).hexdigest()!=SOURCE_HASH:raise SystemExit('源码校验失败')
 archive.write_bytes(data)
if hashlib.sha256(archive.read_bytes()).hexdigest()!=SOURCE_HASH:raise SystemExit('缓存源码校验失败')
# 每次使用独立的小型组件目录，退出时删除，不复制固件源码树。
source_context=tempfile.TemporaryDirectory(prefix='ddns-go-source-',dir=args.work_dir)
source=Path(source_context.name)
with tarfile.open(archive) as tf:
 for member in tf.getmembers():
  parts=Path(member.name).parts[1:]
  if not parts:continue
  if member.issym() or member.islnk() or '..' in parts or any(p.startswith('/') for p in parts):raise SystemExit('源码路径无效')
  target=source.joinpath(*parts)
  if member.isdir():target.mkdir(parents=True,exist_ok=True)
  elif member.isfile():
   target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(tf.extractfile(member).read())
env={**os.environ,'GOTOOLCHAIN':GO_VERSION,'GOOS':'linux','GOARCH':'mipsle','GOMIPS':'softfloat','CGO_ENABLED':'0'}
version=subprocess.check_output([args.go,'version'],env=env,text=True).strip()
if (' '+GO_VERSION+' ') not in version:raise SystemExit('Go 版本不匹配：'+version)
binary=args.work_dir/'ddns-go'
subprocess.run([args.go,'build','-trimpath','-buildvcs=false','-ldflags=-s -w -X main.version=v'+VERSION,'-o',str(binary.resolve()),'.'],cwd=source,env=env,check=True)
metadata={'version':VERSION,'source_commit':COMMIT,'source_url':url,'source_sha256':SOURCE_HASH,'compiler':GO_VERSION,
 'target':'linux/mipsle/softfloat','official_source':True,'official_prebuilt_binary':False,
 'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest()}
name='ddns-go_'+VERSION+'_linux_mipsle_softfloat_padavan-go1.27.3.tar.gz'
output=args.output_dir/name
# 固定归档时间、所有者和顺序，便于校验重编产物。
with output.open('wb') as raw,gzip.GzipFile(filename='',fileobj=raw,mode='wb',mtime=0) as gz,tarfile.open(fileobj=gz,mode='w') as tf:
 for filename,data,mode in [('ddns-go',binary.read_bytes(),0o755),('LICENSE',(source/'LICENSE').read_bytes(),0o644),('BUILD.json',(json.dumps(metadata,indent=2)+'\n').encode(),0o644)]:
  info=tarfile.TarInfo(filename);info.size=len(data);info.mode=mode;info.mtime=0;tf.addfile(info,io.BytesIO(data))
metadata.update(archive=name,archive_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),archive_bytes=output.stat().st_size)
(args.output_dir/'ddns-go-compat-build.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps(metadata))
