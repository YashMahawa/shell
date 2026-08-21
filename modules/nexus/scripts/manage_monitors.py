#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid

PROFILES_PATH = os.path.expanduser("~/.config/caelestia/display_profiles.json")
ROLLBACK_PATH = "/tmp/caelestia_display_rollback.json"

def get_config_dir():
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    return os.path.join(config_home, "hypr")

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
    if scale is None or not re.match(r'^[\d\.]+$', str(scale)):
        raise ValueError(f"Invalid scale: {scale}")

def validate_transform(transform):
    if transform is None or not re.match(r'^[0-7]$', str(transform)):
        raise ValueError(f"Invalid transform: {transform}")

def monitor_rule(name, res, pos, scale, transform="0", disabled=False):
    if disabled or res == "disable":
        return f"{name},disable"
    if str(transform) == "0":
        return f"{name},{res},{pos},{scale}"
    return f"{name},{res},{pos},{scale},transform,{transform}"

def get_current_hypr_monitors():
    try:
        res = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, check=True)
        return json.loads(res.stdout)
    except Exception:
        return []

def reload_hyprland():
    try:
        subprocess.run(["hyprctl", "reload"], capture_output=True, text=True)
    except FileNotFoundError:
        pass

def apply_rules(rules):
    # Safety check: do not allow disabling ALL monitors
    active_count = sum(1 for r in rules if not r.get("disabled") and r.get("res") != "disable")
    if len(rules) > 0 and active_count == 0:
        raise ValueError("Cannot disable all display outputs. At least one screen must remain active.")

    applied_cmd_outputs = []
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
            res_proc = subprocess.run(cmd, capture_output=True, text=True)
            if disabled:
                subprocess.run(["hyprctl", "dispatch", "dpms", "off", name], capture_output=True)
            else:
                subprocess.run(["hyprctl", "dispatch", "dpms", "on", name], capture_output=True)
            applied_cmd_outputs.append((cmd, res_proc.stdout, res_proc.stderr))
        except FileNotFoundError:
            # When hyprctl is not in system PATH (e.g. headless/mock env), simulate success
            pass

    # Output Safety Check: Verify at least one monitor is active in Hyprland if hyprctl is present
    try:
        live_monitors = get_current_hypr_monitors()
        if rules and not live_monitors and shutil.which("hyprctl"):
            # Fallback: recover all connected displays to preferred
            for m in rules:
                cmd = ["hyprctl", "keyword", "monitor", f"{m['name']},preferred,auto,1"]
                subprocess.run(cmd, capture_output=True)
            raise RuntimeError("Output configuration error detected: all displays became unviewable. Automatically rolled back to safe screen state.")
    except FileNotFoundError:
        pass

    return True

def save_to_monitors_conf(monitors):
    config_dir = get_config_dir()
    os.makedirs(config_dir, exist_ok=True)
    monitors_conf_path = os.path.join(config_dir, "monitors.conf")
    hyprland_conf_path = os.path.join(config_dir, "hyprland.conf")

    if os.path.exists(hyprland_conf_path):
        with open(hyprland_conf_path, "r") as f:
            content = f.read()
        source_line = f"source = {monitors_conf_path}"
        if source_line not in content:
            with open(hyprland_conf_path, "a") as f:
                f.write(f"\n{source_line}\n")

    with open(monitors_conf_path, "w") as f:
        for m in monitors:
            name = m.get("name")
            res = m.get("res", "preferred")
            pos = m.get("pos", "0x0")
            scale = str(m.get("scale", "1"))
            transform = str(m.get("transform", "0"))
            disabled = m.get("disabled", False)
            f.write(f"monitor = {monitor_rule(name, res, pos, scale, transform, disabled)}\n")
    reload_hyprland()

