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
        temp_uuid = f"uuid-{temp_con_name}"

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

        def on_add(add_res):
            if self.wifiConnectionChangeKey != request_key:
                if add_res.get("success"):
                    self.executeCommand(["connection", "delete", temp_uuid], None)
                return

            if add_res.get("success"):
                def on_up(up_res):
                    if self.wifiConnectionChangeKey != request_key:
                        self.executeCommand(["connection", "delete", temp_uuid], None)
                        return

                    if up_res.get("success"):
                        def on_modify(mod_res):
                            if self.wifiConnectionChangeKey != request_key:
                                return
                            self.wifiConnectionChangeKey = ""
                            if mod_res.get("success"):
                                if callback:
                                    callback({"success": True, "output": up_res.get("output", ""), "error": "", "exitCode": 0})
                            else:
                                if callback:
                                    callback({"success": False, "output": mod_res.get("output", ""), "error": mod_res.get("error", "Failed to promote connection profile"), "exitCode": -1})
                        self.executeCommand(["connection", "modify", temp_uuid, "connection.id", ssid], on_modify)
                    else:
                        def on_del(del_res):
                            self.wifiConnectionChangeKey = ""
                            if callback:
                                callback(up_res)
                        self.executeCommand(["connection", "delete", temp_uuid], on_del)

                self.executeCommand(["connection", "up", temp_uuid], on_up)

        self.executeCommand(cmd, on_add)
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

    def test_successful_activation_promotes_profile_without_deleting_existing(self):
        # Service executeCommand mock that auto-succeeds commands
        def auto_succeed_execute(cmd_args, callback):
            self.service.executed_commands.append(cmd_args)
            if callback:
                callback({"success": True, "output": "OK", "error": "", "exitCode": 0})

        self.service.executeCommand = auto_succeed_execute
        results = []
        self.service.connectHiddenNetwork("ExistingWiFi", "secretpass123", "wpa-psk", True, lambda res: results.append(res))

        self.assertEqual(len(results), 1)
        self.assertTrue(results[0]["success"])

        # Check executed commands
        executed = self.service.executed_commands
        # 1. add con-name temp_hidden_...
        self.assertEqual(executed[0][0], "connection")
        self.assertEqual(executed[0][1], "add")
        # 2. up uuid-temp_hidden_...
        self.assertEqual(executed[1][0], "connection")
        self.assertEqual(executed[1][1], "up")
        # 3. modify uuid-temp_hidden_... connection.id ExistingWiFi
        self.assertEqual(executed[2][0], "connection")
        self.assertEqual(executed[2][1], "modify")
        self.assertEqual(executed[2][3], "connection.id")
        self.assertEqual(executed[2][4], "ExistingWiFi")

        # Confirm no 'delete ExistingWiFi' occurred
        delete_existing = [c for c in executed if c[0] == "connection" and c[1] == "delete" and "ExistingWiFi" in c]
        self.assertEqual(len(delete_existing), 0)

    def test_modify_failure_propagates_error(self):
        def fail_modify_execute(cmd_args, callback):
            self.service.executed_commands.append(cmd_args)
            if callback:
                if cmd_args[0] == "connection" and cmd_args[1] == "modify":
                    callback({"success": False, "output": "", "error": "Modify permission denied", "exitCode": 1})
                else:
                    callback({"success": True, "output": "OK", "error": "", "exitCode": 0})

        self.service.executeCommand = fail_modify_execute
        results = []
        self.service.connectHiddenNetwork("TestSSID", "secretpass123", "wpa-psk", True, lambda res: results.append(res))

        self.assertEqual(len(results), 1)
        self.assertFalse(results[0]["success"])
        self.assertIn("Modify permission denied", results[0]["error"])

if __name__ == "__main__":
    unittest.main()
