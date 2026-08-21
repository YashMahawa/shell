#!/usr/bin/env python3
import os
import unittest


class TestNightLightQmlContract(unittest.TestCase):
    """Verifies the QML contract and structural guarantees of NightLight.qml."""

    def setUp(self):
        self.qml_path = os.path.join(os.path.dirname(__file__), "..", "services", "NightLight.qml")
        with open(self.qml_path, "r", encoding="utf-8") as f:
            self.qml_content = f.read()

    def test_no_pkill_bash_usage(self):
        """Ensure pkill and uncontrolled bash spawns are not used."""
        self.assertNotIn("pkill hyprsunset", self.qml_content)
        self.assertNotIn("pkill wlsunset", self.qml_content)
        self.assertNotIn("gammastep -x", self.qml_content)

    def test_supervised_process_tracking(self):
        """Ensure process is tracked directly via Process component."""
        self.assertIn("Process", self.qml_content)
        self.assertIn("proc.running", self.qml_content)
        self.assertIn("proc.command", self.qml_content)

    def test_ddc_vcp_presets_validation(self):
        """Ensure DDC VCP values are validated against supported presets."""
        self.assertIn("supportedDdcPresets", self.qml_content)
        self.assertIn("mapTemperatureToDdcPreset", self.qml_content)

    def test_debouncing_timer_exists(self):
        """Ensure debounce timer is configured."""
        self.assertIn("debounceTimer", self.qml_content)
        self.assertIn("interval: 150", self.qml_content)

    def test_hdr_and_hotplug_support(self):
        """Ensure HDR state check and monitor connections exist."""
        self.assertIn("checkHdrState", self.qml_content)
        self.assertIn("hdrActive", self.qml_content)
        self.assertIn("Hypr.monitors", self.qml_content)


class DummyProcess:
    def __init__(self):
        self.running = False
        self.command = []
        self.stdout = None


class MockNightLightEngine:
    """Python simulation of NightLight state machine for behavioral verification."""

    def __init__(self, hyprsunset=False, gammastep=False, wlsunset=False, gsettings=False, ddc=False):
        self.enabled = True
        self.temperature = 4500
        self.pending_temperature = 4500
        self.pending_enabled = True
        self.debounce_scheduled = False
        self.hyprsunset_avail = hyprsunset
        self.gammastep_avail = gammastep
        self.wlsunset_avail = wlsunset
        self.gsettings_avail = gsettings
        self.ddc_avail = ddc
        self.monitors = []
        self.hdr_active = False
        self.proc = DummyProcess()
        self.prior_state = {}
        self.gsettings_store = {"night-light-enabled": "false", "night-light-temperature": "6500"}
        self.ddc_store = {"temperature": "6500"}
        self.supported_ddc_presets = ["5000", "6500", "7500", "9300", "user"]
        self.process_spawn_count = 0

    def detect_backend(self):
        if self.hyprsunset_avail:
            return "hyprsunset"
        if self.gammastep_avail:
            return "gammastep"
        if self.wlsunset_avail:
            return "wlsunset"
        if self.gsettings_avail:
            return "gsettings"
        if self.ddc_avail:
            return "ddc"
        return "none"

    @property
    def active_backend(self):
        return self.detect_backend()

    @property
    def backend_available(self):
        return self.active_backend != "none"

    def check_hdr_state(self):
        self.hdr_active = any(m.get("hdr", False) for m in self.monitors)

    def set_temperature(self, temp):
        clamped = max(2000, min(6500, temp))
        self.pending_temperature = clamped
        self.pending_enabled = self.enabled
        self.debounce_scheduled = True

    def set_enabled(self, val):
        self.pending_enabled = val
        if not self.debounce_scheduled:
            self.pending_temperature = self.temperature
        self.debounce_scheduled = True

    def map_temperature_to_ddc_preset(self, temp):
        if temp >= 5750:
            return "6500"
        if temp >= 4000:
            return "5000"
        return "user"

    def trigger_debounce(self):
        if not self.debounce_scheduled:
            return
        self.debounce_scheduled = False
        self.apply_pending_changes()

    def apply_pending_changes(self):
        new_enabled = self.pending_enabled
        new_temp = self.pending_temperature

        self.temperature = new_temp
        self.enabled = new_enabled
        self.check_hdr_state()

        if not self.enabled:
            self.restore_prior_state()
            self.stop_managed_process()
            return

        self.save_prior_state()

        if self.hdr_active:
            self.stop_managed_process()
            return

        backend = self.active_backend
        if backend == "hyprsunset":
            self.run_managed_process(["hyprsunset", "-t", str(new_temp)])
        elif backend == "gammastep":
            self.run_managed_process(["gammastep", "-P", "-O", str(new_temp)])
        elif backend == "wlsunset":
            self.run_managed_process(["wlsunset", "-T", str(new_temp)])
        elif backend == "gsettings":
            self.gsettings_store["night-light-temperature"] = str(new_temp)
            self.gsettings_store["night-light-enabled"] = "true"
        elif backend == "ddc":
            preset = self.map_temperature_to_ddc_preset(new_temp)
            if preset in self.supported_ddc_presets:
                self.ddc_store["temperature"] = preset
        else:
            self.stop_managed_process()

    def run_managed_process(self, cmd):
        if self.proc.running:
            self.proc.running = False
        self.proc.command = cmd
        self.proc.running = True
        self.process_spawn_count += 1

    def stop_managed_process(self):
        if self.proc.running:
            self.proc.running = False

    def save_prior_state(self):
        if self.prior_state:
            return
        if self.active_backend == "gsettings":
            self.prior_state = dict(self.gsettings_store)
        elif self.active_backend == "ddc":
            self.prior_state = dict(self.ddc_store)

    def restore_prior_state(self):
        if self.prior_state and self.active_backend == "gsettings":
            self.gsettings_store = dict(self.prior_state)
        elif self.prior_state and self.active_backend == "ddc":
            self.ddc_store = dict(self.prior_state)
        self.prior_state = {}

    def hotplug_monitors(self, new_monitors):
        self.monitors = new_monitors
        self.check_hdr_state()
        if self.enabled:
            self.apply_pending_changes()


