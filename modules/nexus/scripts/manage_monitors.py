#!/usr/bin/env python3
import sys
import re
import subprocess
import os
import shutil
import argparse
import json

def validate_monitor_name(name):
    if not re.match(r'^[a-zA-Z0-9_-]+$', name):
        raise ValueError(f"Invalid monitor name: {name}")

def apply_monitor(name, res, pos, scale, old_res, old_pos, old_scale):
    validate_monitor_name(name)
    if not re.match(r'^\d+x\d+@[\d\.]+$', res) and res != "preferred":
        raise ValueError("Invalid resolution")
    if not re.match(r'^-?\d+x-?\d+$', pos) and pos != "auto":
        raise ValueError("Invalid position")
    if not re.match(r'^[\d\.]+$', str(scale)):
        raise ValueError("Invalid scale")

    cmd = ["hyprctl", "keyword", "monitor", f"{name},{res},{pos},{scale}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        # Some versions of hyprctl return 0 but say "invalid" in output
        if "invalid" in result.stdout.lower() or "error" in result.stdout.lower() or "fail" in result.stdout.lower():
            raise subprocess.CalledProcessError(1, cmd, result.stdout, result.stderr)
        return True
    except subprocess.CalledProcessError as e:
        # Rollback
        print(f"Failed to apply monitor config, rolling back. Error: {e.stdout} {e.stderr}", file=sys.stderr)
        old_cmd = ["hyprctl", "keyword", "monitor", f"{name},{old_res},{old_pos},{old_scale}"]
        subprocess.run(old_cmd, capture_output=True)
        sys.exit(1)

def save_monitors(monitors_json):
    try:
        monitors = json.loads(monitors_json)
    except json.JSONDecodeError:
        print("Invalid JSON for monitors", file=sys.stderr)
        sys.exit(1)

    config_dir = os.path.expanduser("~/.config/hypr")
    os.makedirs(config_dir, exist_ok=True)
    monitors_conf_path = os.path.join(config_dir, "monitors.conf")
    hyprland_conf_path = os.path.join(config_dir, "hyprland.conf")

    with open(monitors_conf_path, "w") as f:
        for m in monitors:
            name = m.get("name")
            validate_monitor_name(name)
            res = m.get("res")
            pos = m.get("pos")
            scale = m.get("scale")
            f.write(f"monitor={name},{res},{pos},{scale}\n")

    if os.path.exists(hyprland_conf_path):
        with open(hyprland_conf_path, "r") as f:
            content = f.read()

        source_line = "source = ~/.config/hypr/monitors.conf"
        if not re.search(r'^\s*source\s*=\s*~/\.config/hypr/monitors\.conf', content, re.MULTILINE):
            # Backup
            shutil.copy2(hyprland_conf_path, hyprland_conf_path + ".bak")
            with open(hyprland_conf_path, "a") as f:
                f.write(f"\n{source_line}\n")
            print("Added source to hyprland.conf")
        else:
            print("source already in hyprland.conf")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--name")
    parser.add_argument("--res")
    parser.add_argument("--pos")
    parser.add_argument("--scale")
    parser.add_argument("--old-res")
    parser.add_argument("--old-pos")
    parser.add_argument("--old-scale")

    parser.add_argument("--save", action="store_true")
    parser.add_argument("--monitors-json")

    args = parser.parse_args()

    if args.apply:
        apply_monitor(args.name, args.res, args.pos, args.scale, args.old_res, args.old_pos, args.old_scale)
    elif args.save:
        save_monitors(args.monitors_json)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
