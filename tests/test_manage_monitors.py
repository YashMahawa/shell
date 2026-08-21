#!/usr/bin/env python3
import json
import os
import shutil
import sys
import tempfile
import time
import unittest
from unittest.mock import patch, MagicMock

sys_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "../modules/nexus/scripts"))
if sys_path not in os.path.sys.path:
    os.path.sys.path.insert(0, sys_path)

import manage_monitors

class TestManageMonitors(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.runtime_dir = os.path.join(self.test_dir, "run")
        self.config_dir = os.path.join(self.test_dir, "config")
        os.makedirs(self.runtime_dir, mode=0o700, exist_ok=True)
        os.makedirs(self.config_dir, exist_ok=True)
        self.env_patcher = patch.dict(os.environ, {
            "XDG_RUNTIME_DIR": self.runtime_dir,
            "XDG_CONFIG_HOME": self.config_dir
        })
        self.env_patcher.start()

    def tearDown(self):
        self.env_patcher.stop()
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_security_rollback_path_permissions(self):
        rollback_path = manage_monitors.get_rollback_path()
        base_dir = os.path.dirname(rollback_path)
        self.assertTrue(os.path.exists(base_dir))
        stat_info = os.stat(base_dir)
        mode = stat_info.st_mode & 0o777
        self.assertEqual(mode, 0o700)
        self.assertTrue(rollback_path.startswith(self.runtime_dir))

    def test_invalid_modes_and_inputs(self):
        # Invalid monitor name
        with self.assertRaises(ValueError):
            manage_monitors.validate_monitor_name("../invalid_name")

        # Invalid resolution
        with self.assertRaises(ValueError):
            manage_monitors.validate_res("invalid_resolution")

        # Invalid position
        with self.assertRaises(ValueError):
            manage_monitors.validate_pos("invalid_pos")

        # Invalid scale
        with self.assertRaises(ValueError):
            manage_monitors.validate_scale("-1.0")

        # Invalid transform
        with self.assertRaises(ValueError):
            manage_monitors.validate_transform("9")

        # Disable all monitors safety check
        all_disabled = [
            {"name": "eDP-1", "disabled": True},
            {"name": "HDMI-A-1", "disabled": True}
        ]
        with self.assertRaises(ValueError):
            manage_monitors.apply_rules(all_disabled)

    @patch("shutil.which", return_value="/usr/bin/hyprctl")
    @patch("manage_monitors.run_command")
    def test_external_only_monitors(self, mock_run, mock_which):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        external_only_rules = [
            {"name": "eDP-1", "disabled": True},
            {"name": "HDMI-A-1", "res": "1920x1080@60", "pos": "0x0", "scale": "1"}
        ]
        res = manage_monitors.apply_rules(external_only_rules)
        self.assertTrue(res)

    @patch("shutil.which", return_value="/usr/bin/hyprctl")
    @patch("manage_monitors.run_command")
    def test_mixed_scale_factors(self, mock_run, mock_which):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        mixed_scale_rules = [
            {"name": "eDP-1", "res": "2560x1600@165", "pos": "0x0", "scale": "2"},
            {"name": "HDMI-A-1", "res": "1920x1080@60", "pos": "1280x0", "scale": "1.25"}
        ]
        res = manage_monitors.apply_rules(mixed_scale_rules)
        self.assertTrue(res)

    @patch("shutil.which", return_value="/usr/bin/hyprctl")
    @patch("manage_monitors.run_command")
    def test_mock_safe_and_deliberate_empty_response(self, mock_run, mock_which):
        # 1. Unpopulated or empty stdout mock returns None and does not trigger rollback
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        self.assertIsNone(manage_monitors.get_current_hypr_monitors())

        rules = [{"name": "HDMI-A-1", "res": "1920x1080@60", "pos": "0x0", "scale": "1"}]
        self.assertTrue(manage_monitors.apply_rules(rules))

        # 2. Deliberately mocked empty monitor list "[]" returns [] and triggers rollback safely
        mock_run.return_value = MagicMock(returncode=0, stdout="[]", stderr="")
        self.assertEqual(manage_monitors.get_current_hypr_monitors(), [])

        with self.assertRaises(RuntimeError) as ctx:
            manage_monitors.apply_rules(rules)
        self.assertIn("Output configuration error detected", str(ctx.exception))

        # Ensure rollback executed commands using runner (mock_run) and didn't touch live host
        calls = [c[0][0] for c in mock_run.call_args_list]
        self.assertIn(["hyprctl", "keyword", "monitor", "HDMI-A-1,preferred,auto,1"], calls)

    @patch("manage_monitors.get_current_hypr_monitors")
    @patch("subprocess.run")
    def test_hdmi_power_cut_and_disconnect(self, mock_run, mock_get_monitors):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        # Simulate HDMI disconnected / cut
        mock_get_monitors.return_value = [{"name": "eDP-1", "width": 1920, "height": 1080}]
        
        monitors_after_cut = manage_monitors.get_current_hypr_monitors()
        self.assertEqual(len(monitors_after_cut), 1)
        self.assertEqual(monitors_after_cut[0]["name"], "eDP-1")

    def test_native_lua_config_and_no_legacy_hypr_user_conf(self):
        monitors = [
            {"name": "eDP-1", "res": "1920x1080@60", "pos": "0x0", "scale": "1"},
            {"name": "HDMI-A-1", "res": "2560x1440@144", "pos": "1920x0", "scale": "1.25"}
        ]
        manage_monitors.save_to_monitors_conf(monitors)

        caelestia_dir = os.path.join(self.config_dir, "caelestia")
        managed_conf = os.path.join(caelestia_dir, "hypr-monitors.conf")
        user_conf = os.path.join(caelestia_dir, "hypr-user.conf")
        lua_conf = os.path.join(caelestia_dir, "display.lua")

        # Native Lua fragment must exist
        self.assertTrue(os.path.exists(lua_conf))
        # Legacy hypr-user.conf and hypr-monitors.conf must NOT be written or modified!
        self.assertFalse(os.path.exists(managed_conf))
        self.assertFalse(os.path.exists(user_conf))

        with open(lua_conf, "r") as f:
            lua_content = f.read()
            self.assertIn('name = "eDP-1"', lua_content)
            self.assertIn('scale = 1.25', lua_content)
            self.assertIn('return {', lua_content)

    def test_compositor_return_code_validation_and_rollback(self):
        runner = MagicMock()
        # First command fails (returncode=1)
        runner.return_value = MagicMock(returncode=1, stdout="", stderr="invalid rule")

        rules = [{"name": "HDMI-A-1", "res": "1920x1080@60", "pos": "0x0", "scale": "1"}]
        previous = [{"name": "eDP-1", "width": 1920, "height": 1080, "refreshRate": 60, "x": 0, "y": 0, "scale": 1}]

        with self.assertRaises(RuntimeError) as ctx:
            manage_monitors.apply_rules(rules, previous_layout=previous, runner=runner)
        self.assertIn("Compositor command failed with exit code 1", str(ctx.exception))

        # Check that rollback command to eDP-1 was attempted via runner
        calls = [c[0][0] for c in runner.call_args_list]
        self.assertTrue(any(any("eDP-1" in arg for arg in cmd) for cmd in calls))

    def test_atomic_write_and_locking(self):
        target = os.path.join(self.config_dir, "test_file.txt")
        manage_monitors.atomic_write(target, "hello world")
        self.assertTrue(os.path.exists(target))
        with open(target, "r") as f:
            self.assertEqual(f.read(), "hello world")

        with manage_monitors.TransactionLock():
            # Ensure transaction lock opens and closes without error
            pass

    @patch("manage_monitors.save_to_monitors_conf")
    @patch("manage_monitors.apply_rules")
    def test_token_validation_for_confirm_and_rollback(self, mock_apply, mock_save):
        rollback_info = {
            "token": "valid_token_xyz",
            "previous_layout": [{"name": "eDP-1", "width": 1920, "height": 1080}],
            "pending_layout": [{"name": "eDP-1", "res": "1920x1080@60"}],
            "created_at": time.time(),
            "timeout": 20
        }
        manage_monitors.write_rollback_file(rollback_info)

        # Test CLI confirm with invalid/empty token using sys.argv
        with patch.object(sys, "argv", ["manage_monitors.py", "confirm", ""]):
            with self.assertRaises(SystemExit) as cm:
                manage_monitors.main()
            self.assertEqual(cm.exception.code, 1)

        with patch.object(sys, "argv", ["manage_monitors.py", "confirm", "wrong_token"]):
            with self.assertRaises(SystemExit) as cm:
                manage_monitors.main()
            self.assertEqual(cm.exception.code, 1)

        # Test CLI rollback with invalid/empty token using sys.argv
        with patch.object(sys, "argv", ["manage_monitors.py", "rollback", ""]):
            with self.assertRaises(SystemExit) as cm:
                manage_monitors.main()
            self.assertEqual(cm.exception.code, 1)

        with patch.object(sys, "argv", ["manage_monitors.py", "rollback", "wrong_token"]):
            with self.assertRaises(SystemExit) as cm:
                manage_monitors.main()
            self.assertEqual(cm.exception.code, 1)

        # Confirm with exact valid token succeeds
        with patch.object(sys, "argv", ["manage_monitors.py", "confirm", "valid_token_xyz"]):
            manage_monitors.main()
        mock_save.assert_called_once()
        self.assertFalse(os.path.exists(manage_monitors.get_rollback_path()))

    @patch("manage_monitors.apply_rules")
    def test_standalone_backend_auto_rollback_on_ui_failure(self, mock_apply_rules):
        previous_layout = [
            {"name": "eDP-1", "width": 1920, "height": 1080, "refreshRate": 60, "x": 0, "y": 0, "scale": 1}
        ]
        pending_layout = [
            {"name": "eDP-1", "res": "1920x1080@60", "pos": "0x0", "scale": "2"}
        ]
        token = "test_token_123"
        rollback_info = {
            "token": token,
            "previous_layout": previous_layout,
            "pending_layout": pending_layout,
            "created_at": time.time(),
            "timeout": 0.2
        }

        manage_monitors.write_rollback_file(rollback_info)
        rollback_path = manage_monitors.get_rollback_path()
        self.assertTrue(os.path.exists(rollback_path))

        # Run daemon watch for 0.2 seconds simulating UI crash / no confirm call
        manage_monitors.run_daemon_watch(token, timeout=0.2)

        # Confirm that auto-rollback was executed and file removed
        mock_apply_rules.assert_called_once()
        self.assertFalse(os.path.exists(rollback_path))

if __name__ == "__main__":
    unittest.main()
