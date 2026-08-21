import sys
import os
import json
import pytest

# Add modules/nexus/scripts to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "modules", "nexus", "scripts")))

import manage_systemd

def test_critical_services_denylist():
    critical_samples = [
        "NetworkManager.service",
        "network.service",
        "wpa_supplicant.service",
        "bluetooth.service",
        "display-manager.service",
        "gdm.service",
        "greetd.service",
        "systemd-suspend.service",
        "dbus.service",
        "systemd-logind.service",
        "pipewire.service",
        "caelestia.service"
    ]
    for unit in critical_samples:
        is_crit, reason = manage_systemd.evaluate_critical_status(unit)
        assert is_crit is True, f"Unit '{unit}' should be flagged as critical"
        assert len(reason) > 0, f"Unit '{unit}' should have a critical reason description"

def test_template_units():
    template_instantiations = [
        ("getty@tty1.service", True),
        ("wpa_supplicant@wlan0.service", True),
        ("netctl@wifi_home.service", True),
        ("user@1000.service", True),
        ("customapp@user1.service", False)
    ]
    for unit, expected_critical in template_instantiations:
        is_crit, reason = manage_systemd.evaluate_critical_status(unit)
        assert is_crit == expected_critical, f"Template unit '{unit}' critical status mismatch"

def test_aliases_and_candidate_names():
    candidates = manage_systemd.get_candidate_names("getty@tty1.service")
    assert "getty@tty1.service" in candidates
    assert "getty@.service" in candidates
    assert "getty.service" in candidates

    # Test alias set evaluation
    aliases = {"display-manager.service", "my-custom-dm.service"}
    is_crit, reason = manage_systemd.evaluate_critical_status("my-custom-dm.service", aliases=aliases)
    assert is_crit is True
    assert "Display manager" in reason

def test_system_allowlist():
    allowlisted = ["cups.service", "sshd.service", "syncthing.service", "docker.service"]
    for unit in allowlisted:
        assert manage_systemd.is_allowlisted(unit) is True

    non_allowlisted = ["custom_daemon.service", "random_script.service"]
    for unit in non_allowlisted:
        assert manage_systemd.is_allowlisted(unit) is False

def test_impact_preview_critical_chain():
    impact = manage_systemd.get_impact_preview("dbus.service", nonce=42)
    assert impact["success"] is True
    assert impact["unit"] == "dbus.service"
    assert impact["nonce"] == 42
    assert impact["isCritical"] is True
    assert impact["isCriticalChain"] is True

def test_execute_action_policy_enforcement(monkeypatch):
    # Test invalid action rejection
    res = manage_systemd.execute_action("invalid_cmd", "cups.service", scope="system")
    assert res["success"] is False
    assert "Invalid action" in res["error"]

    # Test invalid unit name rejection
    res = manage_systemd.execute_action("start", "; reboot", scope="system")
    assert res["success"] is False
    assert "Invalid unit name" in res["error"]

    # Test system scope rejection for critical service when expert=False
    res = manage_systemd.execute_action("stop", "NetworkManager.service", scope="system", expert=False)
    assert res["success"] is False
    assert "critical system service" in res["error"]

    # Test system scope rejection for non-allowlisted service when expert=False
    res = manage_systemd.execute_action("stop", "custom_daemon.service", scope="system", expert=False)
    assert res["success"] is False
    assert "not in the system allowlist" in res["error"]

    # Mock subprocess.run for policy pass cases so no actual pkexec is invoked
    called_cmd = []
    def mock_run(cmd, **kwargs):
        called_cmd.append(cmd)
        class DummyRes:
            returncode = 0
            stdout = ""
            stderr = ""
        return DummyRes()

    monkeypatch.setattr(manage_systemd.subprocess, "run", mock_run)

    # Allowlisted service with expert=False should pass policy check and call pkexec
    res_allow = manage_systemd.execute_action("restart", "cups.service", scope="system", expert=False)
    assert res_allow["success"] is True
    assert called_cmd[-1] == ["pkexec", "systemctl", "restart", "cups.service"]

    # Critical service with expert=True should pass policy check and call pkexec
    res_expert = manage_systemd.execute_action("stop", "NetworkManager.service", scope="system", expert=True)
    assert res_expert["success"] is True
    assert called_cmd[-1] == ["pkexec", "systemctl", "stop", "NetworkManager.service"]

def test_stderr_error_reporting(capsys):
    # Call get_services with invalid setup or inspect response
    res = manage_systemd.get_services()
    assert "success" in res
    assert "services" in res
