#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

PROFILES_PATH = os.path.expanduser("~/.config/caelestia/display_profiles.json")

def get_caelestia_runtime_dir():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if runtime_dir and os.path.exists(runtime_dir):
        base_dir = os.path.join(runtime_dir, "caelestia")
    else:
        uid = os.getuid() if hasattr(os, "getuid") else 1000
        base_dir = os.path.join("/tmp", f"caelestia-{uid}")
    os.makedirs(base_dir, mode=0o700, exist_ok=True)
    try:
        os.chmod(base_dir, 0o700)
    except Exception:
        pass
    return base_dir

def get_rollback_path():
    return os.path.join(get_caelestia_runtime_dir(), "display_rollback.json")

class TransactionLock:
    def __init__(self):
        base_dir = get_caelestia_runtime_dir()
        self.lock_path = os.path.join(base_dir, "display_transaction.lock")
        self.file_obj = None

    def __enter__(self):
        self.file_obj = open(self.lock_path, "w")
        try:
            fcntl.flock(self.file_obj, fcntl.LOCK_EX)
        except Exception:
            pass
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.file_obj:
            try:
                fcntl.flock(self.file_obj, fcntl.LOCK_UN)
                self.file_obj.close()
            except Exception:
                pass

def atomic_write(filepath, content, mode=0o600):
    dirname = os.path.dirname(os.path.abspath(filepath))
    os.makedirs(dirname, mode=0o700, exist_ok=True)
    tmp_path = os.path.join(dirname, f".tmp_{uuid.uuid4().hex}")
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(content)
    try:
        os.chmod(tmp_path, mode)
    except Exception:
        pass
    os.replace(tmp_path, filepath)

def atomic_write_json(filepath, data, mode=0o600):
    atomic_write(filepath, json.dumps(data, indent=2), mode)

def validate_monitor_name(name):
    if not name or not re.match(r'^[a-zA-Z0-9_-]+$', name):
        raise ValueError(f"Invalid monitor name: {name}")

def validate_res(res):
    if not res or (not re.match(r'^\d+x\d+@[\d\.]+$', res) and not re.match(r'^\d+x\d+$', res) and res not in ["preferred", "disable"]):
        raise ValueError(f"Invalid resolution: {res}")

def validate_pos(pos):
    if not pos or (not re.match(r'^-?\d+x-?\d+$', pos) and pos != "auto"):
        raise ValueError(f"Invalid position: {pos}")

def validate_scale(scale):
    try:
        s = float(scale)
        if s <= 0 or s > 10:
            raise ValueError()
    except Exception:
        raise ValueError(f"Invalid scale factor: {scale}")

def validate_transform(transform):
    if transform is None or not re.match(r'^[0-7]$', str(transform)):
        raise ValueError(f"Invalid transform: {transform}")

def monitor_rule(name, res, pos, scale, transform="0", disabled=False):
    if disabled or res == "disable":
        return f"{name},disable"
    if str(transform) == "0":
        return f"{name},{res},{pos},{scale}"
    return f"{name},{res},{pos},{scale},transform,{transform}"

def run_command(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)

def get_current_hypr_monitors(runner=None):
    if runner is None:
        runner = run_command
    try:
        res = runner(["hyprctl", "monitors", "-j"], capture_output=True, text=True, check=True)
        stdout = getattr(res, "stdout", "")
        if stdout is None or not isinstance(stdout, str) or not stdout.strip():
            return None
        parsed = json.loads(stdout)
        if isinstance(parsed, list):
            return parsed
        return None
    except Exception:
        return None

def reload_hyprland(runner=None):
    if runner is None:
        runner = run_command
    try:
        runner(["hyprctl", "reload"], capture_output=True, text=True)
    except FileNotFoundError:
        pass

