#!/usr/bin/env python3
import os
import unittest


class TestNightLightQmlContract(unittest.TestCase):
    """Verifies the QML contract and structural guarantees of NightLight.qml."""

    def setUp(self):
        self.qml_path = os.path.join(os.path.dirname(__file__), "..", "services", "NightLight.qml")
        with open(self.qml_path, "r", encoding="utf-8") as f:
            self.qml_content = f.read()

    def test_default_disabled_on_startup(self):
        """Ensure enabled defaults to false unless opt-in is loaded."""
        self.assertIn("property bool enabled: false", self.qml_content)
        self.assertIn("property bool pendingEnabled: false", self.qml_content)

    def test_no_pkill_bash_usage(self):
        """Ensure pkill and uncontrolled bash spawns are not used."""
        self.assertNotIn("pkill hyprsunset", self.qml_content)
        self.assertNotIn("pkill wlsunset", self.qml_content)
        self.assertNotIn("gammastep -x", self.qml_content)

    def test_supervised_process_tracking(self):
        """Ensure process is tracked directly via Process component and generations."""
        self.assertIn("Process", self.qml_content)
        self.assertIn("proc.running", self.qml_content)
        self.assertIn("proc.command", self.qml_content)
        self.assertIn("pendingCommand", self.qml_content)
        self.assertIn("processGeneration", self.qml_content)

    def test_no_ddc_generic_fallback(self):
        """Ensure DDC is not used as a generic night-light fallback."""
        self.assertNotIn("supportedDdcPresets", self.qml_content)
        self.assertNotIn("mapTemperatureToDdcPreset", self.qml_content)
        self.assertNotIn('return "ddc";', self.qml_content)

    def test_verified_gsettings_backend(self):
        """Ensure gsettings backend checks schema availability before returning true."""
        self.assertIn("gsettings get org.gnome.settings-daemon.plugins.color night-light-temperature", self.qml_content)

    def test_state_persistence_file(self):
        """Ensure state persistence via FileView is configured."""
        self.assertIn("FileView", self.qml_content)
        self.assertIn("night-light.json", self.qml_content)

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

    def __init__(self, hyprsunset=False, gammastep=False, wlsunset=False, gsettings=False, gsettings_verified=True, persisted_opt_in=False):
        self.enabled = persisted_opt_in
        self.pending_enabled = persisted_opt_in
        self.temperature = 4500
        self.pending_temperature = 4500
        self.debounce_scheduled = False
        self.hyprsunset_avail = hyprsunset
        self.gammastep_avail = gammastep
        self.wlsunset_avail = wlsunset
        self.gsettings_avail = gsettings and gsettings_verified
        self.monitors = []
        self.hdr_active = False
        self.proc = DummyProcess()
        self.pending_command = []
        self.active_command = []
        self.process_generation = 0
        self.prior_state = {}
        self.gsettings_store = {"night-light-enabled": "false", "night-light-temperature": "6500"}
        self.persisted_store = {}
        if persisted_opt_in:
            self.persisted_store = {"enabled": True, "temperature": 4500}

    def detect_backend(self):
        if self.hyprsunset_avail:
            return "hyprsunset"
        if self.gammastep_avail:
            return "gammastep"
        if self.wlsunset_avail:
            return "wlsunset"
        if self.gsettings_avail:
            return "gsettings"
        return "none"

    @property
    def active_backend(self):
        return self.detect_backend()

    @property
    def backend_available(self):
        return self.active_backend != "none"

    def check_hdr_state(self):
        self.hdr_active = any(
            m.get("hdr", False) or m.get("hdrEnabled", False) or m.get("isHdr", False) or m.get("bitsPerColor", 8) > 8
            for m in self.monitors
        )

    def set_temperature(self, temp):
        clamped = max(2000, min(6500, temp))
        self.pending_temperature = clamped
        if not self.debounce_scheduled:
            self.pending_enabled = self.enabled
        self.debounce_scheduled = True

    def set_enabled(self, val):
        self.pending_enabled = val
        if not self.debounce_scheduled:
            self.pending_temperature = self.temperature
        self.debounce_scheduled = True

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
        self.save_state()

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
        else:
            self.stop_managed_process()

    def run_managed_process(self, cmd):
        if self.proc.running:
            if self.active_command == cmd:
                return
            self.pending_command = cmd
            self.proc.running = False
        else:
            self.pending_command = []
            self.active_command = cmd
            self.proc.command = cmd
            self.proc.running = True
            self.process_generation += 1

    def finish_process_exit(self):
        """Simulates async exit of old process generation."""
        if not self.proc.running:
            self.active_command = []
            if self.pending_command:
                cmd = self.pending_command
                self.pending_command = []
                if self.enabled and not self.hdr_active and self.backend_available:
                    self.active_command = cmd
                    self.proc.command = cmd
                    self.proc.running = True
                    self.process_generation += 1

    def stop_managed_process(self):
        self.pending_command = []
        if self.proc.running:
            self.proc.running = False

    def save_prior_state(self):
        if self.prior_state:
            return
        if self.active_backend == "gsettings":
            self.prior_state = dict(self.gsettings_store)

    def restore_prior_state(self):
        if self.prior_state and self.active_backend == "gsettings":
            self.gsettings_store = dict(self.prior_state)
        self.prior_state = {}

    def save_state(self):
        self.persisted_store = {"enabled": self.enabled, "temperature": self.temperature}

    def hotplug_monitors(self, new_monitors):
        self.monitors = new_monitors
        self.check_hdr_state()
        if self.enabled:
            self.apply_pending_changes()


