"""
Unit tests for Hyprland event routing, schema-based payload parsing,
canonical event selection, refresh coalescing, rapid activelayout changes,
and reconnect/config reloads.
"""

import unittest


class MockHyprDevice:
    def __init__(self, name="at-translated-set1-keyboard"):
        self.name = name
        self.active_keymap = ""
        self.active_layout_index = -1

    def update_active_layout(self, layout_name, layout_index):
        changed = False
        if layout_index >= 0 and self.active_layout_index != layout_index:
            self.active_layout_index = layout_index
            changed = True
        if layout_name and self.active_keymap != layout_name:
            self.active_keymap = layout_name
            changed = True
        return changed


class HyprEventRouter:
    """Simulates the C++/QML Hyprland event routing, payload schema parsing,
    canonical event selection, and refresh coalescing logic.
    """

    def __init__(self):
        self.v2_events = set()

        self.devices_refresh_count = 0
        self.options_refresh_count = 0
        self.workspace_refresh_count = 0
        self.window_refresh_count = 0

        self.devices = [MockHyprDevice("at-translated-set1-keyboard")]
        self.is_refreshing_devices = False
        self.devices_refresh_pending = False

    def reset_capabilities(self):
        self.v2_events.clear()

    @property
    def has_v2_layout(self):
        return "activelayout" in self.v2_events

    @property
    def has_v2_config(self):
        return "configreloaded" in self.v2_events

    @property
    def has_v2_workspace(self):
        return "workspace" in self.v2_events

    @property
    def has_v2_window(self):
        return "activewindow" in self.v2_events

    def trigger_devices_refresh(self):
        if self.is_refreshing_devices:
            self.devices_refresh_pending = True
            return
        self.is_refreshing_devices = True
        self.devices_refresh_count += 1
        # Finish refresh
        self.is_refreshing_devices = False
        if self.devices_refresh_pending:
            self.devices_refresh_pending = False
            self.trigger_devices_refresh()

    def parse_event(self, raw_line: str):
        if ">>" in raw_line:
            name, data = raw_line.split(">>", 1)
        else:
            name, data = raw_line, ""

        return self.handle_event(name.strip(), data.strip())

    def handle_event(self, name: str, data: str):
        is_v2 = name.endswith("v2")
        base_name = name[:-2] if is_v2 else name

        if is_v2:
            self.v2_events.add(base_name)
        elif base_name in self.v2_events:
            return "legacy_ignored"

        if base_name == "activelayout":
            parts = [p.strip() for p in data.split(",")]
            kb_name = parts[0] if len(parts) >= 1 else ""
            layout_name = parts[1] if len(parts) >= 2 else ""
            layout_idx = int(parts[2]) if is_v2 and len(parts) >= 3 and parts[2].isdigit() else -1

            for dev in self.devices:
                if not kb_name or dev.name == kb_name:
                    dev.update_active_layout(layout_name, layout_idx)

            self.trigger_devices_refresh()
            return f"{name}_processed"

        elif base_name == "configreloaded":
            self.options_refresh_count += 1
            return f"{name}_processed"

        elif base_name == "workspace":
            self.workspace_refresh_count += 1
            return f"{name}_processed"

        elif base_name == "activewindow":
            self.window_refresh_count += 1
            return f"{name}_processed"

        elif base_name in ("changefloatingmode", "minimize", "pin", "fullscreen"):
            self.window_refresh_count += 1
            return f"{name}_processed"

        return "unknown"


