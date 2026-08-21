import json
import math
import os
import tempfile
import pytest

class MockHyprlandToplevel:
    def __init__(self, address, cls, title, initial_cls=None, initial_title=None, pid=1000,
                 floating=False, pinned=False, workspace="1", monitor="DP-1",
                 at=(100, 100), size=(800, 600)):
        self.address = address
        self.title = title
        self.workspace_name = workspace
        self.lastIpcObject = {
            "address": address,
            "class": cls,
            "title": title,
            "initialClass": initial_cls or cls,
            "initialTitle": initial_title or title,
            "pid": pid,
            "floating": floating,
            "pinned": pinned,
            "workspace": {"name": workspace, "id": 1},
            "monitor": monitor,
            "at": list(at),
            "size": list(size)
        }

class MockHyprlandMonitor:
    def __init__(self, name, x, y, width, height, mon_id=0):
        self.name = name
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.id = mon_id
        self.lastIpcObject = {
            "name": name,
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "id": mon_id
        }

class OverlayManagerSim:
    def __init__(self, state_file_path):
        self.state_file_path = state_file_path
        self.registered_overlays = {}
        self.saved_state = {}
        self.dispatched_cmds = []
        self.toplevels = []
        self.monitors = []
        self.active_toplevel = None
        self.using_lua = False
        self.focused_monitor = None
        self.load_state()

    def load_state(self):
        if os.path.exists(self.state_file_path):
            try:
                with open(self.state_file_path, "r") as f:
                    data = json.load(f)
                    self.saved_state = data.get("overlays", {})
            except Exception:
                self.saved_state = {}

    def save_state(self):
        payload = {
            "version": 1,
            "overlays": self.registered_overlays
        }
        os.makedirs(os.path.dirname(self.state_file_path), exist_ok=True)
        with open(self.state_file_path, "w") as f:
            json.dump(payload, f, indent=2)

    def format_address(self, addr):
        if not addr:
            return ""
        return addr if addr.startswith("0x") else f"0x{addr}"

    def compute_stable_id(self, toplevel):
        if not toplevel:
            return ""
        ipc = toplevel.lastIpcObject or {}
        cls = ipc.get("class") or ipc.get("initialClass") or ""
        title = ipc.get("initialTitle") or ipc.get("title") or getattr(toplevel, "title", "")
        pid = str(ipc.get("pid", "")) if ipc.get("pid") else ""

        if cls and title:
            return f"{cls}:{title}"
        elif cls:
            return f"{cls}:{pid}" if pid else cls
        elif title:
            return title
        return self.format_address(toplevel.address or ipc.get("address"))

    def find_toplevel(self, window_id):
        if not window_id or window_id in ("", "active"):
            return self.active_toplevel

        raw = str(window_id).strip()
        norm = raw.lower().replace("0x", "")

        # 1. Exact address match
        for t in self.toplevels:
            addr = str(t.address or "").lower().replace("0x", "")
            ipc_addr = str(t.lastIpcObject.get("address", "")).lower().replace("0x", "")
            if addr == norm or ipc_addr == norm:
                return t

        # 2. Class match
        for t in self.toplevels:
            ipc = t.lastIpcObject or {}
            cls = str(ipc.get("class", "")).lower()
            initial_cls = str(ipc.get("initialClass", "")).lower()
            if cls == norm or initial_cls == norm:
                return t

        # 3. Title match
        for t in self.toplevels:
            ipc = t.lastIpcObject or {}
            title = str(ipc.get("title") or getattr(t, "title", "")).lower()
            initial_title = str(ipc.get("initialTitle", "")).lower()
            if title == norm or initial_title == norm:
                return t

        # 4. Composite stableId match
        for t in self.toplevels:
            stable_id = self.compute_stable_id(t).lower()
            if stable_id == norm or stable_id.replace("0x", "") == norm:
                return t

        return None

    def get_monitor_for_toplevel(self, toplevel):
        if not toplevel:
            return self.focused_monitor or (self.monitors[0] if self.monitors else None)

        ipc_mon = toplevel.lastIpcObject.get("monitor")
        for m in self.monitors:
            if m.name == ipc_mon or m.id == ipc_mon or str(m.id) == str(ipc_mon):
                return m
        return self.focused_monitor or (self.monitors[0] if self.monitors else None)

    def dispatch_cmd(self, standard_cmd, lua_cmd):
        cmd = lua_cmd if (self.using_lua and lua_cmd) else standard_cmd
        self.dispatched_cmds.append(cmd)

    def register_overlay(self, window_id, anchor_pos=None, pin_state=None, clickthrough_state=None):
        toplevel = self.find_toplevel(window_id)
        if not toplevel:
            return json.dumps({"success": False, "error": f"Invalid window identifier: {window_id}"})

        raw_addr = toplevel.address or toplevel.lastIpcObject.get("address")
        full_addr = self.format_address(raw_addr)
        norm_addr = full_addr.lower()
        ipc = toplevel.lastIpcObject or {}
        stable_id = self.compute_stable_id(toplevel)

        info = self.registered_overlays.get(norm_addr)
        if not info:
            for k, v in self.registered_overlays.items():
                if v.get("stableId") == stable_id:
                    info = v
                    break

        if not info:
            info = {
                "stableId": stable_id,
                "address": full_addr,
                "class": ipc.get("class", ""),
                "title": ipc.get("title", ""),
                "initialClass": ipc.get("initialClass", ""),
                "initialTitle": ipc.get("initialTitle", ""),
                "pid": ipc.get("pid", 0),
                "originalFloating": ipc.get("floating", False),
                "originalPinned": ipc.get("pinned", False),
                "originalWorkspace": ipc.get("workspace", {}).get("name", ""),
                "originalMonitor": ipc.get("monitor", ""),
                "originalAt": list(ipc.get("at", [0, 0])),
                "originalSize": list(ipc.get("size", [800, 600])),
                "anchored": None,
                "pinned": ipc.get("pinned", False),
                "clickthrough": False
            }

        info["address"] = full_addr

        if not ipc.get("floating", False):
            self.dispatch_cmd(f"setfloating address:{full_addr}", None)

        current_overlay = dict(info)

        if anchor_pos and anchor_pos not in ("", "none"):
            self.apply_anchor(toplevel, anchor_pos)
            current_overlay["anchored"] = anchor_pos

        if str(pin_state).lower() in ("true", "1", "enable"):
            if not ipc.get("pinned"):
                self.dispatch_cmd(f"pin address:{full_addr}", None)
            current_overlay["pinned"] = True

        if str(clickthrough_state).lower() in ("true", "1", "enable"):
            self.dispatch_cmd(f"setprop address:{full_addr} noinput 1", None)
            self.dispatch_cmd(f"setprop address:{full_addr} passthrough 1", None)
            current_overlay["clickthrough"] = True

        new_map = dict(self.registered_overlays)
        new_map[norm_addr] = current_overlay
        self.registered_overlays = new_map
        self.save_state()

        return json.dumps({"success": True, "action": "registered", "overlay": current_overlay})

    def unregister_overlay(self, window_id):
        toplevel = self.find_toplevel(window_id)
        if not toplevel:
            return json.dumps({"success": False, "error": f"Invalid window identifier: {window_id}"})

        raw_addr = toplevel.address or toplevel.lastIpcObject.get("address")
        full_addr = self.format_address(raw_addr)
        norm_addr = full_addr.lower()

        info = self.registered_overlays.get(norm_addr)
        ipc = toplevel.lastIpcObject or {}

        if info:
            if info.get("clickthrough"):
                self.dispatch_cmd(f"setprop address:{full_addr} noinput 0", None)
                self.dispatch_cmd(f"setprop address:{full_addr} passthrough 0", None)

            if not info.get("originalPinned") and ipc.get("pinned"):
                self.dispatch_cmd(f"pin address:{full_addr}", None)

            current_ws = ipc.get("workspace", {}).get("name", "")
            if info.get("originalWorkspace") and current_ws and info["originalWorkspace"] != current_ws:
                self.dispatch_cmd(f"movetoworkspacesilent {info['originalWorkspace']},address:{full_addr}", None)

            if not info.get("originalFloating"):
                self.dispatch_cmd(f"settiled address:{full_addr}", None)
            else:
                orig_at = info.get("originalAt", [0, 0])
                orig_size = info.get("originalSize", [800, 600])
                self.dispatch_cmd(f"movewindowpixel exact {orig_at[0]} {orig_at[1]},address:{full_addr}", None)
                self.dispatch_cmd(f"resizewindowpixel exact {orig_size[0]} {orig_size[1]},address:{full_addr}", None)

            new_map = dict(self.registered_overlays)
            del new_map[norm_addr]
            self.registered_overlays = new_map
            self.save_state()

            return json.dumps({"success": True, "action": "unregistered", "address": full_addr})
        else:
            if ipc.get("floating"):
                self.dispatch_cmd(f"settiled address:{full_addr}", None)
            return json.dumps({"success": True, "action": "unregistered", "address": full_addr, "note": "was not in registry"})

    def apply_anchor(self, toplevel, position, margin_str=None):
        if not toplevel:
            return False

        raw_addr = toplevel.address or toplevel.lastIpcObject.get("address")
        full_addr = self.format_address(raw_addr)
        monitor = self.get_monitor_for_toplevel(toplevel)

        mon_x = monitor.x if monitor else 0
        mon_y = monitor.y if monitor else 0
        mon_w = monitor.width if monitor else 1920
        mon_h = monitor.height if monitor else 1080

        ipc = toplevel.lastIpcObject or {}
        win_w = ipc.get("size", [800, 600])[0]
        win_h = ipc.get("size", [800, 600])[1]

        margin = int(margin_str) if margin_str is not None and str(margin_str).strip() != "" else 10
        pos = str(position or "center").lower()

        target_x = mon_x + round((mon_w - win_w) / 2)
        target_y = mon_y + round((mon_h - win_h) / 2)

        if pos in ("top-left", "topleft"):
            target_x = mon_x + margin
            target_y = mon_y + margin
        elif pos in ("top-right", "topright"):
            target_x = mon_x + mon_w - win_w - margin
            target_y = mon_y + margin
        elif pos in ("bottom-left", "bottomleft"):
            target_x = mon_x + margin
            target_y = mon_y + mon_h - win_h - margin
        elif pos in ("bottom-right", "bottomright"):
            target_x = mon_x + mon_w - win_w - margin
            target_y = mon_y + mon_h - win_h - margin
        elif pos == "top":
            target_x = mon_x + round((mon_w - win_w) / 2)
            target_y = mon_y + margin
        elif pos == "bottom":
            target_x = mon_x + round((mon_w - win_w) / 2)
            target_y = mon_y + mon_h - win_h - margin
        elif pos == "left":
            target_x = mon_x + margin
            target_y = mon_y + round((mon_h - win_h) / 2)
        elif pos == "right":
            target_x = mon_x + mon_w - win_w - margin
            target_y = mon_y + round((mon_h - win_h) / 2)
        elif pos in ("center", "middle"):
            target_x = mon_x + round((mon_w - win_w) / 2)
            target_y = mon_y + round((mon_h - win_h) / 2)

        self.dispatch_cmd(f"movewindowpixel exact {target_x} {target_y},address:{full_addr}", None)

        norm_addr = full_addr.lower()
        if norm_addr in self.registered_overlays:
            new_map = dict(self.registered_overlays)
            new_map[norm_addr]["anchored"] = pos
            self.registered_overlays = new_map
            self.save_state()

        return True

    def reconcile_overlays(self):
        source_map = self.registered_overlays if len(self.registered_overlays) > 0 else self.saved_state
        new_registered = {}

        for key, entry in source_map.items():
            if not entry:
                continue

            matched_toplevel = None

            # 1. Match active window by address
            if entry.get("address"):
                norm_entry_addr = self.format_address(entry["address"]).lower()
                for t in self.toplevels:
                    addr = self.format_address(t.address or t.lastIpcObject.get("address")).lower()
                    if addr == norm_entry_addr:
                        matched_toplevel = t
                        break

            # 2. Match active window by stable identity (class, title, initialTitle, pid)
            if not matched_toplevel and entry.get("class"):
                for t in self.toplevels:
                    ipc = t.lastIpcObject or {}
                    cls = ipc.get("class") or ipc.get("initialClass") or ""
                    title = ipc.get("initialTitle") or ipc.get("title") or getattr(t, "title", "")
                    pid = ipc.get("pid", 0)

                    if cls == entry["class"] and (title == entry.get("title") or title == entry.get("initialTitle") or (entry.get("pid") and pid == entry.get("pid"))):
                        matched_toplevel = t
                        break

            if matched_toplevel:
                raw_addr = matched_toplevel.address or matched_toplevel.lastIpcObject.get("address")
                full_addr = self.format_address(raw_addr)
                norm_addr = full_addr.lower()
                ipc = matched_toplevel.lastIpcObject or {}

                updated_entry = dict(entry)
                updated_entry["address"] = full_addr
                updated_entry["stableId"] = self.compute_stable_id(matched_toplevel)

                if not ipc.get("floating"):
                    self.dispatch_cmd(f"setfloating address:{full_addr}", None)

                if updated_entry.get("pinned") and not ipc.get("pinned"):
                    self.dispatch_cmd(f"pin address:{full_addr}", None)

                if updated_entry.get("clickthrough"):
                    self.dispatch_cmd(f"setprop address:{full_addr} noinput 1", None)
                    self.dispatch_cmd(f"setprop address:{full_addr} passthrough 1", None)

                if updated_entry.get("anchored"):
                    self.apply_anchor(matched_toplevel, updated_entry["anchored"])

                new_registered[norm_addr] = updated_entry

        self.registered_overlays = new_registered
        self.save_state()

