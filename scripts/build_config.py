#!/usr/bin/env python3
"""编译前的中文配置入口：个人选择按机型保存，公共模板保持独立。"""
from pathlib import Path
import argparse
import os
import re
import shlex
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'CONFIG_FIRMWARE_'
OC = PREFIX + 'INCLUDE_OC'
FREQ = PREFIX + 'MT7621_OC'
RAM = PREFIX + 'RAM_SIZE'
TMP = PREFIX + 'TMPFS_TMP_MIB'
ETC = PREFIX + 'TMPFS_ETC_MIB'
CLOCKS = {'1000': '0x312', '1100': '0x362', '1120': '0x372', '1200': '0x3B2'}
RAM_OPTIONS = (16, 32, 64, 128, 256, 512)
TMP_OPTIONS = (0, 8, 16, 24, 32, 64, 128)
ETC_OPTIONS = (0, 4, 6, 8, 16, 32)

# 名称、用途与依赖放在一起，菜单和文档查看共用同一份说明。
GROUPS = {
    'DNS、远程访问与 IPTV': [
        ('ADGUARDHOME', 'AdGuard Home', '过滤广告和管理 DNS；保留官方程序及在线更新。'),
        ('SMARTDNS', 'SmartDNS', '查询多个上游 DNS；同时使用 AdGuard Home 时需规划监听端口。'),
        ('DNSFORWARDER', '旧 DNS 转发入口', '兼容旧配置并迁移到独立 SmartDNS；普通用户通常不需要同时开启。'),
        ('DDNS_GO', 'DDNS-Go', '自动更新域名的 A/AAAA 地址；需要自己的域名和服务商账号。'),
        ('ALIDDNS', '旧 AliDDNS 入口', '保留旧配置迁移入口；新用户优先使用 DDNS-Go。'),
        ('MSD_LITE', 'msd_lite IPTV', '将运营商 IPTV 多播转为 HTTP；仍需实际 IPTV 线路。'),
        ('RTP2HTTPD', 'rtp2httpd IPTV', '另一种 IPTV 多播转 HTTP 服务；一般按需求选择一种。'),
        ('XUPNPD', 'xUPnPd', '通过 DLNA/UPnP 分享 IPTV 播放列表。'),
        ('FRPC', 'FRP 客户端', '连接你自己的 FRP 服务端进行内网穿透。'),
        ('FRPS', 'FRP 服务端', '接收 FRP 客户端连接；需要可达的服务端网络。'),
    ],
    'VPN 与组网': [
        ('OPENVPN', 'OpenVPN', '远程访问 VPN；需要自己的服务器、证书或账号配置。'),
        ('WIREGUARD', 'WireGuard', '基于密钥的 VPN；需要配置对端。'),
        ('ZEROTIER', 'ZeroTier', '虚拟局域网；需要自己的网络或控制器。'),
        ('TAILSCALE', 'Tailscale', '基于账号的组网；当前集成使用 userspace 模式。'),
        ('SOFTETHERVPN_SERVER', 'SoftEther 服务端', 'VPN 服务端；占用较多固件空间和运行内存。'),
        ('SOFTETHERVPN_CLIENT', 'SoftEther 客户端', '连接 SoftEther VPN；需另行配置服务器。'),
        ('SOFTETHERVPN_CMD', 'SoftEther 管理工具', '命令行管理 SoftEther，不会自动建立隧道。'),
    ],
    '代理与兼容入口': [
        ('SHADOWSOCKS', 'Shadowsocks', '代理客户端及管理入口；需要自己的合法服务配置。'),
        ('XRAY', 'Xray', '多协议代理核心；体积较大，只按实际需要选择。'),
        ('V2RAY', 'V2Ray', '另一种多协议代理核心；通常无须和多个同类核心一起内置。'),
        ('SINGBOX', 'Sing-box', '多协议代理与路由核心；需要匹配版本的配置。'),
        ('MIHOMO', 'Mihomo', '规则代理核心；需另行提供配置，编译启用不等于已有服务。'),
        ('TROJAN', '旧 Trojan 入口', '迁移到兼容核心或保留旧实现，兼容已有配置。'),
        ('SSOBFS', 'simple-obfs 兼容', '仅为需要旧 HTTP/TLS 混淆的服务保留。'),
    ],
    '存储与下载': [
        ('SMBD', 'Samba 文件共享', '在局域网共享磁盘；需要 USB/存储硬件和对应驱动。'),
        ('FTPD', 'FTP 文件服务', '共享本地存储；需要实际存储设备。'),
        ('TRANSMISSION', 'Transmission', 'BT 下载；需要足够持久存储，不适合用小容量 RAM 目录下载。'),
        ('ARIA', 'aria2', 'HTTP/BT 下载；需要足够持久存储。'),
        ('ARIA_WEB_CONTROL', 'aria2 管理页面', 'aria2 的网页控制界面，必须同时开启 aria2。'),
        ('MINIDLNA', 'MiniDLNA', '向电视等设备分享媒体文件；需要存储和相应依赖。'),
    ],
    '校园认证与维护工具': [
        ('MENTOHUST', 'MentoHUST', '校园网认证；实际能否使用取决于学校认证服务器。'),
        ('MINIEAP', 'MiniEAP', '802.1X/锐捷兼容认证；需要本校账号和匹配配置。'),
        ('SCUTCLIENT', 'scutclient', '校园认证兼容客户端，按学校网络选择。'),
        ('GDUT_DRCOM', 'GDUT Dr.COM', '对应 Dr.COM 认证流程的兼容客户端。'),
        ('DOGCOM', 'dogcom', 'Dr.COM 兼容客户端，按实际认证环境选择。'),
        ('TCPDUMP', 'tcpdump', '记录网络流量以诊断网络问题；抓包会占用空间。'),
        ('IPERF3', 'iperf3', '与另一台运行 iperf3 的设备测吞吐，测试期间会占用带宽。'),
        ('HTOP', 'htop', '在 SSH 中查看进程和 CPU/内存使用。'),
        ('NANO', 'nano', '终端文本编辑器。'),
        ('TTYD', '网页终端 ttyd', '在浏览器中使用终端，启用后仍需妥善设置认证。'),
    ],
}
LANGUAGES = {'CN': '简体中文', 'BR': '葡萄牙语（巴西）', 'CZ': '捷克语', 'DA': '丹麦语',
             'DE': '德语', 'FI': '芬兰语', 'FR': '法语', 'NO': '挪威语', 'PL': '波兰语',
             'RU': '俄语', 'SV': '瑞典语', 'UK': '乌克兰语'}


