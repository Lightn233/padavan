#!/usr/bin/env python3
"""按 SoftEther FileIO.c 的 BuildHamcore 格式生成 Unix 资源包。

构建机使用 Python/zlib，无须执行目标架构程序。文件名长度字段包含
一个未写入的结尾零，整数为大端，排序与上游 ASCII 大小写无关比较一致。
"""
from pathlib import Path
import argparse
import os
import struct
import zlib


def pack(source, destination):
    source = Path(source).resolve(strict=True)
    destination = Path(destination)
    entries = []
    names = set()
    for path in source.rglob('*'):
        if not path.is_file():
            continue
        if path.is_symlink():
            raise ValueError('资源目录不接受符号链接: ' + str(path))
        name = str(path.relative_to(source)).replace(os.sep, '\\')
        if path.suffix.lower() in {'.exe', '.dll', '.sys', '.inf', '.cat', '.wav'}:
            continue
        if '\\node_modules\\' in name.lower():
            continue
        encoded = name.encode('ascii')
        key = encoded.lower()
        if key in names:
            raise ValueError('资源文件名大小写冲突: ' + name)
        names.add(key)
        data = path.read_bytes()
        entries.append((encoded, len(data), zlib.compress(data)))
    entries.sort(key=lambda entry: entry[0].lower())
    offset = 11 + sum(16 + len(name) for name, _, _ in entries)
    table = bytearray(b'HamCore' + struct.pack('>I', len(entries)))
    for name, size, data in entries:
        if max(size, len(data), offset + len(data)) > 0xffffffff:
            raise ValueError('资源包超过上游 32 位长度限制')
        table.extend(struct.pack('>I', len(name) + 1))
        table.extend(name)
        table.extend(struct.pack('>III', size, len(data), offset))
        offset += len(data)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + '.tmp')
    try:
        with temporary.open('wb') as output:
            output.write(table)
            for _, _, data in entries:
                output.write(data)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    print('hamcore: %d 个文件，%d 字节' % (len(entries), offset))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('destination')
    args = parser.parse_args()
    pack(args.source, args.destination)
