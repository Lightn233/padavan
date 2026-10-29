#!/usr/bin/env python3
"""识别本地官方程序包并生成构建信息；不运行包内程序。"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ASSET = 'AdGuardHome_linux_mipsle_softfloat.tar.gz'
VERSION = re.compile(rb'(?<=\x00)(v\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?)(?=\x00)')
HASH = re.compile(r'[0-9a-fA-F]{64}')


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def go_string(data, pos):
    length = 0
    for shift in range(0, 70, 7):
        if pos >= len(data):
            break
        part = data[pos]
        pos += 1
        length |= (part & 127) << shift
        if not part & 128:
            if length > 1024 * 1024 or pos + length > len(data):
                break
            return data[pos:pos + length], pos + length
    raise ValueError('Go 构建信息长度无效')


def binary_info(data):
    if len(data) < 32 or data[:6] != b'\x7fELF\x01\x01' or struct.unpack_from('<H', data, 18)[0] != 8:
        raise ValueError('主程序必须是 ELF 32 位 MIPS 小端程序')
    # 读取 Go 1.18 以后的内嵌构建信息，核对软浮点目标架构。
    pos = data.find(b'\xff Go buildinf:')
    if pos < 0 or pos + 32 > len(data) or not data[pos + 15] & 2:
        raise ValueError('无法读取 Go 构建信息，请使用官方原始预编译包')
    go_version, next_pos = go_string(data, pos + 32)
    module, _ = go_string(data, next_pos)
    if len(module) < 33 or module[-17:-16] != b'\n':
        raise ValueError('Go 模块信息格式无效')
    text = module[16:-16].decode('utf-8')
    if 'path\tgithub.com/AdguardTeam/AdGuardHome\n' not in text:
        raise ValueError('包内程序不是 AdGuard Home')
    settings = dict(line[6:].split('=', 1) for line in text.splitlines()
                    if line.startswith('build\t') and '=' in line[6:])
    expected = {'GOOS': 'linux', 'GOARCH': 'mipsle', 'GOMIPS': 'softfloat'}
    if any(settings.get(key) != value for key, value in expected.items()):
        raise ValueError('程序的 Go 目标必须为 linux/mipsle/softfloat')
    # 官方程序的版本是独立的零结尾字符串；不根据压缩包文件名猜测。
    versions = {match.group(1).decode('ascii') for match in VERSION.finditer(data)}
    if len(versions) != 1:
        raise ValueError('程序实际版本无法唯一识别：' + ', '.join(sorted(versions)))
    return {'version': versions.pop(), 'binary_hash': hashlib.sha256(data).hexdigest(),
            'binary_bytes': len(data), 'go_version': go_version.decode('ascii'), **expected}


def inspect(path):
    with tarfile.open(path, 'r:gz') as archive:
        member = next((item for item in archive
                       if item.isfile() and item.name.removeprefix('./') == 'AdGuardHome/AdGuardHome'), None)
        if member is None:
            return None
        if member.size > 256 * 1024 * 1024:
            raise ValueError('主程序超过 256 MiB，无法作为此设备的程序包导入')
        return binary_info(archive.extractfile(member).read())


def write_changed(path, data):
    if path.exists() and path.read_bytes() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as stream:
        try:
            import fcntl
        except ImportError:
            # Windows 本地验证只使用单进程；Linux 构建使用文件锁避免并发导入。
            fcntl = None
        if fcntl:
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            if fcntl:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def read_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}


def file_signature(path):
    info = path.stat()
    return [str(path.resolve()), info.st_size, info.st_mtime_ns]


def make_info(info):
    return ('# 自动生成：版本读取自主程序，校验值来自已核验的归档。\n'
            f'PKG_VERSION:={info["version"][1:]}\n'
            f'PKG_SOURCE:={info["source"]}\n'
            f'PKG_HASH:={info["archive_hash"]}\n'
            f'PKG_BINARY_HASH:={info["binary_hash"]}\n').encode('utf-8')


def parse_checksum(data):
    for line in data.splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[1].lstrip('*').removeprefix('./') == ASSET and HASH.fullmatch(fields[0]):
            return fields[0].lower()
    raise ValueError('官方校验文件中没有目标架构的有效 SHA256')


def fetch_official(version):
    url = f'https://github.com/AdguardTeam/AdGuardHome/releases/download/{version}/checksums.txt'
    if shutil.which('curl'):
        run = subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                              '--connect-timeout', '3', '--max-time', '8', url],
                             capture_output=True, timeout=10)
        if run.returncode:
            raise OSError(run.stderr.decode(errors='replace').strip())
        data = run.stdout.decode('utf-8')
    else:
        with urllib.request.urlopen(url, timeout=5) as response:
            data = response.read(1024 * 1024).decode('utf-8')
    return parse_checksum(data)


def resolve(args):
    download = Path(args.download_dir).resolve()
    metadata = Path(args.metadata).resolve()
    state_path = metadata.with_suffix('.json')
    seed_path = Path(__file__).with_name('official-checksums.json')
    cache_path = metadata.with_name('official-checksums-cache.json')
    download.mkdir(parents=True, exist_ok=True)
    for value in (args.package_hash, args.binary_hash):
        if value and not HASH.fullmatch(value):
            raise ValueError('手动校验值必须是完整的 64 位 SHA256')
    explicit = Path(args.archive).resolve() if args.archive else None
    if explicit and not explicit.is_file():
        raise ValueError('指定的程序包不存在：' + str(explicit))
    candidates = [explicit] if explicit else sorted(download.glob('AdGuardHome*.tar.gz'))
    signature = {'files': [file_signature(path) for path in candidates],
                 'manual_package_hash': args.package_hash.lower(),
                 'manual_binary_hash': args.binary_hash.lower(), 'remote': args.remote,
                 'script': file_signature(Path(__file__)), 'seed': file_signature(seed_path)}
    with locked(metadata.with_suffix('.lock')):
        state = read_json(state_path)
        if state.get('signature') == signature and state.get('info'):
            write_changed(metadata, make_info(state['info']))
            return
        selected = None
        # 明确指定时严格使用指定包；否则选择最近放入的有效预编译包。
        for path in sorted(candidates, key=lambda item: (item.stat().st_mtime_ns, item.name), reverse=True):
            try:
                info = inspect(path)
            except (ValueError, tarfile.TarError, OSError) as exc:
                raise ValueError(f'程序包 {path.name} 无效：{exc}') from exc
            if info:
                selected = path
                break
        if selected is None:
            raise ValueError('download 中没有官方预编译程序包；请放入 AdGuardHome*.tar.gz，或填写 ADG_PACKAGE')
        archive_hash = sha256(selected)
        if args.package_hash and archive_hash != args.package_hash.lower():
            raise ValueError('压缩包与手动填写的 PKG_HASH 不一致')
        if args.binary_hash and info['binary_hash'] != args.binary_hash.lower():
            raise ValueError('主程序与手动填写的 PKG_BINARY_HASH 不一致')
        if args.package_hash:
            verification = 'manual'
        else:
            cached = {**read_json(seed_path), **read_json(cache_path)}
            official = cached.get(info['version'])
            if official:
                verification = 'official-cache'
            elif args.remote == '1':
                try:
                    official = fetch_official(info['version'])
                    verification = 'official-network'
                except (OSError, ValueError, subprocess.SubprocessError) as exc:
                    raise ValueError(
                        f'联网核对 {info["version"]} 失败：{exc}\n'
                        f'本地已计算 PKG_HASH={archive_hash}\n'
                        f'本地已计算 PKG_BINARY_HASH={info["binary_hash"]}\n'
                        '请从可信来源核对后，在 prebuilt.local.mk 中填写 PKG_HASH；'
                        'PKG_BINARY_HASH 可自动计算，也可以手动填写。') from exc
            else:
                raise ValueError('此版本没有官方校验缓存；离线导入请在 prebuilt.local.mk 填写 PKG_HASH')
            if archive_hash != official:
                raise ValueError('压缩包与官方发布的 SHA256 不一致，已停止导入')
            cached[info['version']] = official
            write_changed(cache_path, (json.dumps(cached, indent=2) + '\n').encode())
        canonical_name = f'AdGuardHome-{info["version"][1:]}-linux_mipsle_softfloat.tar.gz'
        canonical = download / canonical_name
        if selected != canonical:
            if not canonical.exists() or sha256(canonical) != archive_hash:
                temporary = canonical.with_suffix('.import')
                shutil.copy2(selected, temporary)
                os.replace(temporary, canonical)
        info.update(source=canonical_name, archive_hash=archive_hash,
                    selected_archive=str(selected), verification=verification)
        # 复制后的文件纳入缓存签名，下一次构建无需重复解包或联网。
        candidates = [explicit] if explicit else sorted(download.glob('AdGuardHome*.tar.gz'))
        signature['files'] = [file_signature(path) for path in candidates]
        state = {'signature': signature, 'info': info}
        write_changed(state_path, (json.dumps(state, ensure_ascii=False, indent=2) + '\n').encode())
        write_changed(metadata, make_info(info))
        print(f'已识别 {info["version"]}（linux/mipsle/softfloat），校验来源：{verification}')


def unpack(args):
    source, destination = Path(args.archive), Path(args.destination)
    if sha256(source) != args.package_hash.lower():
        raise ValueError('解包前归档校验失败')
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(source, 'r:gz') as archive:
        for member in archive:
            normalized = member.name.removeprefix('./')
            if not member.isfile() or not normalized.startswith('AdGuardHome/'):
                continue
            name = normalized.removeprefix('AdGuardHome/')
            if '/' in name or name not in ('AdGuardHome', 'AdGuardHome.sig', 'README.md', 'CHANGELOG.md', 'LICENSE.txt'):
                continue
            with archive.extractfile(member) as incoming, (destination / name).open('wb') as outgoing:
                shutil.copyfileobj(incoming, outgoing)
    if not (destination / 'AdGuardHome').is_file():
        raise ValueError('归档未提供主程序')
    (destination / 'AdGuardHome').chmod(0o755)


def main():
    parser = argparse.ArgumentParser(description='自动识别 AdGuard Home 官方预编译包')
    actions = parser.add_subparsers(dest='action', required=True)
    select = actions.add_parser('resolve')
    select.add_argument('--download-dir', required=True)
    select.add_argument('--metadata', required=True)
    select.add_argument('--archive', default='')
    select.add_argument('--package-hash', default='')
    select.add_argument('--binary-hash', default='')
    select.add_argument('--remote', choices=('0', '1'), default='1')
    extract = actions.add_parser('unpack')
    extract.add_argument('--archive', required=True)
    extract.add_argument('--destination', required=True)
    extract.add_argument('--package-hash', required=True)
    args = parser.parse_args()
    try:
        (resolve if args.action == 'resolve' else unpack)(args)
    except (ValueError, OSError, tarfile.TarError) as exc:
        print('AdGuard Home 程序包处理失败：' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
