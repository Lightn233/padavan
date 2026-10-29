#!/usr/bin/env python3
"""从源码独立构建 MIPS 工具链；不依赖旧交叉编译器或旧目标运行库。"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, shutil, subprocess, tarfile, time

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--manifest', type=Path, required=True)
ap.add_argument('--work', type=Path, required=True)
ap.add_argument('--prefix', type=Path, required=True)
ap.add_argument('--kernel', type=Path, required=True)
ap.add_argument('--jobs', type=int, default=4)
a = ap.parse_args()
assert os.geteuid() != 0, '请使用普通用户构建工具链'
assert 1 <= a.jobs <= 64
R, P, K = a.work.resolve(), a.prefix.absolute(), a.kernel.resolve()
assert not P.is_symlink(), '不覆盖现有工具链链接'
assert P.resolve().is_relative_to(R) and P.resolve() != R
assert K.is_dir() and not K.is_relative_to(R)
manifest = json.loads(a.manifest.read_text())
target = 'mipsel-linux-musl'
S = P / target / 'sysroot'
R.mkdir(parents=True, exist_ok=True)
for n in ('logs', 'src', 'build', 'evidence'):
    (R / n).mkdir(exist_ok=True)
statepath = R / 'build-state.json'
identity = {'manifest': manifest, 'prefix': str(P), 'kernel': str(K), 'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
if statepath.exists():
    state = json.loads(statepath.read_text())
    assert state['identity'] == identity, '构建输入变化，请换用空的工作目录'
else:
    assert not P.exists(), '拒绝覆盖未由本次构建创建的工具链'
    state = {'identity': identity, 'started': datetime.datetime.now().astimezone().isoformat(), 'steps': [], 'state': 'preparing', 'hardware_tested': False}

def save():
    q = statepath.with_suffix('.tmp')
    q.write_text(json.dumps(state, ensure_ascii=False, indent=2))
    q.replace(statepath)

def digest(path, algorithm='sha256'):
    h = hashlib.new(algorithm)
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''):
            h.update(b)
    return h.hexdigest()

def done(name):
    return any(x['name'] == name and x.get('exit') == 0 for x in state['steps'])

def run(name, argv, cwd=R, extra=None, timeout=14400):
    if done(name):
        return
    if shutil.disk_usage(R).free < 512 * 1024**2:
        raise RuntimeError('独立编译盘空间不足，保留日志并停止')
    item = {'name': name, 'argv': list(map(str, argv)), 'cwd': str(cwd), 'started': time.time()}
    state['state'] = name
    state['steps'].append(item)
    save()
    # 只允许本轮新编译器和宿主工具进入搜索路径。
    env = dict(os.environ, PATH=str(P / 'bin') + ':/usr/bin:/bin', LC_ALL='C', CCACHE_DISABLE='1', CFLAGS='-O2 -g0', CXXFLAGS='-O2 -g0')
    for n in ('CC', 'CXX', 'AR', 'AS', 'LD', 'RANLIB', 'CROSS_COMPILE', 'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'LD_LIBRARY_PATH'):
        env.pop(n, None)
    env.update(extra or {})
    with (R / 'logs' / (name + '.log')).open('w') as f:
        p = subprocess.run(item['argv'], cwd=cwd, env=env, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
    item.update(exit=p.returncode, seconds=round(time.time() - item['started'], 3))
    save()
    if p.returncode:
        raise RuntimeError(name + ' 失败，请查看对应日志')

def extract(name):
    entry = manifest[name]
    path = Path(entry['path'])
    assert digest(path, entry.get('algorithm', 'sha256')) == entry['hash'], name + ' 校验失败'
    dest = R / 'src' / entry['directory']
    marker = dest / '.rm2100-unpacked'
    if not marker.exists():
        assert not dest.exists(), '存在未完成解包目录，需检查后处理'
        with tarfile.open(path) as t:
            for m in t.getmembers():
                q = (R / 'src' / m.name).resolve()
                assert q.is_relative_to(dest) and not m.isdev()
                if m.issym():
                    assert (q.parent / m.linkname).resolve().is_relative_to(dest)
                if m.islnk():
                    assert (R / 'src' / m.linkname).resolve().is_relative_to(dest)
            t.extractall(R / 'src')
        marker.write_text(entry['hash'])
    return dest

def builddir(name):
    d = R / 'build' / name
    d.mkdir(exist_ok=True)
    return d

def musl(stage, source):
    d = builddir(stage)
    run(stage + '-configure', [source / 'configure', '--target=' + target, '--prefix=/usr', '--syslibdir=/lib', '--disable-wrapper', 'CC=' + str(P / 'bin' / (target + '-gcc')), 'CFLAGS=-Os -g0 -mabi=32 -march=mips32r2'], d)
    run(stage + '-make', ['make', '-j' + str(a.jobs)], d)
    run(stage + '-install', ['make', 'install', 'DESTDIR=' + str(S)], d)
    loader = S / 'lib/ld-musl-mipsel.so.1'
    assert loader.is_symlink()
    loader.unlink()
    loader.symlink_to('../usr/lib/libc.so')

try:
    save()
    bsrc, gsrc, msrc = [extract(n) for n in ('binutils', 'gcc', 'musl')]
    for patch in manifest['musl_patches']:
        path = Path(patch['path'])
        assert digest(path) == patch['sha256']
        run('musl-patch-' + path.stem, ['patch', '-p1', '--fuzz=0', '--batch', '-i', path], msrc)
    # 发布源码沿用该项目先前核实的正式版标志。
    dev = bsrc / 'bfd/development.sh'
    if not done('binutils-configure'):
        text = dev.read_text()
        dev.write_text(text.replace('development=true', 'development=false').replace('experimental=true', 'experimental=false'))
    bd = builddir('binutils')
    run('binutils-configure', [bsrc / 'configure', '--target=' + target, '--prefix=' + str(P), '--with-sysroot=' + str(S), '--disable-nls', '--disable-gdb', '--disable-gdbserver', '--disable-sim', '--disable-gprofng', '--disable-gold', '--enable-deterministic-archives', '--without-debuginfod', '--without-zstd'], bd)
    run('binutils-make', ['make', '-j' + str(a.jobs)], bd)
    run('binutils-install', ['make', 'install'], bd)
    # 只复制头文件导出所需的内核源码，原内核配置与产物不参与写入。
    kh = R / 'src/kernel-headers'
    if not kh.exists():
        kh.mkdir()
        for rel in ('Makefile', 'Kbuild', 'arch/mips/Makefile', 'arch/mips/Kbuild.platforms'):
            p = K / rel
            if p.exists():
                q = kh / rel; q.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p, q)
        for rel in ('scripts', 'include/uapi', 'arch/mips/include'):
            shutil.copytree(K / rel, kh / rel, symlinks=True, ignore=shutil.ignore_patterns('*.o', '*.cmd', 'generated', 'include/config'))
        for p in (K / 'arch/mips').rglob('Platform'):
            q = kh / p.relative_to(K); q.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p, q)
    run('kernel-headers', ['make', 'ARCH=mips', 'CROSS_COMPILE=', 'headers_install', 'INSTALL_HDR_PATH=' + str(S / 'usr')], kh)
    # Padavan 的 PPP UAPI 引用了额外头文件，原 Kbuild 尚未列出导出项。
    # 只修正隔离副本的导出列表，不改正在使用的内核源码。
    uapi = kh / 'include/uapi/linux/Kbuild'
    entries = uapi.read_text()
    for name in ('if_pppolac.h', 'if_pppopns.h'):
        if (kh / 'include/uapi/linux' / name).exists() and ('header-y += ' + name) not in entries:
            entries += '\nheader-y += ' + name + '\n'
    uapi.write_text(entries)
    run('kernel-headers-vendor', ['make', 'ARCH=mips', 'CROSS_COMPILE=', 'headers_install', 'INSTALL_HDR_PATH=' + str(S / 'usr')], kh)
    basic = [gsrc / 'configure', '--target=' + target, '--prefix=' + str(P), '--with-sysroot=' + str(S), '--with-local-prefix=' + str(S), '--with-as=' + str(P / 'bin' / (target + '-as')), '--with-ld=' + str(P / 'bin' / (target + '-ld')), '--with-abi=32', '--with-arch=mips32r2', '--with-tune=mips32r2', '--with-float=hard', '--disable-bootstrap', '--disable-multilib', '--disable-nls', '--disable-plugin', '--disable-libgomp', '--disable-libssp', '--disable-libquadmath', '--disable-libquadmath-support', '--disable-libsanitizer', '--with-isl=no', '--with-gnu-ld']
    gd = builddir('gcc-bootstrap')
    run('gcc-bootstrap-configure', basic + ['--enable-languages=c', '--without-headers', '--with-newlib', '--disable-threads', '--disable-shared', '--disable-libatomic'], gd)
    run('gcc-bootstrap-make', ['make', '-j' + str(a.jobs), 'all-gcc'], gd)
    run('gcc-bootstrap-install', ['make', 'install-gcc'], gd)
    # 先安装新 musl 头文件，再生成静态 libgcc，消除对旧工具链的依赖。
    mh = builddir('musl-headers')
    run('musl-headers-configure', [msrc / 'configure', '--target=' + target, '--prefix=/usr', '--syslibdir=/lib', '--disable-wrapper', 'CC=' + str(P / 'bin' / (target + '-gcc'))], mh)
    run('musl-headers-install', ['make', 'install-headers', 'DESTDIR=' + str(S)], mh)
    run('libgcc-bootstrap-make', ['make', '-j' + str(a.jobs), 'all-target-libgcc', 'CFLAGS_FOR_TARGET=-O2 -g0 -mips32r2'], gd)
    run('libgcc-bootstrap-install', ['make', 'install-target-libgcc'], gd)
    musl('musl-bootstrap', msrc)
    gf = builddir('gcc-final')
    run('gcc-final-configure', basic + ['--enable-languages=c,c++', '--enable-__cxa_atexit', '--enable-threads=posix', '--enable-tls', '--enable-shared', '--enable-lto', '--enable-target-optspace', '--enable-long-long'], gf)
    run('gcc-final-make', ['make', '-j' + str(a.jobs), 'CFLAGS_FOR_TARGET=-O2 -g0 -mips32r2', 'CXXFLAGS_FOR_TARGET=-O2 -g0 -mips32r2'], gf)
    run('gcc-final-install', ['make', 'install'], gf)
    musl('musl-final', msrc)
    for entry in manifest.get('supplemental_headers', []):
        p = Path(entry['path']); assert digest(p) == entry['sha256']
        q = S / 'usr/include' / entry['destination']
        assert q.resolve().is_relative_to(S / 'usr/include')
        q.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(p, q)
    for f in (P / target / 'lib').iterdir():
        if f.name.startswith(('libgcc_s', 'libstdc++', 'libatomic', 'libsupc++')) and not f.is_dir():
            q = S / 'lib' / f.name
            if q.exists() or q.is_symlink(): q.unlink()
            if f.is_symlink(): q.symlink_to(os.readlink(f))
            else: shutil.copy2(f, q)
    for n in ('gcc', 'g++', 'ld', 'as'):
        run('version-' + n, [P / 'bin' / (target + '-' + n), '--version'])
    state.update(state='built-awaiting-tests', finished=datetime.datetime.now().astimezone().isoformat())
    save()
except Exception as e:
    state.update(state='failed', error=repr(e)); save(); raise