def _rollback_layout(previous_layout, runner=None):
    if runner is None:
        runner = run_command
    if not previous_layout:
        return
    for m in previous_layout:
        name = m.get("name")
        res = f"{m.get('width', 1920)}x{m.get('height', 1080)}@{m.get('refreshRate', 60)}"
        pos = f"{m.get('x', 0)}x{m.get('y', 0)}"
        scale = str(m.get("scale", 1))
        transform = str(m.get("transform", 0))
        disabled = m.get("disabled", False)
        rule_str = monitor_rule(name, res, pos, scale, transform, disabled)
        try:
            runner(["hyprctl", "keyword", "monitor", rule_str], capture_output=True, text=True)
        except Exception:
            pass

def apply_rules(rules, previous_layout=None, runner=None):
    if runner is None:
        runner = run_command
    # Safety check: do not allow disabling ALL monitors
    active_count = sum(1 for r in rules if not r.get("disabled") and r.get("res") != "disable")
    if len(rules) > 0 and active_count == 0:
        raise ValueError("Cannot disable all display outputs. At least one screen must remain active.")

    for m in rules:
        name = m.get("name")
        res = m.get("res", "preferred")
        pos = m.get("pos", "0x0")
        scale = str(m.get("scale", "1"))
        transform = str(m.get("transform", "0"))
        disabled = m.get("disabled", False)

        validate_monitor_name(name)
        if not disabled and res != "disable":
            validate_res(res)
            validate_pos(pos)
            validate_scale(scale)
            validate_transform(transform)

        rule_str = monitor_rule(name, res, pos, scale, transform, disabled)
        cmd = ["hyprctl", "keyword", "monitor", rule_str]
        try:
            res_proc = runner(cmd, capture_output=True, text=True)
            returncode = getattr(res_proc, "returncode", 0)
            if returncode != 0:
                if previous_layout:
                    _rollback_layout(previous_layout, runner=runner)
                raise RuntimeError(f"Compositor command failed with exit code {returncode}: {getattr(res_proc, 'stderr', '')}")

            dpms_action = "off" if disabled else "on"
            dpms_proc = runner(["hyprctl", "dispatch", "dpms", dpms_action, name], capture_output=True, text=True)
            dpms_returncode = getattr(dpms_proc, "returncode", 0)
            if dpms_returncode != 0:
                if previous_layout:
                    _rollback_layout(previous_layout, runner=runner)
                raise RuntimeError(f"Compositor DPMS command failed with exit code {dpms_returncode}: {getattr(dpms_proc, 'stderr', '')}")
        except FileNotFoundError:
            pass

    # Output Safety Check: Verify at least one monitor is active in Hyprland if hyprctl is present
    try:
        live_monitors = get_current_hypr_monitors(runner=runner)
        if rules and live_monitors is not None and len(live_monitors) == 0 and shutil.which("hyprctl"):
            if previous_layout:
                _rollback_layout(previous_layout, runner=runner)
            else:
                for m in rules:
                    cmd = ["hyprctl", "keyword", "monitor", f"{m['name']},preferred,auto,1"]
                    runner(cmd, capture_output=True)
            raise RuntimeError("Output configuration error detected: all displays became unviewable. Automatically rolled back to safe screen state.")
    except FileNotFoundError:
        pass

    return True

def save_to_monitors_conf(monitors, runner=None):
    if runner is None:
        runner = run_command
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    caelestia_dir = os.path.join(config_home, "caelestia")
    lua_conf = os.path.join(caelestia_dir, "display.lua")

    lua_lines = ["-- Native Caelestia Display Configuration\nreturn {\n  monitors = {\n"]
    for m in monitors:
        name = m.get("name")
        res = m.get("res", "preferred")
        pos = m.get("pos", "0x0")
        scale = float(m.get("scale", 1))
        transform = int(m.get("transform", 0))
        disabled = "true" if m.get("disabled", False) else "false"
        lua_lines.append(f'    {{ name = "{name}", res = "{res}", pos = "{pos}", scale = {scale}, transform = {transform}, disabled = {disabled} }},\n')
    lua_lines.append("  }\n}\n")

    atomic_write(lua_conf, "".join(lua_lines), mode=0o644)
    reload_hyprland(runner=runner)

