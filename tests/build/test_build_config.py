"""在独立小目录验证真实菜单、构建入口与资源配置，不运行完整固件编译。"""
from pathlib import Path
import importlib.util
import json
import os
import pty
import select
import shutil
import subprocess
import tempfile
import time
import unittest

SOURCE = Path(__file__).resolve().parents[2]


def load(path):
    spec = importlib.util.spec_from_file_location('build_config', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='padavan-config-test-')
        self.root = Path(self.temp.name)
        # 仅复制配置和脚本，测试不写源码、构建缓存或工具链。
        for directory in ('trunk/configs/templates', 'trunk/configs/boards'):
            for source in (SOURCE / directory).rglob('*'):
                if source.is_file() and (source.suffix == '.config' or source.name == 'board.mk'):
                    target = self.root / source.relative_to(SOURCE)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, target)
        for relative in ('Makefile', 'hello/common.override', 'scripts/build_config.py',
                         'scripts/apply_overrides.sh', 'trunk/configure', 'trunk/user/boards.mk'):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / relative, target)
        self.bc = load(self.root / 'scripts/build_config.py')
        self.cfg = self.bc.effective_config(self.root, 'RM2100')
        self.apply = self.root / 'scripts/apply_overrides.sh'
        self.apply.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def write_project(self, cfg=None, model='RM2100'):
        cfg = dict(cfg or self.cfg)
        cfg['CONFIG_BUILD_MODEL'] = model
        (self.root / 'trunk/.config').write_text(''.join(k + '=' + json.dumps(v) + '\n' for k, v in cfg.items()))

    def configure(self, cfg=None, model='RM2100'):
        self.write_project(cfg, model)
        for relative in ['trunk/vendors/Ralink/config.arch', 'trunk/configs/boards/' + self.bc.model_data(self.root, model)[0]['CONFIG_FIRMWARE_PRODUCT_ID'] + '/board.h']:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / relative, path)
        for relative in ['trunk/linux-4.4.x', 'trunk/user/busybox/busybox-1.38.0',
                         'trunk/user/busybox/busybox-1.24.x', 'trunk/user/shared/src/include']:
            (self.root / relative).mkdir(parents=True, exist_ok=True)
        result = subprocess.run(['bash', 'configure'], cwd=self.root / 'trunk', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return self.bc.read_config(self.root / 'trunk/linux-4.4.x/.config')

    def test_default_is_stock(self):
        self.assertEqual(self.cfg[self.bc.OC], 'n')
        self.assertEqual(self.bc.ram_size(self.root, 'RM2100', self.cfg), 128)
        self.bc.validate(self.root, 'RM2100', self.cfg)

    def test_all_templates_default_validate(self):
        for model in self.bc.models(self.root):
            with self.subTest(model=model):
                self.bc.validate(self.root, model, self.bc.effective_config(self.root, model))

    def test_model_isolation(self):
        changed = {**self.cfg, self.bc.RAM: '512', self.bc.OC: 'y', self.bc.FREQ: '0x362'}
        self.bc.save_config(self.root, 'RM2100', changed)
        self.assertEqual(self.bc.effective_config(self.root, 'RM2100')[self.bc.RAM], '512')
        self.assertNotIn(self.bc.RAM, self.bc.effective_config(self.root, 'K2P'))
        self.assertNotIn(self.bc.RAM, self.bc.effective_config(self.root, 'K2P-NANO'))

    def test_local_override_wins_in_real_apply_script(self):
        self.bc.save_config(self.root, 'RM2100', {**self.cfg, self.bc.RAM: '512', self.bc.OC: 'y', self.bc.FREQ: '0x362'})
        self.write_project()
        result = subprocess.run(['bash', str(self.apply), 'RM2100'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        actual = self.bc.read_config(self.root / 'trunk/.config')
        self.assertEqual((actual[self.bc.RAM], actual[self.bc.OC], actual[self.bc.FREQ]), ('512', 'y', '0x362'))

    def test_apply_keeps_mtime_when_unchanged(self):
        self.write_project()
        for _ in range(2):
            subprocess.run(['bash', str(self.apply), 'RM2100'], cwd=self.root, check=True, capture_output=True)
            previous = getattr(self, 'mtime', None)
            self.mtime = (self.root / 'trunk/.config').stat().st_mtime_ns
            if previous:
                self.assertEqual(previous, self.mtime)

    def test_invalid_resources_leave_config_intact(self):
        self.write_project()
        before = (self.root / 'trunk/.config').read_bytes()
        local = self.root / 'hello/local/RM2100.override'
        local.parent.mkdir(parents=True)
        local.write_text(self.bc.RAM + '=1024\n')
        result = subprocess.run(['bash', str(self.apply), 'RM2100'], cwd=self.root, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / 'trunk/.config').read_bytes(), before)

    def test_tmpfs_limits_consider_auto_other_directory(self):
        with self.assertRaises(ValueError):
            self.bc.validate(self.root, 'RM2100', {**self.cfg, self.bc.TMP: '64'})
        self.bc.validate(self.root, 'RM2100', {**self.cfg, self.bc.RAM: '512', self.bc.TMP: '64', self.bc.ETC: '16'})

    def test_missing_dependency_is_explained(self):
        with self.assertRaisesRegex(ValueError, 'ARIA_WEB_CONTROL'):
            self.bc.validate(self.root, 'RM2100', {**self.cfg, 'CONFIG_FIRMWARE_INCLUDE_ARIA_WEB_CONTROL': 'y', 'CONFIG_FIRMWARE_INCLUDE_ARIA': 'n'})

    def test_real_kernel_configuration_roundtrip(self):
        kernel = self.configure()
        self.assertEqual(kernel['CONFIG_MT7621_OC'], 'n')
        overclock = {**self.cfg, self.bc.OC: 'y', self.bc.FREQ: '0x362', self.bc.RAM: '512'}
        kernel = self.configure(overclock)
        self.assertEqual(kernel['CONFIG_MT7621_OC'], 'y')
        self.assertEqual(kernel['CONFIG_MT7621_CPU_FREQ'], '0x362')
        kernel = self.configure()
        self.assertEqual(kernel['CONFIG_MT7621_OC'], 'n')
        self.assertNotIn('CONFIG_MT7621_CPU_FREQ', kernel)

    def test_board_macro_uses_selected_memory(self):
        self.configure()
        makefile = 'include trunk/.config\nROOTDIR:=$(CURDIR)/trunk\ninclude trunk/user/boards.mk\nall:\n\t@echo $(CFLAGS)\n'
        for amount in (128, 256, 512):
            self.write_project({**self.cfg, self.bc.RAM: str(amount)})
            result = subprocess.run(['make', '-s', '-f', '-'], input=makefile, cwd=self.root, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('-DBOARD_RAM_SIZE=' + str(amount), result.stdout)

    def test_transition_detects_old_build_before_config_changes(self):
        self.configure({**self.cfg, self.bc.OC: 'y', self.bc.FREQ: '0x362', self.bc.RAM: '512'})
        (self.root / 'trunk/linux-4.4.x/vmlinux').write_text('测试用编译产物标记')
        before = (self.root / 'trunk/.config').read_bytes()
        with self.assertRaisesRegex(ValueError, 'make clean'):
            self.bc.transitions(self.root, 'RM2100')
        self.assertEqual(before, (self.root / 'trunk/.config').read_bytes())

    def test_same_hardware_does_not_require_clean(self):
        selected = {**self.cfg, self.bc.OC: 'y', self.bc.FREQ: '0x362', self.bc.RAM: '512'}
        self.configure(selected)
        self.bc.save_config(self.root, 'RM2100', selected)
        (self.root / 'trunk/linux-4.4.x/vmlinux').write_text('测试用编译产物标记')
        self.bc.transitions(self.root, 'RM2100')

    def test_plugin_change_requires_clean(self):
        self.configure()
        (self.root / 'trunk/linux-4.4.x/vmlinux').write_text('测试用编译产物标记')
        self.bc.save_config(self.root, 'RM2100', {**self.cfg, 'CONFIG_FIRMWARE_INCLUDE_OPENVPN': 'y'})
        with self.assertRaisesRegex(ValueError, 'make clean'):
            self.bc.transitions(self.root, 'RM2100')

    def test_tmpfs_only_change_does_not_require_clean(self):
        self.configure()
        (self.root / 'trunk/linux-4.4.x/vmlinux').write_text('测试用编译产物标记')
        self.bc.save_config(self.root, 'RM2100', {**self.cfg, self.bc.TMP: '16'})
        self.bc.transitions(self.root, 'RM2100')

    def test_saved_choices_survive_reset_to_default(self):
        self.bc.save_config(self.root, 'RM2100', {**self.cfg, self.bc.RAM: '512'})
        self.bc.save_config(self.root, 'RM2100', self.bc.base_config(self.root, 'RM2100'))
        self.assertEqual(self.bc.read_config(self.root / 'hello/local/RM2100.override'), {})

    def test_resources_file(self):
        cfg = {**self.cfg, self.bc.RAM: '512', self.bc.TMP: '64', self.bc.ETC: '16'}
        self.write_project(cfg)
        target = self.root / 'trunk/romfs/etc_ro/build-resources.conf'
        self.bc.write_resources(self.root, self.root / 'trunk/.config', target)
        self.assertIn('TMPFS_TMP_MIB=64\nTMPFS_ETC_MIB=16\n', target.read_text())
        self.write_project()
        self.bc.write_resources(self.root, self.root / 'trunk/.config', target)
        self.assertIn('TMPFS_TMP_MIB=0\nTMPFS_ETC_MIB=0\n', target.read_text())

    def tty_run(self, text):
        master, slave = pty.openpty()
        process = subprocess.Popen(['make', '-s', 'menuconfig', 'MODEL=RM2100'], cwd=self.root,
                                   stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        output = b''
        try:
            os.write(master, text.encode())
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], .1)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    output += chunk
                if process.poll() is not None and not ready:
                    break
            process.wait(timeout=2)
        finally:
            if process.poll() is None:
                process.kill()
            os.close(master)
        self.assertEqual(process.returncode, 0, output.decode(errors='replace'))
        return output.decode(errors='replace')

    def test_actual_tty_menu_save_and_cancel(self):
        output = self.tty_run('1\n3\n2\n7\n3\n6\n5\n6\ns\nyes\n')
        cfg = self.bc.effective_config(self.root, 'RM2100')
        self.assertEqual((cfg[self.bc.FREQ], cfg[self.bc.RAM], cfg[self.bc.TMP], cfg[self.bc.ETC]), ('0x362', '512', '64', '16'))
        self.assertIn('不是 Flash', output)
        self.assertIn('确认保存', output)
        path = self.root / 'hello/local/RM2100.override'
        before = path.read_bytes()
        self.tty_run('1\n1\nq\n')
        self.assertEqual(before, path.read_bytes())

    def test_noninteractive_menu_fails_without_saving(self):
        result = subprocess.run(['make', '-s', 'menuconfig', 'MODEL=RM2100'], input='', cwd=self.root, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('交互终端', result.stderr)
        self.assertFalse((self.root / 'hello/local').exists())

    def test_make_product_remains_noninteractive(self):
        (self.root / 'toolchain').mkdir()
        (self.root / 'toolchain/Makefile').write_text('download:\n\t@true\n')
        (self.root / 'trunk/Makefile').write_text('all:\n\t@echo TEST_BUILD_ENTRY\n')
        result = subprocess.run(['make', '-s', 'RM2100'], input='', cwd=self.root, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('TEST_BUILD_ENTRY', result.stdout)
        cfg = self.bc.read_config(self.root / 'trunk/.config')
        self.assertEqual(cfg[self.bc.OC], 'n')
        self.assertEqual(cfg['CONFIG_BUILD_MODEL'], 'RM2100')


if __name__ == '__main__':
    unittest.main(verbosity=2)
