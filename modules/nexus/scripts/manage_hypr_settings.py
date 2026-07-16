#!/usr/bin/env python3
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

ALLOWED_KEYWORDS = {
    "input:follow_mouse",
    "binds:workspace_back_and_forth",
    "general:gaps_in",
    "general:gaps_out",
    "decoration:rounding",
    "decoration:active_opacity",
    "decoration:inactive_opacity",
}


def validate_keyword(keyword):
    if keyword not in ALLOWED_KEYWORDS:
        raise ValueError(f"Unsupported keyword: {keyword}")


def validate_value(value):
    if not re.match(r"^[a-zA-Z0-9_. -]+$", str(value)):
        raise ValueError("Invalid value")


def apply_keyword(keyword, value):
    validate_keyword(keyword)
    validate_value(value)
    result = subprocess.run(["hyprctl", "keyword", keyword, str(value)], capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr or result.stdout or "hyprctl failed", file=sys.stderr)
        sys.exit(result.returncode)
    print(f"Applied {keyword}={value}")


def ensure_source(user_conf, managed_conf):
    source_line = f"source = {managed_conf}"
    os.makedirs(os.path.dirname(user_conf), exist_ok=True)
    if not os.path.exists(user_conf):
        with open(user_conf, "w", encoding="utf-8") as f:
            f.write(f"{source_line}\n")
        return

    with open(user_conf, "r", encoding="utf-8") as f:
        content = f.read()
    if source_line in content:
        return

    backup = f"{user_conf}.bak.{int(time.time())}"
    shutil.copy2(user_conf, backup)
    with open(user_conf, "a", encoding="utf-8") as f:
        if content and not content.endswith("\n"):
            f.write("\n")
        f.write(f"{source_line}\n")


def save_settings(settings_json):
    try:
        settings = json.loads(settings_json)
    except json.JSONDecodeError:
        print("Invalid settings JSON", file=sys.stderr)
        sys.exit(1)

    for keyword, value in settings.items():
        validate_keyword(keyword)
        validate_value(value)

    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    caelestia_dir = os.path.join(config_home, "caelestia")
    managed_conf = os.path.join(caelestia_dir, "hypr-window-management.conf")
    user_conf = os.path.join(caelestia_dir, "hypr-user.conf")
    os.makedirs(caelestia_dir, exist_ok=True)

    with open(managed_conf, "w", encoding="utf-8") as f:
        f.write("# Managed by Caelestia Nexus Windows settings.\n")
        for keyword, value in settings.items():
            f.write(f"keyword = {keyword} {value}\n")

    ensure_source(user_conf, managed_conf)
    print(f"Saved window settings to {managed_conf}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--keyword")
    parser.add_argument("--value")
    parser.add_argument("--save", action="store_true")
    parser.add_argument("--settings-json")
    args = parser.parse_args()

    try:
        if args.apply:
            apply_keyword(args.keyword, args.value)
        elif args.save:
            save_settings(args.settings_json)
        else:
            parser.print_help()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