class TestHyprEventRouting(unittest.TestCase):
    def test_legacy_only(self):
        router = HyprEventRouter()

        # Legacy activelayout
        res = router.parse_event("activelayout>>at-translated-set1-keyboard,English (US)")
        self.assertEqual(res, "activelayout_processed")
        self.assertEqual(router.devices[0].active_keymap, "English (US)")
        self.assertEqual(router.devices_refresh_count, 1)

        # Legacy workspace
        res = router.parse_event("workspace>>2")
        self.assertEqual(res, "workspace_processed")
        self.assertEqual(router.workspace_refresh_count, 1)

        # Legacy configreloaded
        res = router.parse_event("configreloaded>>")
        self.assertEqual(res, "configreloaded_processed")
        self.assertEqual(router.options_refresh_count, 1)

    def test_v2_only(self):
        router = HyprEventRouter()

        # V2 activelayout
        res = router.parse_event("activelayoutv2>>at-translated-set1-keyboard,Czech,1")
        self.assertEqual(res, "activelayoutv2_processed")
        self.assertTrue(router.has_v2_layout)
        self.assertEqual(router.devices[0].active_keymap, "Czech")
        self.assertEqual(router.devices[0].active_layout_index, 1)
        self.assertEqual(router.devices_refresh_count, 1)

        # V2 workspace
        res = router.parse_event("workspacev2>>2,code")
        self.assertEqual(res, "workspacev2_processed")
        self.assertTrue(router.has_v2_workspace)
        self.assertEqual(router.workspace_refresh_count, 1)

        # V2 configreloaded
        res = router.parse_event("configreloadedv2>>")
        self.assertEqual(res, "configreloadedv2_processed")
        self.assertTrue(router.has_v2_config)
        self.assertEqual(router.options_refresh_count, 1)

    def test_both_emitted_legacy_then_v2(self):
        router = HyprEventRouter()

        # Both emitted: legacy arrives, then v2 arrives for same action
        res1 = router.parse_event("activelayout>>at-translated-set1-keyboard,English (US)")
        self.assertEqual(res1, "activelayout_processed")

        res2 = router.parse_event("activelayoutv2>>at-translated-set1-keyboard,English (US),0")
        self.assertEqual(res2, "activelayoutv2_processed")
        self.assertTrue(router.has_v2_layout)

        # Subsequent legacy duplicate is ignored
        res3 = router.parse_event("activelayout>>at-translated-set1-keyboard,English (US)")
        self.assertEqual(res3, "legacy_ignored")

        # Verify no double refresh work on duplicate
        self.assertEqual(router.devices_refresh_count, 2)

    def test_both_emitted_v2_then_legacy(self):
        router = HyprEventRouter()

        # Both emitted: v2 arrives first, then legacy
        res1 = router.parse_event("activelayoutv2>>at-translated-set1-keyboard,German,2")
        self.assertEqual(res1, "activelayoutv2_processed")
        self.assertTrue(router.has_v2_layout)
        self.assertEqual(router.devices[0].active_layout_index, 2)

        # Legacy duplicate arriving second is immediately ignored
        res2 = router.parse_event("activelayout>>at-translated-set1-keyboard,German")
        self.assertEqual(res2, "legacy_ignored")

        self.assertEqual(router.devices_refresh_count, 1)

    def test_mixed_stream_some_v2_some_legacy(self):
        router = HyprEventRouter()

        # Process activewindowv2
        res1 = router.parse_event("activewindowv2>>0x1234")
        self.assertEqual(res1, "activewindowv2_processed")
        self.assertIn("activewindow", router.v2_events)
        self.assertEqual(router.window_refresh_count, 1)

        # Legacy duplicate activewindow is ignored
        res2 = router.parse_event("activewindow>>class,title")
        self.assertEqual(res2, "legacy_ignored")
        self.assertEqual(router.window_refresh_count, 1)

        # Legacy-only window state events (changefloatingmode, minimize, pin) are NOT suppressed!
        res3 = router.parse_event("changefloatingmode>>0x1234,1")
        self.assertEqual(res3, "changefloatingmode_processed")
        self.assertEqual(router.window_refresh_count, 2)

        res4 = router.parse_event("minimize>>0x1234,1")
        self.assertEqual(res4, "minimize_processed")
        self.assertEqual(router.window_refresh_count, 3)

        # Legacy workspace event is NOT suppressed by activewindowv2
        res5 = router.parse_event("workspace>>3")
        self.assertEqual(res5, "workspace_processed")
        self.assertEqual(router.workspace_refresh_count, 1)

    def test_rapid_activelayout_changes(self):
        router = HyprEventRouter()

        layouts = [
            ("English (US)", 0),
            ("Czech", 1),
            ("German", 2),
            ("French", 3),
        ]

        for i in range(20):
            name, idx = layouts[i % len(layouts)]
            router.is_refreshing_devices = True  # Simulate refresh in progress
            res = router.parse_event(f"activelayoutv2>>at-translated-set1-keyboard,{name},{idx}")
            self.assertEqual(res, "activelayoutv2_processed")

        # Finish in-progress refresh
        router.is_refreshing_devices = False
        if router.devices_refresh_pending:
            router.devices_refresh_pending = False
            router.trigger_devices_refresh()

        # Verify final state matches the last layout emitted
        last_name, last_idx = layouts[19 % len(layouts)]
        self.assertEqual(router.devices[0].active_keymap, last_name)
        self.assertEqual(router.devices[0].active_layout_index, last_idx)

        # Coalescing prevented launching 20 separate socket requests
        self.assertLessEqual(router.devices_refresh_count, 2)

    def test_reconnect_and_config_reload(self):
        router = HyprEventRouter()

        # Process v2 event
        router.parse_event("activelayoutv2>>at-translated-set1-keyboard,English (US),0")
        self.assertTrue(router.has_v2_layout)

        # Simulate socket disconnect & reconnect
        router.reset_capabilities()
        self.assertFalse(router.has_v2_layout)
        self.assertFalse(router.has_v2_config)

        # Config reload event
        res = router.parse_event("configreloadedv2>>")
        self.assertEqual(res, "configreloadedv2_processed")
        self.assertTrue(router.has_v2_config)
        self.assertEqual(router.options_refresh_count, 1)


if __name__ == "__main__":
    unittest.main()
