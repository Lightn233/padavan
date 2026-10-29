#!/usr/bin/env python3
"""校验并安装 U5 的离线工具链；已有目录不覆盖、不删除。"""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ARCHIVE_SHA256 = '68c5769e33ff03d511f104775f2dd9db67c5c28dd16b019712b889b36b76bf30'
LIBC_SHA256 = 'c3c3d086debbd3c85285542c5bccb764540deced893140923eaf53bf69c49217'
TARGET = 'mipsel-linux-musl'

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def verify(prefix):
    gcc = prefix / 'bin' / (TARGET + '-gcc')
    ld = prefix / 'bin' / (TARGET + '-ld')
    def output(args):
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=15).strip()
    if output([str(gcc), '-dumpfullversion']) != '16.2.0':
        raise RuntimeError('已有工具链的 GCC 不是 16.2.0；请自行保留旧目录后选择新的安装位置。')
    if output([str(gcc), '-dumpmachine']) != TARGET:
        raise RuntimeError('工具链目标架构不符。')
    if not output([str(ld), '--version']).splitlines()[0].endswith(' 2.47'):
        raise RuntimeError('binutils 版本不符。')
    if digest(prefix / TARGET / 'sysroot/usr/lib/libc.so') != LIBC_SHA256:
        raise RuntimeError('musl 库与已验证的安全修复版本不符。')
    if not (prefix / TARGET / 'sysroot/usr/include/sys/queue.h').is_file():
        raise RuntimeError('缺少 Padavan 构建所需的 sys/queue.h。')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', required=True, type=Path)
    parser.add_argument('--prefix', required=True, type=Path)
    args = parser.parse_args()
    prefix = args.prefix.absolute()
    if os.path.lexists(prefix):
        verify(prefix)
        print('U5 工具链已存在，版本与 musl 摘要校验通过；未覆盖文件。')
        return
    if not args.archive.is_file():
        raise RuntimeError('未找到 U5 离线包：' + str(args.archive) + '。请复制交付的工具链归档到此处，或通过 TOOLCHAIN_ARCHIVE 指定路径；不会下载旧版本代替。')
    if digest(args.archive) != ARCHIVE_SHA256:
        raise RuntimeError('工具链归档 SHA256 不符，未解压或修改安装目录。')
    if not Path('/usr/bin/ccache').is_file():
        raise RuntimeError('缺少 /usr/bin/ccache，请先安装宿主构建依赖。')
    prefix.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix='.u5-toolchain-', dir=prefix.parent))
    try:
        # 仅解包摘要固定、已经审查过目录及符号链接的交付包。
        subprocess.run(['tar', '-xJf', str(args.archive.absolute()), '-C', str(temporary)], check=True, timeout=180)
        verify(temporary)
        if os.path.lexists(prefix):
            raise RuntimeError('安装位置已被另一个进程创建，停止安装。')
        temporary.rename(prefix)
        print('U5 工具链安装及校验通过：' + str(prefix))
    finally:
        # 仅清理本进程创建的临时目录；安装成功后该目录已改名。
        if temporary.exists():
            assert temporary.parent == prefix.parent and temporary.name.startswith('.u5-toolchain-')
            shutil.rmtree(temporary)

if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