def load_profiles():
    if os.path.exists(PROFILES_PATH):
        try:
            with open(PROFILES_PATH, "r") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_profiles(profiles):
    os.makedirs(os.path.dirname(PROFILES_PATH), exist_ok=True)
    with open(PROFILES_PATH, "w") as f:
        json.dump(profiles, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Interactive Visual Monitor Manager CLI")
    subparsers = parser.add_subparsers(dest="subcommand")

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

    # Legacy argument handling
    if args.apply:
        subcommand = "apply"
    elif args.save:
        subcommand = "save_legacy"
    else:
        subcommand = args.subcommand

    if subcommand == "status":
        monitors = get_current_hypr_monitors()
        profiles = load_profiles()
        print(json.dumps({
            "monitors": monitors,
            "mode": "extend" if len(monitors) > 1 else "laptop",
            "profiles": list(profiles.keys())
        }))
        return

    if subcommand == "confirm":
        token = args.token
        if os.path.exists(ROLLBACK_PATH):
            try:
                with open(ROLLBACK_PATH, "r") as f:
                    data = json.load(f)
                if not token or data.get("token") == token:
                    pending_layout = data.get("pending_layout", [])
                    save_to_monitors_conf(pending_layout)
                    os.remove(ROLLBACK_PATH)
                    print(json.dumps({"saved": True, "message": "Layout saved permanently."}))
                    return
            except Exception as e:
                print(json.dumps({"saved": False, "error": str(e)}), file=sys.stderr)
                sys.exit(1)
        print(json.dumps({"saved": True, "message": "Confirmed."}))
        return

    if subcommand == "rollback":
        if os.path.exists(ROLLBACK_PATH):
            try:
                with open(ROLLBACK_PATH, "r") as f:
                    data = json.load(f)
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
                os.remove(ROLLBACK_PATH)
                print(json.dumps({"reverted": True, "message": "Previous layout restored."}))
                return
            except Exception as e:
                print(json.dumps({"reverted": False, "error": str(e)}), file=sys.stderr)
                sys.exit(1)
        print(json.dumps({"reverted": True, "message": "No pending rollback."}))
        return

    if subcommand == "apply":
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
            apply_rules(monitors_data)
            token = uuid.uuid4().hex[:8]
            rollback_info = {
                "token": token,
                "previous_layout": previous_monitors,
                "pending_layout": monitors_data,
                "created_at": time.time(),
                "timeout": 20
            }
            with open(ROLLBACK_PATH, "w") as f:
                json.dump(rollback_info, f)
            print(json.dumps({"token": token, "timeout": 20}))
        except Exception as e:
            print(f"Failed to apply monitor config: {e}", file=sys.stderr)
            sys.exit(1)
        return

    if subcommand == "save_legacy":
        monitors_data = json.loads(args.monitors_json)
        save_to_monitors_conf(monitors_data)
        print("Saved monitor layout to monitors.conf")
        return

    if subcommand == "move-window":
        target = args.target
        try:
            cmd = ["hyprctl", "dispatch", "movewindowmon", "silent", target]
            res = subprocess.run(cmd, capture_output=True, text=True)
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
            monitors_data = []
            if getattr(args, "monitors_json", None):
                monitors_data = json.loads(args.monitors_json)
            else:
                current = get_current_hypr_monitors()
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
            monitors_data = profiles[name]
            previous_monitors = get_current_hypr_monitors()
            try:
                apply_rules(monitors_data)
                token = uuid.uuid4().hex[:8]
                rollback_info = {
                    "token": token,
                    "previous_layout": previous_monitors,
                    "pending_layout": monitors_data,
                    "created_at": time.time(),
                    "timeout": 20
                }
                with open(ROLLBACK_PATH, "w") as f:
                    json.dump(rollback_info, f)
                print(json.dumps({"token": token, "timeout": 20, "profile": name}))
            except Exception as e:
                print(f"Failed to apply profile '{name}': {e}", file=sys.stderr)
                sys.exit(1)
            return

        if action == "delete":
            if name in profiles:
                del profiles[name]
                save_profiles(profiles)
            print(json.dumps({"deleted": True, "name": name, "profiles": list(profiles.keys())}))
            return

    parser.print_help()

if __name__ == "__main__":
    main()