def read_config(path):
    result = {}
    if not path.exists():
        return result
    for line in path.read_text(encoding='utf-8').splitlines():
        off = re.fullmatch(r'\s*#\s+(CONFIG_[A-Za-z0-9_]+) is not set\s*', line)
        if off:
            result[off[1]] = 'n'
            continue
        if not re.match(r'^CONFIG_[A-Za-z0-9_]+=', line):
            continue
        key, value = line.split('=', 1)
        tokens = shlex.split(value, comments=True)
        result[key] = ' '.join(tokens)
    return result


def models(root):
    return sorted(p.stem for p in (root / 'trunk/configs/templates').glob('*.config'))


def model_data(root, model):
    if model not in models(root):
        raise ValueError('机型不存在，请运行 make menuconfig 选择仓库中的机型。')
    template = read_config(root / 'trunk/configs/templates' / (model + '.config'))
    board = template['CONFIG_FIRMWARE_PRODUCT_ID']
    if not re.fullmatch(r'[A-Za-z0-9_-]+', board):
        raise ValueError('机型模板中的板级名称无效。')
    board_cfg = read_config(root / 'trunk/configs/boards' / board / 'board.mk')
    return template, board_cfg


def base_config(root, model):
    template, _ = model_data(root, model)
    template.update(read_config(root / 'hello/common.override'))
    return template


def effective_config(root, model):
    result = base_config(root, model)
    result.update(read_config(root / 'hello/local' / (model + '.override')))
    return result


def ram_size(root, model, cfg):
    _, board = model_data(root, model)
    return int(cfg.get(RAM, '0') or '0') or int(board.get('CONFIG_BOARD_RAM_SIZE', '128'))


