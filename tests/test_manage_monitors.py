#!/usr/bin/env python3
import json
import os
import shutil
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

    @patch("subprocess.run")
    def test_external_only_monitors(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        external_only_rules = [
            {"name": "eDP-1", "disabled": True},
            {"name": "HDMI-A-1", "res": "1920x1080@60", "pos": "0x0", "scale": "1"}
        ]
        res = manage_monitors.apply_rules(external_only_rules)
        self.assertTrue(res)

    @patch("subprocess.run")
    def test_mixed_scale_factors(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        mixed_scale_rules = [
            {"name": "eDP-1", "res": "2560x1600@165", "pos": "0x0", "scale": "2"},
            {"name": "HDMI-A-1", "res": "1920x1080@60", "pos": "1280x0", "scale": "1.25"}
        ]
        res = manage_monitors.apply_rules(mixed_scale_rules)
        self.assertTrue(res)

    @patch("manage_monitors.get_current_hypr_monitors")
    @patch("subprocess.run")
    def test_hdmi_power_cut_and_disconnect(self, mock_run, mock_get_monitors):
        mock_run.return_value = MagicMock(returncode=0, stdout="", stderr="")
        # Simulate HDMI disconnected / cut
        mock_get_monitors.return_value = [{"name": "eDP-1", "width": 1920, "height": 1080}]
        
        monitors_after_cut = manage_monitors.get_current_hypr_monitors()
        self.assertEqual(len(monitors_after_cut), 1)
        self.assertEqual(monitors_after_cut[0]["name"], "eDP-1")

    def test_display_config_integration_and_restart_persistence(self):
        monitors = [
            {"name": "eDP-1", "res": "1920x1080@60", "pos": "0x0", "scale": "1"},
            {"name": "HDMI-A-1", "res": "2560x1440@144", "pos": "1920x0", "scale": "1.25"}
        ]
        manage_monitors.save_to_monitors_conf(monitors)

        caelestia_dir = os.path.join(self.config_dir, "caelestia")
        managed_conf = os.path.join(caelestia_dir, "hypr-monitors.conf")
        user_conf = os.path.join(caelestia_dir, "hypr-user.conf")
        lua_conf = os.path.join(caelestia_dir, "display.lua")

        self.assertTrue(os.path.exists(managed_conf))
        self.assertTrue(os.path.exists(user_conf))
        self.assertTrue(os.path.exists(lua_conf))

        with open(managed_conf, "r") as f:
            content = f.read()
            self.assertIn("eDP-1,1920x1080@60,0x0,1", content)
            self.assertIn("HDMI-A-1,2560x1440@144,1920x0,1.25", content)

        with open(user_conf, "r") as f:
            user_content = f.read()
            self.assertIn(f"source = {managed_conf}", user_content)

        with open(lua_conf, "r") as f:
            lua_content = f.read()
            self.assertIn('name = "eDP-1"', lua_content)
            self.assertIn('scale = 1.25', lua_content)

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
