#!/usr/bin/env python3
import sys
import json
import subprocess

def get_services(user=False):
    base_cmd = ["systemctl", "--user"] if user else ["systemctl"]
    units_map = {}

    # 1. Get running/loaded units
    try:
        res = subprocess.run(
            base_cmd + ["list-units", "--type=service", "--all", "--output=json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )
        if res.returncode == 0 and res.stdout.strip():
            for u in json.loads(res.stdout):
                unit_full = u.get("unit", "")
                if unit_full and unit_full.endswith(".service"):
                    name = unit_full[:-8] if unit_full.endswith(".service") else unit_full
                    units_map[unit_full] = {
                        "unit": unit_full,
                        "name": name,
                        "active": u.get("active", "inactive"),
                        "sub": u.get("sub", "dead"),
                        "description": u.get("description", "") or name,
                        "fileState": "unknown"
                    }
    except Exception as e:
        pass

    # 2. Get unit files (enabled/disabled states)
    try:
        res = subprocess.run(
            base_cmd + ["list-unit-files", "--type=service", "--output=json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )
        if res.returncode == 0 and res.stdout.strip():
            for f in json.loads(res.stdout):
                unit_full = f.get("unit_file", "")
                if not unit_full or not unit_full.endswith(".service"):
                    continue
                state = f.get("state", "unknown")
                name = unit_full[:-8] if unit_full.endswith(".service") else unit_full
                if unit_full in units_map:
                    units_map[unit_full]["fileState"] = state
                else:
                    units_map[unit_full] = {
                        "unit": unit_full,
                        "name": name,
                        "active": "inactive",
                        "sub": "dead",
                        "description": name,
                        "fileState": state
                    }
    except Exception as e:
        pass

    services = list(units_map.values())
    services.sort(key=lambda s: s["name"].lower())
    return services

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "list":
        is_user = len(sys.argv) > 2 and sys.argv[2] == "user"
        services = get_services(user=is_user)
        print(json.dumps(services))
    else:
        print(json.dumps([]))

if __name__ == "__main__":
    main()