def validate(root, model, cfg):
    template, _ = model_data(root, model)
    for key in ('CONFIG_PRODUCT', 'CONFIG_FIRMWARE_PRODUCT_ID'):
        if cfg.get(key) != template.get(key):
            raise ValueError('本地覆盖不能更改机型身份，请使用 make <机型> 选择。')
    if cfg.get(OC, 'n') not in ('y', 'n'):
        raise ValueError('超频开关只能为 y 或 n。')
    if cfg.get(OC) == 'y':
        if cfg.get('CONFIG_PRODUCT') != 'MT7621':
            raise ValueError('当前 CPU 调频入口只支持 MT7621。')
        if cfg.get(FREQ, '').lower() not in [v.lower() for v in CLOCKS.values()]:
            raise ValueError('CPU 频率参数不在已定义的菜单档位内，请重新选择。')
    for key, allowed in ((RAM, (0,) + RAM_OPTIONS), (TMP, TMP_OPTIONS), (ETC, ETC_OPTIONS)):
        if not re.fullmatch(r'0|[1-9][0-9]*', cfg.get(key, '0')) or int(cfg.get(key, '0')) not in allowed:
            raise ValueError(key + ' 数值无效，请从菜单中选择容量。')
    memory = ram_size(root, model, cfg)
    tmp = int(cfg.get(TMP, '0'))
    etc = int(cfg.get(ETC, '0'))
    auto_tmp, auto_etc = (64, 16) if memory >= 512 else (8 if memory <= 32 else 24, 6)
    if (tmp or etc) and (tmp or auto_tmp) + (etc or auto_etc) > memory // 2:
        raise ValueError('/tmp 与 /etc 的自定义上限合计超过内存的一半，请减小容量或使用自动值。')
    for suffix, needs in (('ARIA_WEB_CONTROL', PREFIX + 'INCLUDE_ARIA'),):
        if cfg.get(PREFIX + 'INCLUDE_' + suffix) == 'y' and cfg.get(needs) != 'y':
            raise ValueError(suffix + ' 需要同时启用 ' + needs)


def transitions(root, model):
    new = effective_config(root, model)
    validate(root, model, new)
    old = read_config(root / 'trunk/.config')
    if not old:
        return
    artifacts = (root / 'trunk' / old.get('CONFIG_LINUXDIR', 'linux-4.4.x') / 'vmlinux',
                 root / 'trunk/user/rc/src/rc')
    if not any(p.exists() for p in artifacts):
        return
    old_board = read_config(root / 'trunk/user/board.mk')
    old_ram = int(old.get(RAM, '0') or '0') or int(old_board.get('CONFIG_BOARD_RAM_SIZE', '128'))
    old_clock = old.get(FREQ, '').lower() if old.get(OC) == 'y' else 'off'
    new_clock = new.get(FREQ, '').lower() if new.get(OC) == 'y' else 'off'
    old_model = old.get('CONFIG_BUILD_MODEL', old.get('CONFIG_FIRMWARE_PRODUCT_ID'))
    switches = {key for key in old.keys() | new.keys()
                if key.startswith((PREFIX + 'INCLUDE_', PREFIX + 'ENABLE_'))}
    changed_switches = [key for key in switches if old.get(key, 'n') != new.get(key, 'n')]
    if old_model != model or old_ram != ram_size(root, model, new) or old_clock != new_clock or changed_switches:
        raise ValueError('机型、CPU、内存规格或编译功能已变化，目录中仍有旧编译产物。\n'
                         '请先执行 make clean，再执行 make ' + model + '。个人菜单选择会保留。')


def choices(title, values, current=None):
    print('\n' + title)
    for i, (value, label) in enumerate(values, 1):
        print(f'  {i}. {label}' + (' [当前]' if value == current else ''))
    while True:
        answer = input('输入编号，直接回车保留当前，q 返回：').strip()
        if answer == 'q':
            return current
        if not answer and current is not None:
            return current
        if answer.isdigit() and 1 <= int(answer) <= len(values):
            return values[int(answer) - 1][0]
        print('请输入列表中的编号。')


def describe(root, model, cfg):
    base = base_config(root, model)
    _, board = model_data(root, model)
    print('\n机型：' + model)
    print('CPU：' + ('保持引导程序时钟（固件不超频）' if cfg.get(OC) != 'y' else
                     next((k + ' MHz（需自行验证稳定性）' for k, v in CLOCKS.items()
                           if v.lower() == cfg.get(FREQ, '').lower()), cfg.get(FREQ, '未指定'))))
    memory = ram_size(root, model, cfg)
    print(f'内存规格：{memory} MiB；原机板级默认 {board.get("CONFIG_BOARD_RAM_SIZE", "128")} MiB。物理容量由内核识别。')
    for key, label in ((TMP, '/tmp'), (ETC, '/etc')):
        value = cfg.get(key, '0')
        print(label + ' 上限：' + ('按启动时可用内存自动选择' if value == '0' else value + ' MiB'))
    changed = [(k, v) for k, v in cfg.items() if base.get(k) != v and k != 'CONFIG_BUILD_MODEL']
    print('相对公共默认的个人改动：')
    for key, value in sorted(changed):
        print('  ' + key + '=' + value)
    if not changed:
        print('  无')
    print('选择插件只决定是否打包，刷入后还需配置账号/服务；固件大小以实际构建结果为准。')