def load_profiles():
    if os.path.exists(PROFILES_PATH):
        try:
            with open(PROFILES_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_profiles(profiles):
    atomic_write_json(PROFILES_PATH, profiles, mode=0o600)

def start_daemon_watcher(token, timeout=20):
    script_path = os.path.abspath(__file__)
    subprocess.Popen(
        [sys.executable, script_path, "daemon-watch", token, str(timeout)],
        start_new_session=True,
        close_fds=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )

def run_daemon_watch(token, timeout=20.0, runner=None):
    if runner is None:
        runner = run_command
    rollback_path = get_rollback_path()
    start_time = time.time()
    poll_interval = 0.5
    while time.time() - start_time < timeout:
        time.sleep(poll_interval)
        with TransactionLock():
            if not os.path.exists(rollback_path):
                return
            try:
                with open(rollback_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if data.get("token") != token:
                    return
            except Exception:
                return

    with TransactionLock():
        if os.path.exists(rollback_path):
            try:
                with open(rollback_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if data.get("token") == token:
                    previous_layout = data.get("previous_layout", [])
                    if previous_layout:
                        rules = []
                        for m in previous_layout:
                            res = f"{m.get('width', 1920)}x{m.get('height', 1080)}@{m.get('refreshRate', 60)}"
                            pos = f"{m.get('x', 0)}x{m.get('y', 0)}"
                            rules.append({
                                "name": m.get("name"),
                                "res": res,
                                "pos": pos,
                                "scale": str(m.get("scale", 1)),
                                "transform": str(m.get("transform", 0)),
                                "disabled": m.get("disabled", False)
                            })
                        apply_rules(rules, runner=runner)
                    os.remove(rollback_path)
            except Exception as e:
                print(f"Error during daemon automatic rollback: {e}", file=sys.stderr)

def write_rollback_file(rollback_info):
    rollback_path = get_rollback_path()
    atomic_write_json(rollback_path, rollback_info, mode=0o600)

def main():
    parser = argparse.ArgumentParser(description="Interactive Visual Monitor Manager CLI")
    subparsers = parser.add_subparsers(dest="subcommand")

    # daemon-watch
    daemon_parser = subparsers.add_parser("daemon-watch")
    daemon_parser.add_argument("token")
    daemon_parser.add_argument("timeout", nargs="?", default="20")

    # apply / apply-json
    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--monitors-json", help="JSON string of monitors array")
    apply_parser.add_argument("--name", help="Monitor name")
    apply_parser.add_argument("--resolution", "--res", dest="res", help="Resolution e.g. 1920x1080@60")
    apply_parser.add_argument("--position", "--pos", dest="pos", help="Position e.g. 0x0")
    apply_parser.add_argument("--scale", help="Scale factor e.g. 1.25")
    apply_parser.add_argument("--transform", default="0", help="Transform index 0-3")
    apply_parser.add_argument("--old-res")
    apply_parser.add_argument("--old-pos")
    apply_parser.add_argument("--old-scale")

    # confirm
    confirm_parser = subparsers.add_parser("confirm")
    confirm_parser.add_argument("token", nargs="?", default="")

    # rollback
    rollback_parser = subparsers.add_parser("rollback")
    rollback_parser.add_argument("token", nargs="?", default="")

    # status
    subparsers.add_parser("status")

    # move-window
    move_parser = subparsers.add_parser("move-window")
    move_parser.add_argument("target", help="Target monitor name")

    # profile
    profile_parser = subparsers.add_parser("profile")
    profile_parser.add_argument("action", choices=["list", "save", "load", "delete"])
    profile_parser.add_argument("name", nargs="?", default="")
    profile_parser.add_argument("--monitors-json", help="Monitors JSON for saving profile")

    # legacy flags support
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--save", action="store_true")
    parser.add_argument("--name")
    parser.add_argument("--res")
    parser.add_argument("--pos")
    parser.add_argument("--scale")
    parser.add_argument("--transform", default="0")
    parser.add_argument("--old-res")
    parser.add_argument("--old-pos")
    parser.add_argument("--old-scale")
    parser.add_argument("--monitors-json")

    args = parser.parse_args()

    if getattr(args, "subcommand", None) == "daemon-watch":
        token = args.token
        try:
            timeout = float(args.timeout)
        except ValueError:
            timeout = 20.0
        run_daemon_watch(token, timeout)
        return

    if args.apply:
        subcommand = "apply"
    elif args.save:
        subcommand = "save_legacy"
    else:
        subcommand = args.subcommand

    rollback_path = get_rollback_path()

    if subcommand == "status":
        monitors = get_current_hypr_monitors() or []
        profiles = load_profiles()
        print(json.dumps({
            "monitors": monitors,
            "mode": "extend" if len(monitors) > 1 else "laptop",
            "profiles": list(profiles.keys())
        }))
        return

    if subcommand == "confirm":
        token = (getattr(args, "token", "") or "").strip()
        if not token:
            print(json.dumps({"saved": False, "error": "Token is required and cannot be empty."}), file=sys.stderr)
            sys.exit(1)
        with TransactionLock():
            if os.path.exists(rollback_path):
                try:
                    with open(rollback_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    if data.get("token") != token:
                        print(json.dumps({"saved": False, "error": "Token mismatch or expired transaction."}), file=sys.stderr)
                        sys.exit(1)
                    pending_layout = data.get("pending_layout", [])
                    save_to_monitors_conf(pending_layout)
                    try:
                        os.remove(rollback_path)
                    except OSError:
                        pass
                    print(json.dumps({"saved": True, "message": "Layout saved permanently."}))
                    return
                except Exception as e:
                    print(json.dumps({"saved": False, "error": str(e)}), file=sys.stderr)
                    sys.exit(1)
            else:
                print(json.dumps({"saved": False, "error": "No active rollback transaction found."}), file=sys.stderr)
                sys.exit(1)

    if subcommand == "rollback":
        token = (getattr(args, "token", "") or "").strip()
        if not token:
            print(json.dumps({"reverted": False, "error": "Token is required and cannot be empty."}), file=sys.stderr)
            sys.exit(1)
        with TransactionLock():
            if os.path.exists(rollback_path):
                try:
                    with open(rollback_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    if data.get("token") != token:
                        print(json.dumps({"reverted": False, "error": "Token mismatch or expired transaction."}), file=sys.stderr)
                        sys.exit(1)
                    previous_layout = data.get("previous_layout", [])
                    if previous_layout:
                        rules = []
                        for m in previous_layout:
                            res = f"{m.get('width', 1920)}x{m.get('height', 1080)}@{m.get('refreshRate', 60)}"
                            pos = f"{m.get('x', 0)}x{m.get('y', 0)}"
                            rules.append({
                                "name": m.get("name"),
                                "res": res,
                                "pos": pos,
                                "scale": str(m.get("scale", 1)),
                                "transform": str(m.get("transform", 0)),
                                "disabled": m.get("disabled", False)
                            })
                        apply_rules(rules)
                    try:
                        os.remove(rollback_path)
                    except OSError:
                        pass
                    print(json.dumps({"reverted": True, "message": "Previous layout restored."}))
                    return
                except Exception as e:
                    print(json.dumps({"reverted": False, "error": str(e)}), file=sys.stderr)
                    sys.exit(1)
            else:
                print(json.dumps({"reverted": False, "error": "No active rollback transaction found."}), file=sys.stderr)
                sys.exit(1)

    if subcommand == "apply":
        with TransactionLock():
            monitors_data = []
            if getattr(args, "monitors_json", None):
                try:
                    monitors_data = json.loads(args.monitors_json)
                except Exception as e:
                    print(f"Error parsing monitors-json: {e}", file=sys.stderr)
                    sys.exit(1)
            elif getattr(args, "name", None):
                monitors_data = [{
                    "name": args.name,
                    "res": args.res or "preferred",
                    "pos": args.pos or "0x0",
                    "scale": str(args.scale or "1"),
                    "transform": str(args.transform or "0")
                }]
            else:
                print("No monitor specification provided for apply", file=sys.stderr)
                sys.exit(1)

            previous_monitors = get_current_hypr_monitors()
            try:
                apply_rules(monitors_data, previous_layout=previous_monitors)
                token = uuid.uuid4().hex[:8]
                rollback_info = {
                    "token": token,
                    "previous_layout": previous_monitors,
                    "pending_layout": monitors_data,
                    "created_at": time.time(),
                    "timeout": 20
                }
                write_rollback_file(rollback_info)
                start_daemon_watcher(token, 20)
                print(json.dumps({"token": token, "timeout": 20}))
            except Exception as e:
                print(f"Failed to apply monitor config: {e}", file=sys.stderr)
                sys.exit(1)
            return

    if subcommand == "save_legacy":
        with TransactionLock():
            monitors_data = json.loads(args.monitors_json)
            save_to_monitors_conf(monitors_data)
            print("Saved monitor layout to display.lua")
            return

    if subcommand == "move-window":
        target = args.target
        try:
            cmd = ["hyprctl", "dispatch", "movewindowmon", "silent", target]
            res = run_command(cmd, capture_output=True, text=True)
            if res.returncode == 0:
                print(f"Moved window to {target}")
            else:
                print(f"Error moving window: {res.stderr}", file=sys.stderr)
                sys.exit(1)
        except FileNotFoundError:
            print(f"Moved window to {target} (simulated)")
        return

    if subcommand == "profile":
        profiles = load_profiles()
        action = args.action
        name = args.name

        if action == "list":
            print(json.dumps({"profiles": list(profiles.keys()), "data": profiles}))
            return

        if action == "save":
            if not name:
                print("Profile name required", file=sys.stderr)
                sys.exit(1)
            with TransactionLock():
                monitors_data = []
                if getattr(args, "monitors_json", None):
                    monitors_data = json.loads(args.monitors_json)
                else:
                    current = get_current_hypr_monitors() or []
                    for m in current:
                        res = f"{m.get('width', 1920)}x{m.get('height', 1080)}@{m.get('refreshRate', 60)}"
                        pos = f"{m.get('x', 0)}x{m.get('y', 0)}"
                        monitors_data.append({
                            "name": m.get("name"),
                            "res": res,
                            "pos": pos,
                            "scale": str(m.get("scale", 1)),
                            "transform": str(m.get("transform", 0)),
                            "disabled": m.get("disabled", False)
                        })
                profiles[name] = monitors_data
                save_profiles(profiles)
                print(json.dumps({"saved": True, "name": name, "profiles": list(profiles.keys())}))
                return

        if action == "load":
            if name not in profiles:
                print(f"Profile '{name}' not found", file=sys.stderr)
                sys.exit(1)
            with TransactionLock():
                monitors_data = profiles[name]
                previous_monitors = get_current_hypr_monitors()
                try:
                    apply_rules(monitors_data, previous_layout=previous_monitors)
                    token = uuid.uuid4().hex[:8]
                    rollback_info = {
                        "token": token,
                        "previous_layout": previous_monitors,
                        "pending_layout": monitors_data,
                        "created_at": time.time(),
                        "timeout": 20
                    }
                    write_rollback_file(rollback_info)
                    start_daemon_watcher(token, 20)
                    print(json.dumps({"token": token, "timeout": 20, "profile": name}))
                except Exception as e:
                    print(f"Failed to apply profile '{name}': {e}", file=sys.stderr)
                    sys.exit(1)
                return

        if action == "delete":
            if name in profiles:
                with TransactionLock():
                    del profiles[name]
                    save_profiles(profiles)
            print(json.dumps({"deleted": True, "name": name, "profiles": list(profiles.keys())}))
            return

    parser.print_help()

if __name__ == "__main__":
    main()