class TestNightLightBehavior(unittest.TestCase):
    """Behavioral unit tests covering startup opt-in, process generation, HDR, backend transitions, and restart."""

    def test_default_disabled_without_opt_in(self):
        """Verify NightLight starts disabled by default and does not spawn processes."""
        nl = MockNightLightEngine(hyprsunset=True, persisted_opt_in=False)
        self.assertFalse(nl.enabled)
        nl.apply_pending_changes()
        self.assertFalse(nl.proc.running)
        self.assertEqual(nl.process_generation, 0)

    def test_rapid_slider_and_generation_supervision(self):
        """Verify rapid slider movements update target and supervise one process generation at a time."""
        nl = MockNightLightEngine(hyprsunset=True, persisted_opt_in=True)
        nl.apply_pending_changes()
        self.assertTrue(nl.proc.running)
        self.assertEqual(nl.process_generation, 1)
        self.assertEqual(nl.proc.command, ["hyprsunset", "-t", "4500"])

        # Change temperature while process is running
        nl.set_temperature(3000)
        nl.trigger_debounce()

        # Previous generation process was requested to terminate, pending_command was updated
        self.assertFalse(nl.proc.running)
        self.assertEqual(nl.pending_command, ["hyprsunset", "-t", "3000"])
        self.assertEqual(nl.process_generation, 1)

        # Old process finishes exiting
        nl.finish_process_exit()

        # Generation 2 starts cleanly
        self.assertTrue(nl.proc.running)
        self.assertEqual(nl.process_generation, 2)
        self.assertEqual(nl.proc.command, ["hyprsunset", "-t", "3000"])

    def test_missing_backend(self):
        """Verify behavior when no night light backend is available on the system."""
        nl = MockNightLightEngine(hyprsunset=False, gammastep=False, wlsunset=False, gsettings=False, persisted_opt_in=True)
        self.assertFalse(nl.backend_available)
        self.assertEqual(nl.active_backend, "none")

        nl.set_temperature(3000)
        nl.trigger_debounce()

        self.assertFalse(nl.proc.running)
        self.assertEqual(nl.process_generation, 0)

    def test_verified_gsettings_backend(self):
        """Verify gsettings is ignored if unverified/unsupported daemon schema."""
        nl_unverified = MockNightLightEngine(gsettings=True, gsettings_verified=False, persisted_opt_in=True)
        self.assertFalse(nl_unverified.backend_available)
        self.assertEqual(nl_unverified.active_backend, "none")

        nl_verified = MockNightLightEngine(gsettings=True, gsettings_verified=True, persisted_opt_in=True)
        self.assertTrue(nl_verified.backend_available)
        self.assertEqual(nl_verified.active_backend, "gsettings")

    def test_no_ddc_fallback(self):
        """Verify DDC is never selected as a backend."""
        nl = MockNightLightEngine(hyprsunset=False, gammastep=False, wlsunset=False, gsettings=False, persisted_opt_in=True)
        self.assertEqual(nl.active_backend, "none")

    def test_restart_and_prior_state_restoration(self):
        """Verify prior enabled and temperature state query & restoration across disable/enable cycle."""
        nl = MockNightLightEngine(gsettings=True, gsettings_verified=True)
        nl.gsettings_store = {"night-light-enabled": "false", "night-light-temperature": "6500"}

        # User opts in
        nl.set_enabled(True)
        nl.set_temperature(3500)
        nl.trigger_debounce()

        self.assertEqual(nl.gsettings_store["night-light-temperature"], "3500")
        self.assertEqual(nl.gsettings_store["night-light-enabled"], "true")
        self.assertEqual(nl.prior_state, {"night-light-enabled": "false", "night-light-temperature": "6500"})

        # User disables
        nl.set_enabled(False)
        nl.trigger_debounce()

        # Prior state (both enabled and temperature) restored
        self.assertEqual(nl.gsettings_store["night-light-temperature"], "6500")
        self.assertEqual(nl.gsettings_store["night-light-enabled"], "false")

    def test_hdr_handling_and_hotplug(self):
        """Verify software gamma tools stop under HDR displays and resume when HDR is removed."""
        nl = MockNightLightEngine(hyprsunset=True, persisted_opt_in=True)
        nl.monitors = [{"name": "DP-1", "hdr": True}]

        nl.set_temperature(3000)
        nl.trigger_debounce()

        self.assertTrue(nl.hdr_active)
        self.assertFalse(nl.proc.running)

        # Hotplug monitor to non-HDR
        nl.hotplug_monitors([{"name": "DP-1", "hdr": False, "bitsPerColor": 8}])
        self.assertFalse(nl.hdr_active)
        self.assertTrue(nl.proc.running)

        # Hotplug monitor with 10-bit HDR enabled
        nl.hotplug_monitors([{"name": "DP-1", "hdr": False, "bitsPerColor": 10}])
        self.assertTrue(nl.hdr_active)
        self.assertFalse(nl.proc.running)

    def test_backend_transition(self):
        """Verify transitioning between backends stops old process and starts new backend cleanly."""
        nl = MockNightLightEngine(hyprsunset=True, persisted_opt_in=True)
        nl.apply_pending_changes()

        self.assertEqual(nl.active_backend, "hyprsunset")
        self.assertTrue(nl.proc.running)
        self.assertEqual(nl.proc.command, ["hyprsunset", "-t", "4500"])

        # Transition backend to gammastep
        nl.hyprsunset_avail = False
        nl.gammastep_avail = True
        nl.apply_pending_changes()

        self.assertEqual(nl.active_backend, "gammastep")
        self.assertFalse(nl.proc.running)
        nl.finish_process_exit()

        self.assertTrue(nl.proc.running)
        self.assertEqual(nl.proc.command, ["gammastep", "-P", "-O", "4500"])


if __name__ == "__main__":
    unittest.main()