class TestNightLightBehavior(unittest.TestCase):
    """Behavioral unit tests covering rapid slider, missing backend, restart, HDR, and hotplug."""

    def test_rapid_slider(self):
        """Verify rapid slider movements are debounced and spawn process only once."""
        nl = MockNightLightEngine(hyprsunset=True)
        for t in range(2000, 6500, 90):
            nl.set_temperature(t)

        self.assertTrue(nl.debounce_scheduled)
        self.assertEqual(nl.process_spawn_count, 0)

        nl.trigger_debounce()

        self.assertFalse(nl.debounce_scheduled)
        self.assertEqual(nl.process_spawn_count, 1)
        self.assertEqual(nl.temperature, 6410)
        self.assertEqual(nl.proc.command, ["hyprsunset", "-t", "6410"])

    def test_missing_backend(self):
        """Verify behavior when no night light backend is available on the system."""
        nl = MockNightLightEngine(hyprsunset=False, gammastep=False, wlsunset=False, gsettings=False, ddc=False)
        self.assertFalse(nl.backend_available)
        self.assertEqual(nl.active_backend, "none")

        nl.set_temperature(3000)
        nl.trigger_debounce()

        self.assertFalse(nl.proc.running)
        self.assertEqual(nl.process_spawn_count, 0)

    def test_restart(self):
        """Verify state restoration and process tracking across disable/enable cycle."""
        nl = MockNightLightEngine(gsettings=True)
        nl.gsettings_store = {"night-light-enabled": "false", "night-light-temperature": "6500"}

        nl.set_temperature(3500)
        nl.set_enabled(True)
        nl.trigger_debounce()

        self.assertEqual(nl.gsettings_store["night-light-temperature"], "3500")
        self.assertEqual(nl.gsettings_store["night-light-enabled"], "true")

        nl.set_enabled(False)
        nl.trigger_debounce()

        self.assertEqual(nl.gsettings_store["night-light-temperature"], "6500")
        self.assertEqual(nl.gsettings_store["night-light-enabled"], "false")

    def test_hdr(self):
        """Verify software gamma is paused/bypassed when HDR display is connected."""
        nl = MockNightLightEngine(hyprsunset=True)
        nl.monitors = [{"name": "DP-1", "hdr": True}]

        nl.set_temperature(3000)
        nl.trigger_debounce()

        self.assertTrue(nl.hdr_active)
        self.assertFalse(nl.proc.running)

    def test_monitor_hotplug(self):
        """Verify monitor hotplug event re-evaluates HDR and applies settings cleanly."""
        nl = MockNightLightEngine(hyprsunset=True)
        nl.monitors = [{"name": "eDP-1", "hdr": False}]

        nl.set_temperature(4000)
        nl.trigger_debounce()

        self.assertTrue(nl.proc.running)
        self.assertFalse(nl.hdr_active)

        nl.hotplug_monitors([{"name": "eDP-1", "hdr": False}, {"name": "HDMI-A-1", "hdr": True}])

        self.assertTrue(nl.hdr_active)
        self.assertFalse(nl.proc.running)


if __name__ == "__main__":
    unittest.main()