# Tests

def test_state_persistence_and_serialization(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    win = MockHyprlandToplevel("0x11223344", "com.github.pet", "Desktop Pet", floating=False, pinned=False, workspace="1")
    sim.toplevels = [win]

    # Register window as overlay
    res = json.loads(sim.register_overlay("0x11223344", "bottom-right", "true", "true"))
    assert res["success"] is True
    assert os.path.exists(state_file)

    with open(state_file, "r") as f:
        data = json.load(f)
    assert "overlays" in data
    assert "0x11223344" in data["overlays"]
    entry = data["overlays"]["0x11223344"]
    assert entry["stableId"] == "com.github.pet:Desktop Pet"
    assert entry["pinned"] is True
    assert entry["clickthrough"] is True
    assert entry["anchored"] == "bottom-right"
    assert entry["originalFloating"] is False
    assert entry["originalWorkspace"] == "1"

def test_reconciliation_and_stale_address_recovery_on_restart(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    
    # 1. Pre-populate state file simulating a previous session before shell restart
    initial_data = {
        "version": 1,
        "overlays": {
            "0xoldaddress": {
                "stableId": "com.github.pet:Desktop Pet",
                "address": "0xoldaddress",
                "class": "com.github.pet",
                "title": "Desktop Pet",
                "initialClass": "com.github.pet",
                "initialTitle": "Desktop Pet",
                "pid": 5000,
                "originalFloating": False,
                "originalPinned": False,
                "originalWorkspace": "2",
                "originalMonitor": "DP-1",
                "originalAt": [100, 100],
                "originalSize": [400, 300],
                "anchored": "bottom-right",
                "pinned": True,
                "clickthrough": True
            }
        }
    }
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    with open(state_file, "w") as f:
        json.dump(initial_data, f)

    # 2. Simulate shell restart: window now has a new transient address "0xnewaddress99"
    new_win = MockHyprlandToplevel("0xnewaddress99", "com.github.pet", "Desktop Pet", pid=5000, floating=False, pinned=False, workspace="2")
    sim = OverlayManagerSim(state_file)
    sim.toplevels = [new_win]

    # Reconcile on boot
    sim.reconcile_overlays()

    # Address should be updated from stale address to new address
    assert "0xnewaddress99" in sim.registered_overlays
    assert "0xoldaddress" not in sim.registered_overlays
    entry = sim.registered_overlays["0xnewaddress99"]
    assert entry["address"] == "0xnewaddress99"
    assert entry["pinned"] is True
    assert entry["clickthrough"] is True

    # Check commands dispatched during reconciliation
    cmds = " ".join(sim.dispatched_cmds)
    assert "setfloating address:0xnewaddress99" in cmds
    assert "pin address:0xnewaddress99" in cmds
    assert "setprop address:0xnewaddress99 noinput 1" in cmds
    assert "setprop address:0xnewaddress99 passthrough 1" in cmds

def test_sleep_and_suspend_recovery(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    pet_win = MockHyprlandToplevel("0xpetaddr", "com.github.pet", "Desktop Pet", floating=False, pinned=False, workspace="1")
    sim.toplevels = [pet_win]

    sim.register_overlay("0xpetaddr", "bottom-left", "true", "true")
    assert sim.registered_overlays["0xpetaddr"]["clickthrough"] is True

    # Save before sleep
    sim.save_state()

    # Simulate wake: active window list refreshed, reconciliation triggered
    sim.dispatched_cmds.clear()
    sim.reconcile_overlays()

    assert "0xpetaddr" in sim.registered_overlays
    assert sim.registered_overlays["0xpetaddr"]["originalFloating"] is False
    assert sim.registered_overlays["0xpetaddr"]["originalWorkspace"] == "1"

def test_window_close_event_handling(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    win1 = MockHyprlandToplevel("0xwin1", "app1", "App 1")
    win2 = MockHyprlandToplevel("0xwin2", "app2", "App 2")
    sim.toplevels = [win1, win2]

    sim.register_overlay("0xwin1")
    sim.register_overlay("0xwin2")
    assert len(sim.registered_overlays) == 2

    # Simulate win1 closing (window list now only has win2)
    sim.toplevels = [win2]
    sim.reconcile_overlays()

    assert "0xwin1" not in sim.registered_overlays
    assert "0xwin2" in sim.registered_overlays

    with open(state_file, "r") as f:
        data = json.load(f)
    assert "0xwin1" not in data["overlays"]
    assert "0xwin2" in data["overlays"]

def test_multi_monitor_anchoring(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    mon1 = MockHyprlandMonitor("DP-1", 0, 0, 1920, 1080, mon_id=0)
    mon2 = MockHyprlandMonitor("HDMI-A-1", 1920, 0, 2560, 1440, mon_id=1)
    sim.monitors = [mon1, mon2]

    win_mon2 = MockHyprlandToplevel("0xmon2win", "app", "Title", monitor="HDMI-A-1", size=(600, 400))
    sim.toplevels = [win_mon2]

    # Test top-right anchor on secondary monitor (HDMI-A-1 at x=1920, y=0, w=2560, h=1440)
    # Expected X: 1920 + 2560 - 600 - 15 = 3865
    # Expected Y: 0 + 15 = 15
    sim.dispatched_cmds.clear()
    sim.register_overlay("0xmon2win", "top-right")
    sim.apply_anchor(win_mon2, "top-right", margin_str="15")

    cmds = sim.dispatched_cmds
    assert any("movewindowpixel exact 3865 15,address:0xmon2win" in c for c in cmds)

    # Test bottom-left anchor on primary monitor (DP-1 at x=0, y=0, w=1920, h=1080)
    win_mon1 = MockHyprlandToplevel("0xmon1win", "app", "Title", monitor="DP-1", size=(500, 300))
    sim.toplevels.append(win_mon1)
    sim.dispatched_cmds.clear()
    sim.apply_anchor(win_mon1, "bottom-left", margin_str="20")

    # Expected X: 0 + 20 = 20
    # Expected Y: 0 + 1080 - 300 - 20 = 760
    cmds = sim.dispatched_cmds
    assert any("movewindowpixel exact 20 760,address:0xmon1win" in c for c in cmds)

def test_window_state_preservation_and_safe_restoration(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    tiled_win = MockHyprlandToplevel(
        "0xtiled", "org.kde.konsole", "Konsole",
        floating=False, pinned=False, workspace="3",
        at=(0, 0), size=(960, 1080)
    )
    sim.toplevels = [tiled_win]

    # 1. Register tiled window as overlay
    sim.register_overlay("0xtiled", "top-right", "true", "true")
    entry = sim.registered_overlays["0xtiled"]
    assert entry["originalFloating"] is False
    assert entry["originalWorkspace"] == "3"
    assert entry["originalPinned"] is False

    # 2. Simulate moving tiled window to workspace 5 while overlayed
    tiled_win.lastIpcObject["workspace"]["name"] = "5"

    # 3. Unregister and restore
    sim.dispatched_cmds.clear()
    res = json.loads(sim.unregister_overlay("0xtiled"))
    assert res["success"] is True

    cmds = sim.dispatched_cmds
    # Safe restoration steps:
    # - Restore input
    assert "setprop address:0xtiled noinput 0" in cmds
    assert "setprop address:0xtiled passthrough 0" in cmds
    # - Restore original workspace
    assert "movetoworkspacesilent 3,address:0xtiled" in cmds
    # - Restore tiling mode
    assert "settiled address:0xtiled" in cmds

def test_stable_identity_generic_matching_without_browser_heuristics(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    apps = [
        MockHyprlandToplevel("0x1", "org.gnome.Nautilus", "Files", pid=101),
        MockHyprlandToplevel("0x2", "mpv", "video.mp4", pid=102),
        MockHyprlandToplevel("0x3", "com.obsproject.Studio", "OBS Studio", pid=103),
    ]
    sim.toplevels = apps

    # Verify find_toplevel works by class, title, address, and stable_id
    assert sim.find_toplevel("org.gnome.nautilus") == apps[0]
    assert sim.find_toplevel("video.mp4") == apps[1]
    assert sim.find_toplevel("com.obsproject.Studio:OBS Studio") == apps[2]
    assert sim.find_toplevel("0x2") == apps[1]
