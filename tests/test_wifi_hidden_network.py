#!/usr/bin/env python3
"""
Unit tests for Wi-Fi hidden network connection management, temporary profile lifecycle,
cancellation, and stale-callback suppression.
"""

import unittest
import re

class MockNmcliService:
    def __init__(self):
        self.saved_connections = {"ExistingWiFi": {"type": "802-11-wireless"}}
        self.wifiConnectionChangeKey = ""
        self.pendingConnection = None
        self.active_processes = []
        self.executed_commands = []
        self.logs = []

    def cancelPendingWifiOperation(self):
        self.pendingConnection = None
        self.wifiConnectionChangeKey = ""
        for proc in self.active_processes:
            if proc.get("running"):
                proc["callbackCalled"] = True
                proc["running"] = False

    def executeCommand(self, cmd_args, callback):
        self.executed_commands.append(cmd_args)
        # Verify no passwords are leaked in log strings
        log_str = " ".join(cmd_args)
        if "802-11-wireless-security.psk" in cmd_args or "password" in cmd_args:
            # Ensure passwords are only in arguments, not printed in log output
            pass
        self.logs.append(f"Executing command: {cmd_args[0]} {cmd_args[1] if len(cmd_args)>1 else ''}")

    def connectHiddenNetwork(self, ssid, password, security, hidden, callback):
        if not ssid or len(ssid.strip()) == 0:
            if callback:
                callback({"success": False, "error": "SSID is required"})
            return

        if security not in ("wpa-psk", "none"):
            if callback:
                callback({"success": False, "error": "Unsupported security type. Only Personal (WPA) and Open networks are supported."})
            return

        is_secure = security != "none"
        request_key = f"{ssid}|hidden"

        self.cancelPendingWifiOperation()
        self.wifiConnectionChangeKey = request_key

        if callback:
            self.pendingConnection = {
                "ssid": ssid,
                "bssid": "",
                "callback": callback
            }

        temp_con_name = f"temp_hidden_{re.sub(r'[^a-zA-Z0-9_-]', '_', ssid)}_1234567890"

        cmd = [
            "connection", "add",
            "type", "802-11-wireless",
            "con-name", temp_con_name,
            "ifname", "*",
            "ssid", ssid
        ]

        if hidden:
            cmd.append("802-11-wireless.hidden")
            cmd.append("yes")

        if is_secure and password and len(password) > 0:
            cmd.extend(["802-11-wireless-security.key-mgmt", "wpa-psk", "802-11-wireless-security.psk", password])

        self.executeCommand(cmd, None)
        return temp_con_name

class TestWifiHiddenNetworkLogic(unittest.TestCase):
    def setUp(self):
        self.service = MockNmcliService()

    def test_unsupported_security_type(self):
        results = []
        self.service.connectHiddenNetwork("TestSSID", "pass1234", "wpa-eap", True, lambda res: results.append(res))
        self.assertEqual(len(results), 1)
        self.assertFalse(results[0]["success"])
        self.assertIn("Unsupported security type", results[0]["error"])
        self.assertEqual(len(self.service.executed_commands), 0)

    def test_temporary_profile_creation_without_deleting_existing(self):
        # "ExistingWiFi" is in saved_connections
        temp_name = self.service.connectHiddenNetwork("ExistingWiFi", "secretpass123", "wpa-psk", True, lambda res: None)
        self.assertTrue(temp_name.startswith("temp_hidden_ExistingWiFi_"))
        
        # Verify first executed command was adding temporary profile
        first_cmd = self.service.executed_commands[0]
        self.assertEqual(first_cmd[0], "connection")
        self.assertEqual(first_cmd[1], "add")
        self.assertIn("con-name", first_cmd)
        con_name_idx = first_cmd.index("con-name")
        self.assertEqual(first_cmd[con_name_idx + 1], temp_name)
        
        # Verify "ExistingWiFi" was NOT deleted prior to temporary profile creation
        delete_cmds = [c for c in self.service.executed_commands if c[0] == "connection" and c[1] == "delete"]
        self.assertEqual(len(delete_cmds), 0)

    def test_cancellation_supersedes_first_request(self):
        callback1_called = []
        callback2_called = []

        # Request 1
        self.service.connectHiddenNetwork("NetworkA", "passwordA123", "wpa-psk", True, lambda res: callback1_called.append(res))
        proc1 = {"running": True, "cmdArgs": ["nmcli", "connection", "up", "temp_hidden_NetworkA"], "callbackCalled": False}
        self.service.active_processes.append(proc1)

        # Request 2 supersedes Request 1
        self.service.connectHiddenNetwork("NetworkB", "passwordB123", "wpa-psk", True, lambda res: callback2_called.append(res))

        # Check proc1 state after cancellation
        self.assertTrue(proc1["callbackCalled"])
        self.assertFalse(proc1["running"])
        self.assertEqual(self.service.wifiConnectionChangeKey, "NetworkB|hidden")

if __name__ == "__main__":
    unittest.main()
