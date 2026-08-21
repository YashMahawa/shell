import json
import math
import os
import re
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
        self.fail_dispatch = False
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

    def compute_app_identity(self, toplevel):
        if not toplevel:
            return ""
        ipc = toplevel.lastIpcObject or {}
        cls = ipc.get("initialClass") or ipc.get("class") or ""
        title = ipc.get("initialTitle") or ipc.get("title") or getattr(toplevel, "title", "")
        if cls:
            return cls
        if title:
            return title
        return self.format_address(toplevel.address or ipc.get("address"))

    def compute_instance_discriminator(self, toplevel):
        if not toplevel:
            return ""
        ipc = toplevel.lastIpcObject or {}
        pid = str(ipc.get("pid", "")) if ipc.get("pid") else ""
        title = ipc.get("initialTitle") or ipc.get("title") or getattr(toplevel, "title", "")
        addr = self.format_address(toplevel.address or ipc.get("address"))

        parts = []
        if pid:
            parts.append(f"pid:{pid}")
        if title:
            parts.append(f"title:{title}")
        if addr:
            parts.append(f"addr:{addr}")
        return ";".join(parts)

    def compute_stable_id(self, toplevel):
        if not toplevel:
            return ""
        app_id = self.compute_app_identity(toplevel)
        inst = self.compute_instance_discriminator(toplevel)
        return f"{app_id}#{inst}"

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

        # 2. Exact stableId match
        for t in self.toplevels:
            stable_id = self.compute_stable_id(t).lower()
            if stable_id == norm or stable_id.replace("0x", "") == norm:
                return t

        # 3. Class match
        for t in self.toplevels:
            ipc = t.lastIpcObject or {}
            cls = str(ipc.get("class", "")).lower()
            initial_cls = str(ipc.get("initialClass", "")).lower()
            if cls == norm or initial_cls == norm:
                return t

        # 4. Title match
        for t in self.toplevels:
            ipc = t.lastIpcObject or {}
            title = str(ipc.get("title") or getattr(t, "title", "")).lower()
            initial_title = str(ipc.get("initialTitle", "")).lower()
            if title == norm or initial_title == norm:
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
        if self.fail_dispatch:
            return False
        cmd = lua_cmd if (self.using_lua and lua_cmd) else standard_cmd
        self.dispatched_cmds.append(cmd)
        return True

    def register_overlay(self, window_id, anchor_pos=None, pin_state=None, clickthrough_state=None):
        toplevel = self.find_toplevel(window_id)
        if not toplevel:
            return json.dumps({"success": False, "error": f"Invalid window identifier: {window_id}"})

        raw_addr = toplevel.address or toplevel.lastIpcObject.get("address")
        if not raw_addr:
            return json.dumps({"success": False, "error": "Window missing address"})

        full_addr = self.format_address(raw_addr)
        norm_addr = full_addr.lower()
        ipc = toplevel.lastIpcObject or {}

        app_id = self.compute_app_identity(toplevel)
        inst_disc = self.compute_instance_discriminator(toplevel)
        stable_id = self.compute_stable_id(toplevel)

        info = self.registered_overlays.get(norm_addr)
        old_key = None

        if not info:
            for k, v in self.registered_overlays.items():
                if not v:
                    continue
                match_stable = (v.get("stableId") == stable_id)
                match_identity = (v.get("appIdentity") and v.get("instanceDiscriminator") and
                                  v.get("appIdentity") == app_id and v.get("instanceDiscriminator") == inst_disc)
                match_old_class_title = (v.get("class") == (ipc.get("class") or ipc.get("initialClass")) and
                                         v.get("title") == (ipc.get("title") or ipc.get("initialTitle")))
                if match_stable or match_identity or match_old_class_title:
                    info = v
                    old_key = k
                    break

        if not info:
            info = {
                "stableId": stable_id,
                "appIdentity": app_id,
                "instanceDiscriminator": inst_disc,
                "address": full_addr,
                "class": ipc.get("class") or ipc.get("initialClass") or "",
                "title": ipc.get("title") or ipc.get("initialTitle") or "",
                "initialClass": ipc.get("initialClass") or "",
                "initialTitle": ipc.get("initialTitle") or "",
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
        else:
            info["stableId"] = stable_id
            info["appIdentity"] = app_id
            info["instanceDiscriminator"] = inst_disc
            info["address"] = full_addr

        dispatch_success = True

        if not ipc.get("floating", False):
            ok = self.dispatch_cmd(f"setfloating address:{full_addr}", None)
            if not ok:
                dispatch_success = False

        current_overlay = dict(info)

        if anchor_pos and anchor_pos not in ("", "none"):
            ok = self.apply_anchor(toplevel, anchor_pos)
            if ok:
                current_overlay["anchored"] = anchor_pos
            else:
                dispatch_success = False

        if str(pin_state).lower() in ("true", "1", "enable"):
            if not ipc.get("pinned"):
                ok = self.dispatch_cmd(f"pin address:{full_addr}", None)
                if not ok:
                    dispatch_success = False
            if dispatch_success:
                current_overlay["pinned"] = True

        if str(clickthrough_state).lower() in ("true", "1", "enable"):
            ok1 = self.dispatch_cmd(f"setprop address:{full_addr} noinput 1", None)
            ok2 = self.dispatch_cmd(f"setprop address:{full_addr} passthrough 1", None)
            if not ok1 or not ok2:
                dispatch_success = False
            if dispatch_success:
                current_overlay["clickthrough"] = True

        if not dispatch_success:
            return json.dumps({"success": False, "error": f"Compositor dispatch failed during overlay registration for window {window_id}"})

        new_map = dict(self.registered_overlays)
        if old_key and old_key != norm_addr:
            del new_map[old_key]
        new_map[norm_addr] = current_overlay
        self.registered_overlays = new_map
        self.save_state()

        return json.dumps({"success": True, "action": "registered", "overlay": current_overlay})

    def unregister_overlay(self, window_id):
        toplevel = self.find_toplevel(window_id)
        if not toplevel:
            return json.dumps({"success": False, "error": f"Invalid window identifier: {window_id}"})

        raw_addr = toplevel.address or toplevel.lastIpcObject.get("address")
        if not raw_addr:
            return json.dumps({"success": False, "error": "Window missing address"})

        full_addr = self.format_address(raw_addr)
        norm_addr = full_addr.lower()

        info = self.registered_overlays.get(norm_addr)
        ipc = toplevel.lastIpcObject or {}

        if not info:
            # NO-OP for unmanaged windows
            return json.dumps({
                "success": False,
                "error": f"Window is not registered as an overlay: {window_id}",
                "address": full_addr
            })

        dispatch_success = True

        if info.get("clickthrough"):
            ok1 = self.dispatch_cmd(f"setprop address:{full_addr} noinput 0", None)
            ok2 = self.dispatch_cmd(f"setprop address:{full_addr} passthrough 0", None)
            if not ok1 or not ok2:
                dispatch_success = False

        if not info.get("originalPinned") and ipc.get("pinned"):
            ok = self.dispatch_cmd(f"pin address:{full_addr}", None)
            if not ok:
                dispatch_success = False

        current_ws = ipc.get("workspace", {}).get("name", "")
        if info.get("originalWorkspace") and current_ws and info["originalWorkspace"] != current_ws:
            ok = self.dispatch_cmd(f"movetoworkspacesilent {info['originalWorkspace']},address:{full_addr}", None)
            if not ok:
                dispatch_success = False

        if not info.get("originalFloating"):
            ok = self.dispatch_cmd(f"settiled address:{full_addr}", None)
            if not ok:
                dispatch_success = False
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

        ok = self.dispatch_cmd(f"movewindowpixel exact {target_x} {target_y},address:{full_addr}", None)
        if not ok:
            return False

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

            # 2. Match active window by exact stable identity (appIdentity + instanceDiscriminator)
            if not matched_toplevel:
                entry_app_id = entry.get("appIdentity") or entry.get("class") or entry.get("initialClass") or ""
                entry_inst = entry.get("instanceDiscriminator") or (f"pid:{entry['pid']}" if entry.get("pid") else "")

                if entry_app_id:
                    for t in self.toplevels:
                        cand_app_id = self.compute_app_identity(t)
                        cand_inst = self.compute_instance_discriminator(t)
                        if cand_app_id == entry_app_id and cand_inst == entry_inst:
                            matched_toplevel = t
                            break

            # 3. Match by appIdentity + PID
            if not matched_toplevel and entry.get("pid"):
                entry_app_id = entry.get("appIdentity") or entry.get("class") or entry.get("initialClass") or ""
                for t in self.toplevels:
                    ipc = t.lastIpcObject or {}
                    cand_app_id = self.compute_app_identity(t)
                    cand_pid = ipc.get("pid", 0)
                    if cand_app_id == entry_app_id and cand_pid == entry["pid"]:
                        matched_toplevel = t
                        break

            # 4. Fallback match by appIdentity + title ONLY IF UNAMBIGUOUS and PID does not contradict
            if not matched_toplevel:
                entry_app_id = entry.get("appIdentity") or entry.get("class") or entry.get("initialClass") or ""
                entry_title = entry.get("title") or entry.get("initialTitle") or ""

                if entry_app_id:
                    candidates = []
                    for t in self.toplevels:
                        cand_app_id = self.compute_app_identity(t)
                        ipc = t.lastIpcObject or {}
                        cand_title = ipc.get("title") or ipc.get("initialTitle") or getattr(t, "title", "")
                        cand_pid = ipc.get("pid", 0)

                        if entry.get("pid") and cand_pid and entry["pid"] != cand_pid:
                            continue

                        if cand_app_id == entry_app_id and (not entry_title or cand_title == entry_title):
                            candidates.append(t)

                    if len(candidates) == 1:
                        matched_toplevel = candidates[0]

            if matched_toplevel:
                raw_addr = matched_toplevel.address or matched_toplevel.lastIpcObject.get("address")
                full_addr = self.format_address(raw_addr)
                norm_addr = full_addr.lower()
                ipc = matched_toplevel.lastIpcObject or {}

                updated_entry = dict(entry)
                updated_entry["address"] = full_addr
                updated_entry["appIdentity"] = self.compute_app_identity(matched_toplevel)
                updated_entry["instanceDiscriminator"] = self.compute_instance_discriminator(matched_toplevel)
                updated_entry["stableId"] = self.compute_stable_id(matched_toplevel)

                is_already_registered = norm_addr in self.registered_overlays
                if not is_already_registered:
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

def test_unmanaged_window_unregister_and_restore_is_strict_noop(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    # Unmanaged floating window that is NOT in overlay registry
    unmanaged_floating = MockHyprlandToplevel("0xunmanaged1", "com.example.app", "Unmanaged App", floating=True, pinned=False)
    # Unmanaged tiled window that is NOT in overlay registry
    unmanaged_tiled = MockHyprlandToplevel("0xunmanaged2", "com.example.app2", "Unmanaged Tiled App", floating=False, pinned=False)
    sim.toplevels = [unmanaged_floating, unmanaged_tiled]

    sim.dispatched_cmds.clear()

    # 1. Unregistering unmanaged floating window must be a strict no-op
    res1 = json.loads(sim.unregister_overlay("0xunmanaged1"))
    assert res1["success"] is False
    assert "not registered" in res1["error"]
    assert len(sim.dispatched_cmds) == 0  # CRITICAL: 0 commands dispatched, window not mutated into tiled!

    # 2. Unregistering unmanaged tiled window must be a strict no-op
    res2 = json.loads(sim.unregister_overlay("0xunmanaged2"))
    assert res2["success"] is False
    assert "not registered" in res2["error"]
    assert len(sim.dispatched_cmds) == 0

    # Ensure window state properties remain completely unchanged
    assert unmanaged_floating.lastIpcObject["floating"] is True
    assert unmanaged_tiled.lastIpcObject["floating"] is False

def test_atomic_key_migration_when_reregistering_under_new_address(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    win_old = MockHyprlandToplevel("0xaddr1", "com.github.pet", "Desktop Pet", pid=1001, floating=False)
    sim.toplevels = [win_old]

    # Register initial overlay under address 0xaddr1
    sim.register_overlay("0xaddr1", "bottom-right", "true", "true")
    assert "0xaddr1" in sim.registered_overlays
    assert len(sim.registered_overlays) == 1

    # Simulate app restarting with a new window address 0xaddr2 (same PID, class, title)
    win_new = MockHyprlandToplevel("0xaddr2", "com.github.pet", "Desktop Pet", pid=1001, floating=False)
    sim.toplevels = [win_new]

    # Re-register under 0xaddr2
    res = json.loads(sim.register_overlay("0xaddr2", "bottom-right", "true", "true"))
    assert res["success"] is True

    # Validate ATOMIC KEY MIGRATION:
    # 0xaddr1 MUST be deleted, 0xaddr2 MUST be added, len(registered_overlays) MUST remain 1
    assert "0xaddr2" in sim.registered_overlays
    assert "0xaddr1" not in sim.registered_overlays
    assert len(sim.registered_overlays) == 1

    # Check saved state file on disk
    with open(state_file, "r") as f:
        data = json.load(f)
    assert "0xaddr2" in data["overlays"]
    assert "0xaddr1" not in data["overlays"]

def test_explicit_application_identity_and_instance_discriminator(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    win = MockHyprlandToplevel("0x123456", "org.kde.konsole", "Terminal Window", pid=4000)
    sim.toplevels = [win]

    app_id = sim.compute_app_identity(win)
    inst_disc = sim.compute_instance_discriminator(win)
    stable_id = sim.compute_stable_id(win)

    assert app_id == "org.kde.konsole"
    assert "pid:4000" in inst_disc
    assert "title:Terminal Window" in inst_disc
    assert f"{app_id}#" in stable_id

    res = json.loads(sim.register_overlay("0x123456"))
    assert res["success"] is True

    entry = sim.registered_overlays["0x123456"]
    assert entry["appIdentity"] == "org.kde.konsole"
    assert "pid:4000" in entry["instanceDiscriminator"]
    assert entry["stableId"] == stable_id

def test_ambiguity_prevention_in_multi_window_class_title_matching(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    # Two active terminal windows with IDENTICAL class and title
    term1 = MockHyprlandToplevel("0xterm1", "Alacritty", "Terminal", pid=1001)
    term2 = MockHyprlandToplevel("0xterm2", "Alacritty", "Terminal", pid=1002)
    sim.toplevels = [term1, term2]

    # Register term1 as a click-through overlay
    sim.register_overlay("0xterm1", clickthrough_state="true")
    assert sim.registered_overlays["0xterm1"]["clickthrough"] is True

    # Now simulate term1 being closed (only term2 is active)
    sim.toplevels = [term2]

    # Reconcile overlays: because PID/instanceDiscriminator does not match term2,
    # and multiple candidate windows existed originally, click-through state must NOT
    # be ambiguously attached to term2!
    sim.reconcile_overlays()

    assert "0xterm2" not in sim.registered_overlays
    assert "0xterm1" not in sim.registered_overlays
    assert len(sim.registered_overlays) == 0

def test_dispatch_success_validation_before_persisting_state(tmp_path):
    state_file = str(tmp_path / "overlay-manager-state.json")
    sim = OverlayManagerSim(state_file)

    win = MockHyprlandToplevel("0xfailwin", "com.example.fail", "Fail App")
    sim.toplevels = [win]

    # Force compositor dispatch failure
    sim.fail_dispatch = True

    res = json.loads(sim.register_overlay("0xfailwin", pin_state="true", clickthrough_state="true"))
    assert res["success"] is False
    assert "dispatch failed" in res["error"]

    # Desired state MUST NOT be saved to registered_overlays or state file on dispatch failure
    assert "0xfailwin" not in sim.registered_overlays

def test_qml_ipc_contract_and_structure_validation():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    qml_file_path = os.path.join(base_dir, "services", "OverlayManager.qml")
    assert os.path.exists(qml_file_path), "OverlayManager.qml file must exist"

    with open(qml_file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Verify Singleton declaration
    assert "pragma Singleton" in content
    assert "Singleton {" in content

    # 2. Verify IpcHandler definition and target "overlay"
    assert 'IpcHandler {' in content
    assert 'target: "overlay"' in content

    # 3. Verify all required IPC methods are present in the QML file
    required_ipc_methods = [
        "function register(",
        "function float(",
        "function unregister(",
        "function unoverlay(",
        "function anchor(",
        "function pin(",
        "function clickthrough(",
        "function list(",
        "function toggle(",
        "function restore(",
        "function restoreAll("
    ]

    for method in required_ipc_methods:
        assert method in content, f"OverlayManager.qml missing IPC method {method}"

    # 4. Verify no-op check logic is present in unregisterOverlay
    assert "if (!info)" in content
    assert "Window is not registered as an overlay" in content

    # 5. Verify explicit appIdentity and instanceDiscriminator helper functions
    assert "function computeAppIdentity(" in content
    assert "function computeInstanceDiscriminator(" in content

    # 6. Verify event filtering to avoid conflicts with pet/window rules after moves/sleep/workspace switches
    assert 'n === "movewindow"' not in content
    assert 'n === "configreloaded"' not in content

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
    assert "com.github.pet" in entry["stableId"]
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
                "stableId": "com.github.pet#pid:5000;title:Desktop Pet;addr:0xoldaddress",
                "appIdentity": "com.github.pet",
                "instanceDiscriminator": "pid:5000;title:Desktop Pet;addr:0xoldaddress",
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

    win1 = MockHyprlandToplevel("0xwin1", "app1", "App 1", pid=101)
    win2 = MockHyprlandToplevel("0xwin2", "app2", "App 2", pid=102)
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
