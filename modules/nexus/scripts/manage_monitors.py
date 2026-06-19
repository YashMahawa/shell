#!/usr/bin/env python3
import sys
import re
import subprocess
import os
import shutil
import argparse
import json
import time

def validate_monitor_name(name):
    if not re.match(r'^[a-zA-Z0-9_-]+$', name):
        raise ValueError(f"Invalid monitor name: {name}")

def validate_res(res):
    if not re.match(r'^\d+x\d+@[\d\.]+$', res) and not re.match(r'^\d+x\d+$', res) and res not in ["preferred", "disable"]:
        raise ValueError("Invalid resolution")

def validate_pos(pos):
    if not re.match(r'^-?\d+x-?\d+$', pos) and pos != "auto":
        raise ValueError("Invalid position")

def validate_scale(scale):
    if not re.match(r'^[\d\.]+$', str(scale)):
        raise ValueError("Invalid scale")

def validate_transform(transform):
    if not re.match(r'^[0-7]$', str(transform)):
        raise ValueError("Invalid transform")

def monitor_rule(name, res, pos, scale, transform=None):
    if res == "disable":
        return f"{name},disable"
    if transform is None:
        return f"{name},{res},{pos},{scale}"
    return f"{name},{res},{pos},{scale},transform,{transform}"

def reload_hyprland():
    subprocess.run(["hyprctl", "reload"], capture_output=True, text=True)

def apply_monitor(name, res, pos, scale, old_res, old_pos, old_scale, transform="0"):
    validate_monitor_name(name)
    validate_res(res)
    if res != "disable":
        validate_pos(pos)
        validate_scale(scale)
        validate_transform(transform)

    cmd = ["hyprctl", "keyword", "monitor", monitor_rule(name, res, pos, scale, transform)]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        # Some versions of hyprctl return 0 but say "invalid" in output
        if "invalid" in result.stdout.lower() or "error" in result.stdout.lower() or "fail" in result.stdout.lower():
            raise subprocess.CalledProcessError(1, cmd, result.stdout, result.stderr)
        print(f"Applied monitor {name}: {monitor_rule(name, res, pos, scale, transform)}")
        return True
    except subprocess.CalledProcessError as e:
        # Rollback
        print(f"Failed to apply monitor config, rolling back. Error: {e.stdout} {e.stderr}", file=sys.stderr)
        old_cmd = ["hyprctl", "keyword", "monitor", monitor_rule(name, old_res, old_pos, old_scale)]
        subprocess.run(old_cmd, capture_output=True)
        sys.exit(1)

def save_monitors(monitors_json):
    try:
        monitors = json.loads(monitors_json)
    except json.JSONDecodeError:
        print("Invalid JSON for monitors", file=sys.stderr)
        sys.exit(1)

    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    config_dir = os.path.join(config_home, "hypr")
    os.makedirs(config_dir, exist_ok=True)
    monitors_conf_path = os.path.join(config_dir, "monitors.conf")
    hyprland_conf_path = os.path.join(config_dir, "hyprland.conf")

    for m in monitors:
        validate_monitor_name(m.get("name"))
        validate_res(m.get("res"))
        if m.get("res") != "disable":
            validate_pos(m.get("pos"))
            validate_scale(m.get("scale"))
            validate_transform(m.get("transform", "0"))

    if os.path.exists(hyprland_conf_path):
        with open(hyprland_conf_path, "r") as f:
            content = f.read()

        source_line = f"source = {monitors_conf_path}"
        if source_line not in content:
            timestamp = int(time.time())
            backup_path = f"{hyprland_conf_path}.bak.{timestamp}"
            shutil.copy2(hyprland_conf_path, backup_path)
            try:
                with open(hyprland_conf_path, "a") as f:
                    f.write(f"\n{source_line}\n")
                print(f"Added source to hyprland.conf (backup saved to {backup_path})")
            except Exception as e:
                print(f"Failed to update hyprland.conf: {e}", file=sys.stderr)
                shutil.copy2(backup_path, hyprland_conf_path)
                sys.exit(1)
        else:
            print("source already in hyprland.conf")

    try:
        with open(monitors_conf_path, "w") as f:
            for m in monitors:
                f.write(f"monitor = {monitor_rule(m['name'], m['res'], m.get('pos', 'auto'), m.get('scale', '1'), m.get('transform', '0'))}\n")
        reload_hyprland()
        print(f"Saved monitor layout to {monitors_conf_path}")
    except Exception as e:
        print(f"Failed to write monitors.conf: {e}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--name")
    parser.add_argument("--res")
    parser.add_argument("--pos")
    parser.add_argument("--scale")
    parser.add_argument("--transform", default="0")
    parser.add_argument("--old-res")
    parser.add_argument("--old-pos")
    parser.add_argument("--old-scale")

    parser.add_argument("--save", action="store_true")
    parser.add_argument("--monitors-json")

    args = parser.parse_args()

    if args.apply:
        apply_monitor(args.name, args.res, args.pos, args.scale, args.old_res, args.old_pos, args.old_scale, args.transform)
    elif args.save:
        save_monitors(args.monitors_json)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
