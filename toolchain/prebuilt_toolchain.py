#!/usr/bin/env python3
"""从本项目 Release 取得固定摘要的预编译工具链，保留源码构建入口。"""
from pathlib import Path, PurePosixPath
import fcntl
import hashlib
import json
import os
import platform
import posixpath
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent

def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def specification():
    spec = json.loads((HERE / 'prebuilt-toolchain.json').read_text())
    assert spec['url'].startswith('https://github.com/Lightn233/padavan/releases/download/')
    assert len(spec['sha256']) == 64 and spec['bytes'] > 0
    return spec

def supported_host():
    return platform.system() == 'Linux' and platform.machine() in ('x86_64', 'amd64')

def fetch(archive, spec):
    archive = Path(archive)
    if archive.exists():
        if archive.stat().st_size != spec['bytes'] or digest(archive) != spec['sha256']:
            raise RuntimeError('本地预编译工具链摘要不符，未修改安装目录：' + str(archive))
        return archive
    archive.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + archive.name + '.', suffix='.part', dir=archive.parent)
    partial = Path(temporary)
    try:
        request = urllib.request.Request(spec['url'], headers={'User-Agent': 'Padavan-toolchain-bootstrap/1'})
        with os.fdopen(fd, 'wb') as target, urllib.request.urlopen(request, timeout=60) as response:
            size = 0
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                size += len(block)
                if size > spec['bytes']:
                    raise RuntimeError('工具链下载大小超过发布清单，已拒绝安装。')
                target.write(block)
        if partial.stat().st_size != spec['bytes'] or digest(partial) != spec['sha256']:
            raise RuntimeError('工具链下载不完整或 SHA256 不符，已拒绝安装。')
        partial.replace(archive)
        return archive
    finally:
        if partial.exists():
            partial.unlink()

def audit_archive(archive):
    with tarfile.open(archive, 'r:xz') as stream:
        links = set()
        members = stream.getmembers()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or member.isdev() or member.isfifo():
                raise RuntimeError('工具链归档含不安全条目：' + member.name)
            if member.issym() or member.islnk():
                links.add(path)
                if member.issym() and str(path).startswith('lib/ccache/') and member.linkname == '/usr/bin/ccache':
                    continue
                base = str(path.parent) if member.issym() else '.'
                target = PurePosixPath(posixpath.normpath(posixpath.join(base, member.linkname)))
                if target.is_absolute() or '..' in target.parts:
                    raise RuntimeError('工具链归档的链接越过安装目录：' + member.name)
        for member in members:
            if any(parent in links for parent in PurePosixPath(member.name).parents):
                raise RuntimeError('工具链归档含链接下的嵌套条目：' + member.name)

def install(archive, prefix, spec, verify, smoke):
    prefix = Path(prefix).absolute()
    prefix.parent.mkdir(parents=True, exist_ok=True)
    with prefix.with_name('.' + prefix.name + '.install.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if os.path.lexists(prefix):
            verify(prefix)
            return
        if Path(archive).stat().st_size != spec['bytes'] or digest(archive) != spec['sha256']:
            raise RuntimeError('预编译工具链摘要不符，未解包。')
        audit_archive(archive)
        if not Path('/usr/bin/ccache').is_file():
            raise RuntimeError('请先安装宿主构建依赖 ccache，或使用源码构建入口。')
        temporary = Path(tempfile.mkdtemp(prefix='.padavan-toolchain-', dir=prefix.parent))
        try:
            subprocess.run(['tar', '-xJf', str(Path(archive).absolute()), '-C', str(temporary)], check=True, timeout=180)
            verify(temporary)
            with tempfile.TemporaryDirectory(prefix='padavan-abi-') as work:
                smoke(temporary, Path(work))
            if os.path.lexists(prefix):
                raise RuntimeError('安装目录已被其他进程创建；保留它并停止安装。')
            temporary.rename(prefix)
        finally:
            if temporary.exists():
                assert temporary.parent == prefix.parent and temporary.name.startswith('.padavan-toolchain-')
                shutil.rmtree(temporary)
    print('本仓库预编译工具链已校验并安装：' + str(prefix))
