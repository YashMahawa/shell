"""
Unit tests for Hyprland event routing, schema-based payload parsing,
canonical event selection, refresh coalescing, rapid activelayout changes,
and reconnect/config reloads.
"""

import pytest


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
        self.has_v2_layout = False
        self.has_v2_config = False
        self.has_v2_workspace = False
        self.has_v2_window = False

        self.devices_refresh_count = 0
        self.options_refresh_count = 0
        self.workspace_refresh_count = 0
        self.window_refresh_count = 0

        self.devices = [MockHyprDevice("at-translated-set1-keyboard")]
        self.is_refreshing_devices = False
        self.devices_refresh_pending = False

    def reset_capabilities(self):
        self.has_v2_layout = False
        self.has_v2_config = False
        self.has_v2_workspace = False
        self.has_v2_window = False

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
        if name == "activelayoutv2":
            self.has_v2_layout = True
            parts = [p.strip() for p in data.split(",")]
            # V2 Schema: keyboard_name, layout_name, layout_index
            kb_name = parts[0] if len(parts) >= 1 else ""
            layout_name = parts[1] if len(parts) >= 2 else ""
            layout_idx = int(parts[2]) if len(parts) >= 3 and parts[2].isdigit() else -1

            for dev in self.devices:
                if not kb_name or dev.name == kb_name:
                    dev.update_active_layout(layout_name, layout_idx)

            self.trigger_devices_refresh()
            return "activelayoutv2_processed"

        elif name == "activelayout":
            if self.has_v2_layout:
                return "legacy_ignored"
            parts = [p.strip() for p in data.split(",")]
            # Legacy Schema: keyboard_name, layout_name
            kb_name = parts[0] if len(parts) >= 1 else ""
            layout_name = parts[1] if len(parts) >= 2 else ""

            for dev in self.devices:
                if not kb_name or dev.name == kb_name:
                    dev.update_active_layout(layout_name, -1)

            self.trigger_devices_refresh()
            return "activelayout_processed"

        elif name == "configreloadedv2":
            self.has_v2_config = True
            self.options_refresh_count += 1
            return "configreloadedv2_processed"

        elif name == "configreloaded":
            if self.has_v2_config:
                return "legacy_ignored"
            self.options_refresh_count += 1
            return "configreloaded_processed"

        elif name == "workspacev2":
            self.has_v2_workspace = True
            self.workspace_refresh_count += 1
            return "workspacev2_processed"

        elif name == "workspace":
            if self.has_v2_workspace:
                return "legacy_ignored"
            self.workspace_refresh_count += 1
            return "workspace_processed"

        elif name == "activewindowv2":
            self.has_v2_window = True
            self.window_refresh_count += 1
            return "activewindowv2_processed"

        elif name == "activewindow":
            if self.has_v2_window:
                return "legacy_ignored"
            self.window_refresh_count += 1
            return "activewindow_processed"

        return "unknown"


def test_legacy_only():
    router = HyprEventRouter()

    # Legacy activelayout
    res = router.parse_event("activelayout>>at-translated-set1-keyboard,English (US)")
    assert res == "activelayout_processed"
    assert router.devices[0].active_keymap == "English (US)"
    assert router.devices_refresh_count == 1

    # Legacy workspace
    res = router.parse_event("workspace>>2")
    assert res == "workspace_processed"
    assert router.workspace_refresh_count == 1

    # Legacy configreloaded
    res = router.parse_event("configreloaded>>")
    assert res == "configreloaded_processed"
    assert router.options_refresh_count == 1


def test_v2_only():
    router = HyprEventRouter()

    # V2 activelayout
    res = router.parse_event("activelayoutv2>>at-translated-set1-keyboard,Czech,1")
    assert res == "activelayoutv2_processed"
    assert router.has_v2_layout is True
    assert router.devices[0].active_keymap == "Czech"
    assert router.devices[0].active_layout_index == 1
    assert router.devices_refresh_count == 1

    # V2 workspace
    res = router.parse_event("workspacev2>>2,code")
    assert res == "workspacev2_processed"
    assert router.has_v2_workspace is True
    assert router.workspace_refresh_count == 1

    # V2 configreloaded
    res = router.parse_event("configreloadedv2>>")
    assert res == "configreloadedv2_processed"
    assert router.has_v2_config is True
    assert router.options_refresh_count == 1


def test_both_emitted_legacy_then_v2():
    router = HyprEventRouter()

    # Both emitted: legacy arrives, then v2 arrives for same action
    res1 = router.parse_event("activelayout>>at-translated-set1-keyboard,English (US)")
    assert res1 == "activelayout_processed"

    res2 = router.parse_event("activelayoutv2>>at-translated-set1-keyboard,English (US),0")
    assert res2 == "activelayoutv2_processed"
    assert router.has_v2_layout is True

    # Subsequent legacy duplicate is ignored
    res3 = router.parse_event("activelayout>>at-translated-set1-keyboard,English (US)")
    assert res3 == "legacy_ignored"

    # Verify no double refresh work on duplicate
    assert router.devices_refresh_count == 2


def test_both_emitted_v2_then_legacy():
    router = HyprEventRouter()

    # Both emitted: v2 arrives first, then legacy
    res1 = router.parse_event("activelayoutv2>>at-translated-set1-keyboard,German,2")
    assert res1 == "activelayoutv2_processed"
    assert router.has_v2_layout is True
    assert router.devices[0].active_layout_index == 2

    # Legacy duplicate arriving second is immediately ignored
    res2 = router.parse_event("activelayout>>at-translated-set1-keyboard,German")
    assert res2 == "legacy_ignored"

    assert router.devices_refresh_count == 1


def test_rapid_activelayout_changes():
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
        assert res == "activelayoutv2_processed"

    # Finish in-progress refresh
    router.is_refreshing_devices = False
    if router.devices_refresh_pending:
        router.devices_refresh_pending = False
        router.trigger_devices_refresh()

    # Verify final state matches the last layout emitted
    last_name, last_idx = layouts[19 % len(layouts)]
    assert router.devices[0].active_keymap == last_name
    assert router.devices[0].active_layout_index == last_idx

    # Coalescing prevented launching 20 separate socket requests
    assert router.devices_refresh_count <= 2


def test_reconnect_and_config_reload():
    router = HyprEventRouter()

    # Process v2 event
    router.parse_event("activelayoutv2>>at-translated-set1-keyboard,English (US),0")
    assert router.has_v2_layout is True

    # Simulate socket disconnect & reconnect
    router.reset_capabilities()
    assert router.has_v2_layout is False
    assert router.has_v2_config is False

    # Config reload event
    res = router.parse_event("configreloadedv2>>")
    assert res == "configreloadedv2_processed"
    assert router.has_v2_config is True
    assert router.options_refresh_count == 1