def save_config(root, model, cfg):
    validate(root, model, cfg)
    base = base_config(root, model)
    path = root / 'hello/local' / (model + '.override')
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ['# 本文件由中文配置菜单保存，仅作用于 ' + model + '，不提交 Git。',
             '# 恢复公共默认可在菜单中重置；手工修改说明见 docs/build-configuration.md。']
    for key, value in sorted(cfg.items()):
        if key == 'CONFIG_BUILD_MODEL' or base.get(key) == value:
            continue
        if not re.fullmatch(r'CONFIG_[A-Za-z0-9_]+', key) or '\n' in value or '\r' in value:
            raise ValueError('配置项格式无效。')
        # 使用 shell 单引号保留人工设置的字符串，禁止将其作为菜单命令执行。
        encoded = value if re.fullmatch(r'[A-Za-z0-9_./+-]+', value) else shlex.quote(value)
        lines.append(key + '=' + encoded)
    text = '\n'.join(lines) + '\n'
    if path.exists() and path.read_text(encoding='utf-8') == text:
        return path
    fd, name = tempfile.mkstemp(prefix='.config-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            stream.write(text)
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return path


def write_resources(root, config_path, target):
    cfg = read_config(config_path)
    validate(root, cfg.get('CONFIG_BUILD_MODEL', cfg.get('CONFIG_FIRMWARE_PRODUCT_ID', '')), cfg)
    target.parent.mkdir(parents=True, exist_ok=True)
    text = '# 编译生成的 RAM 目录上限，0 表示按实际内存自动选择。\n'
    text += 'TMPFS_TMP_MIB=' + cfg.get(TMP, '0') + '\n'
    text += 'TMPFS_ETC_MIB=' + cfg.get(ETC, '0') + '\n'
    target.write_text(text, encoding='utf-8')


def edit_plugins(root, model, cfg):
    while True:
        category = choices('插件类别；不清楚用途时保留默认。', [('back', '返回')] + [(k, k) for k in GROUPS], 'back')
        if category == 'back':
            return
        entries = [(PREFIX + 'INCLUDE_' + suffix, name, help_text) for suffix, name, help_text in GROUPS[category]]
        # 只展示当前模板或公共配置已经声明的构建入口。
        entries = [row for row in entries if row[0] in base_config(root, model)]
        while True:
            selected = choices(category, [('back', '返回类别')] +
                [(key, ('[开] ' if cfg.get(key) == 'y' else '[关] ') + name) for key, name, _ in entries], 'back')
            if selected == 'back':
                break
            _, name, help_text = next(row for row in entries if row[0] == selected)
            print('\n用途：' + help_text)
            print('公共默认：' + ('开启' if base_config(root, model).get(selected) == 'y' else '关闭'))
            value = choices(name, [('n', '不打包'), ('y', '打包此功能')], cfg.get(selected, 'n'))
            if value:
                cfg[selected] = value


def menu(root, model):
    if not sys.stdin.isatty():
        raise ValueError('菜单需要交互终端。自动构建请使用本地覆盖文件或直接 make <机型>，不会自动弹菜单。')
    if not model:
        model = choices('选择要编译的路由器机型', [(name, name) for name in models(root)])
        if model is None:
            return
    model_data(root, model)
    cfg = effective_config(root, model)
    while True:
        print('\nPadavan 编译配置：' + model)
        print('这里只修改下一次编译的本地选择，不连接或改动正在使用的路由器。')
        print('1. CPU 频率   2. 物理内存规格   3. 临时目录容量   4. 插件选择')
        print('5. 界面语言   6. 查看汇总       7. 恢复公共默认   s. 保存退出   q. 不保存退出')
        action = input('请选择：').strip().lower()
        if action == 'q':
            print('已退出，本地文件未改变。')
            return
        if action == '1':
            if cfg.get('CONFIG_PRODUCT') != 'MT7621':
                print('该机型不使用 MT7621，保留原有 CPU 设置。')
                continue
            print('用途：提高 CPU 运算频率。默认不超频；发热、供电和每颗芯片的稳定性不同。')
            print('默认关闭仅表示固件不重写时钟，不会撤销引导程序里已有的超频。')
            current = cfg.get(FREQ) if cfg.get(OC) == 'y' else 'off'
            value = choices('CPU 选择', [('off', '不超频（默认）')] + [(v, k + ' MHz') for k, v in CLOCKS.items()], current)
            if value == 'off':
                cfg[OC] = 'n'
                cfg[FREQ] = base_config(root, model).get(FREQ, '0x312')
            elif value:
                cfg[OC], cfg[FREQ] = 'y', value
        elif action == '2':
            print('用途：按实际焊接的 RAM 容量设置缓存和连接数。不是 Flash，也不会增加物理内存。')
            print('未改装请选机型默认；换过内存才选择对应容量，内核仍自动识别实际 RAM。')
            default_ram = ram_size(root, model, {})
            value = choices('内存规格', [('0', f'机型默认（{default_ram} MiB）')] +
                            [(str(n), f'{n} MiB（必须与实际硬件一致）') for n in RAM_OPTIONS], cfg.get(RAM, '0'))
            if value is not None:
                cfg[RAM] = value
        elif action == '3':
            print('用途：限制 RAM 临时文件的最大容量；按使用量占内存，断电会丢失。')
            print('/etc/storage 运行时共用 /etc，保存机制和 Flash Storage 分区大小不随这个选项改变。')
            print('默认自动；可用 RAM 达 256 MiB 时为 /tmp 64、/etc 16 MiB，普通模式为 24/6 MiB。')
            print('低内存启动模式保留原限制；自动按 MemTotal 判断，不是按标称容量判断。')
            for key, label, options in ((TMP, '/tmp', TMP_OPTIONS), (ETC, '/etc', ETC_OPTIONS)):
                value = choices(label, [(str(n), '自动（默认）' if n == 0 else str(n) + ' MiB') for n in options], cfg.get(key, '0'))
                if value is not None:
                    cfg[key] = value
        elif action == '4':
            edit_plugins(root, model, cfg)
        elif action == '5':
            print('用途：增加管理页面语言资源；英语基础资源保留，多选会增大固件。')
            rows = [(PREFIX + 'INCLUDE_LANG_' + k, label) for k, label in LANGUAGES.items()]
            selected = choices('选择要更改的语言', [('back', '返回')] +
                [(key, ('[开] ' if cfg.get(key) == 'y' else '[关] ') + label) for key, label in rows], 'back')
            if selected != 'back':
                cfg[selected] = 'n' if cfg.get(selected) == 'y' else 'y'
        elif action == '6':
            describe(root, model, cfg)
        elif action == '7':
            if input('恢复该机型公共默认，保存后生效。输入 yes 确认：').strip().lower() == 'yes':
                cfg = base_config(root, model)
        elif action == 's':
            try:
                validate(root, model, cfg)
                describe(root, model, cfg)
                if input('确认保存这些选择？输入 yes 保存，其他输入返回：').strip().lower() != 'yes':
                    continue
                path = save_config(root, model, cfg)
                print('已保存：' + str(path.relative_to(root)))
                print('开始编译：make ' + model)
                print('改变机型、CPU、内存或编译功能时先 make clean；清理不会删除个人选择。')
                return
            except ValueError as error:
                print('未保存：' + str(error))
        else:
            print('请输入菜单中列出的编号或字母。')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--menu', metavar='MODEL')
    group.add_argument('--show', metavar='MODEL')
    group.add_argument('--check-transition', metavar='MODEL')
    group.add_argument('--validate-config', nargs=2, metavar=('MODEL', 'PATH'))
    group.add_argument('--write-resources', nargs=2, metavar=('CONFIG', 'OUTPUT'))
    args = parser.parse_args()
    try:
        if args.menu is not None:
            menu(ROOT, args.menu)
        elif args.show is not None:
            cfg = effective_config(ROOT, args.show)
            validate(ROOT, args.show, cfg)
            describe(ROOT, args.show, cfg)
        elif args.check_transition is not None:
            transitions(ROOT, args.check_transition)
        elif args.validate_config:
            model, path = args.validate_config
            validate(ROOT, model, read_config(Path(path)))
        else:
            source, target = args.write_resources
            write_resources(ROOT, Path(source), Path(target))
    except (ValueError, KeyError, OSError) as error:
        print('配置错误：' + str(error), file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print('\n已取消，未保存。', file=sys.stderr)
        return 130
    return 0


if __name__ == '__main__':
    sys.exit(main())
