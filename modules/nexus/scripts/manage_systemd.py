#!/usr/bin/env python3
import sys
import json
import subprocess
import re

# Comprehensive critical service denylist (lowercase)
CRITICAL_SERVICES = {
    # Networking
    "networkmanager.service",
    "network.service",
    "systemd-networkd.service",
    "systemd-resolved.service",
    "wpa_supplicant.service",
    "wpa_supplicant@.service",
    "iwd.service",
    "connman.service",
    "netctl.service",
    "netctl@.service",
    "dhcpcd.service",
    "dhcpcd@.service",

    # Bluetooth
    "bluetooth.service",
    "bluez.service",

    # Display Manager / Session / Desktop / Console
    "display-manager.service",
    "gdm.service",
    "sddm.service",
    "lightdm.service",
    "greetd.service",
    "caelestia.service",
    "hyprland.service",
    "wayland.service",
    "kwin.service",
    "sway.service",
    "weston.service",
    "xorg.service",
    "x11.service",
    "systemd-vconsole-setup.service",
    "getty.service",
    "getty@.service",
    "serial-getty@.service",

    # Power / Suspend / Recovery
    "systemd-suspend.service",
    "systemd-hibernate.service",
    "systemd-hybrid-sleep.service",
    "systemd-suspend-then-hibernate.service",
    "upower.service",
    "power-profiles-daemon.service",
    "tlp.service",

    # System Core / D-Bus / Polkit / Journal
    "systemd-logind.service",
    "logind.service",
    "dbus.service",
    "dbus.socket",
    "dbus-broker.service",
    "polkit.service",
    "systemd-journald.service",
    "systemd-udevd.service",
    "systemd-homed.service",
    "systemd-userdbd.service",
    "systemd-machined.service",
    "systemd-importd.service",
    "user@.service",

    # Audio / Core User Session
    "pipewire.service",
    "pipewire-pulse.service",
    "wireplumber.service",
    "pulseaudio.service",
}

# Allowlisted system services safe to manage when expert mode is off
SYSTEM_ALLOWLIST = {
    "cups.service",
    "cups-browsed.service",
    "sshd.service",
    "ssh.service",
    "avahi-daemon.service",
    "fstrim.service",
    "fstrim.timer",
    "syncthing.service",
    "syncthing@.service",
    "docker.service",
    "podman.service",
    "tailscaled.service",
    "cron.service",
    "crond.service",
    "atd.service",
    "lm_sensors.service",
    "smartd.service",
}

def get_candidate_names(unit_name: str) -> set:
    """Returns candidate names for template and alias matching."""
    candidates = {unit_name.lower()}
    if not unit_name.endswith(".service"):
        unit_name_svc = unit_name + ".service"
        candidates.add(unit_name_svc.lower())
    else:
        unit_name_svc = unit_name

    # Check for template unit instance, e.g. getty@tty1.service -> getty@.service and getty.service
    if "@" in unit_name_svc:
        base_name = re.sub(r'@[^.]*\.', '@.', unit_name_svc)
        candidates.add(base_name.lower())
        no_at_name = re.sub(r'@[^.]*\.', '.', unit_name_svc)
        candidates.add(no_at_name.lower())

    return candidates

def resolve_unit_info(unit_name: str, user=False) -> dict:
    """Queries systemctl show to get Id, Names, and candidate aliases."""
    base_cmd = ["systemctl", "--user"] if user else ["systemctl"]
    aliases = get_candidate_names(unit_name)
    canonical_id = unit_name
    try:
        res = subprocess.run(
            base_cmd + ["show", unit_name, "--property=Id,Names"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3
        )
        if res.returncode == 0 and res.stdout:
            for line in res.stdout.splitlines():
                if line.startswith("Id="):
                    canonical_id = line.split("=", 1)[1].strip()
                    aliases.update(get_candidate_names(canonical_id))
                elif line.startswith("Names="):
                    names = line.split("=", 1)[1].strip().split()
                    for n in names:
                        aliases.update(get_candidate_names(n))
    except Exception:
        pass
    return {"id": canonical_id, "aliases": aliases}

def evaluate_critical_status(unit_name: str, aliases: set = None) -> tuple:
    """Evaluates whether a unit or any of its aliases/templates is critical."""
    candidates = get_candidate_names(unit_name)
    if aliases:
        candidates.update(aliases)

    for c in candidates:
        if c in CRITICAL_SERVICES:
            if any(k in c for k in ("network", "wpa", "iwd", "connman", "netctl", "dhcp")):
                return True, "Networking service (critical for connectivity)"
            elif "blue" in c:
                return True, "Bluetooth service (critical for wireless peripherals)"
            elif any(k in c for k in ("display", "gdm", "sddm", "lightdm", "greetd", "caelestia", "hyprland", "wayland", "kwin", "sway")):
                return True, "Display manager / Graphical session service"
            elif any(k in c for k in ("suspend", "hibernate", "power", "upower", "tlp")):
                return True, "Power management / Suspend & Recovery service"
            elif any(k in c for k in ("pipewire", "wireplumber", "pulse")):
                return True, "Audio system service"
            else:
                return True, "System core / Session critical service"
    return False, ""

def is_allowlisted(unit_name: str, aliases: set = None) -> bool:
    candidates = get_candidate_names(unit_name)
    if aliases:
        candidates.update(aliases)
    return any(c in SYSTEM_ALLOWLIST for c in candidates)

def get_services(user=False) -> dict:
    base_cmd = ["systemctl", "--user"] if user else ["systemctl"]
    units_map = {}
    errors = []

    # 1. Get running/loaded units
    try:
        res = subprocess.run(
            base_cmd + ["list-units", "--type=service", "--all", "--output=json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )
        if res.returncode != 0:
            err_msg = res.stderr.strip() or f"systemctl exited with code {res.returncode}"
            sys.stderr.write(f"Discovery error (list-units): {err_msg}\n")
            errors.append(err_msg)
        elif res.stdout.strip():
            for u in json.loads(res.stdout):
                unit_full = u.get("unit", "")
                if unit_full and unit_full.endswith(".service"):
                    name = unit_full[:-8]
                    units_map[unit_full] = {
                        "unit": unit_full,
                        "name": name,
                        "active": u.get("active", "inactive"),
                        "sub": u.get("sub", "dead"),
                        "description": u.get("description", "") or name,
                        "fileState": "unknown"
                    }
    except Exception as e:
        err_msg = f"Failed to query systemctl list-units: {str(e)}"
        sys.stderr.write(f"Discovery exception: {err_msg}\n")
        errors.append(err_msg)

    # 2. Get unit files (enabled/disabled states)
    try:
        res = subprocess.run(
            base_cmd + ["list-unit-files", "--type=service", "--output=json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )
        if res.returncode != 0:
            err_msg = res.stderr.strip() or f"systemctl list-unit-files exited with code {res.returncode}"
            sys.stderr.write(f"Discovery error (list-unit-files): {err_msg}\n")
            errors.append(err_msg)
        elif res.stdout.strip():
            for f in json.loads(res.stdout):
                unit_full = f.get("unit_file", "")
                if not unit_full or not unit_full.endswith(".service"):
                    continue
                state = f.get("state", "unknown")
                name = unit_full[:-8]
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
        err_msg = f"Failed to query systemctl list-unit-files: {str(e)}"
        sys.stderr.write(f"Discovery exception: {err_msg}\n")
        errors.append(err_msg)

    # 3. Enrich units with critical status & allowlist flags
    services = []
    for unit_full, item in units_map.items():
        info = resolve_unit_info(unit_full, user=user)
        is_crit, reason = evaluate_critical_status(unit_full, info["aliases"])
        item["isCritical"] = is_crit
        item["criticalReason"] = reason
        item["isAllowlisted"] = is_allowlisted(unit_full, info["aliases"])
        services.append(item)

    services.sort(key=lambda s: s["name"].lower())

    error_summary = "; ".join(errors) if errors and not services else None
    return {
        "success": error_summary is None,
        "error": error_summary,
        "services": services
    }

def get_impact_preview(unit_name: str, user=False) -> dict:
    """Analyzes unit dependencies and impact on other services."""
    base_cmd = ["systemctl", "--user"] if user else ["systemctl"]
    try:
        info = resolve_unit_info(unit_name, user=user)
        is_crit, crit_reason = evaluate_critical_status(unit_name, info["aliases"])

        res = subprocess.run(
            base_cmd + ["show", unit_name, "--property=Id,Names,Requires,RequiredBy,Wants,WantedBy,ConsistsOf"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5
        )

        required_by = []
        wanted_by = []
        consists_of = []
        if res.returncode == 0 and res.stdout:
            for line in res.stdout.splitlines():
                if line.startswith("RequiredBy="):
                    required_by = [x for x in line.split("=", 1)[1].split() if x.endswith(".service")]
                elif line.startswith("WantedBy="):
                    wanted_by = [x for x in line.split("=", 1)[1].split() if x.endswith(".service")]
                elif line.startswith("ConsistsOf="):
                    consists_of = [x for x in line.split("=", 1)[1].split() if x.endswith(".service")]

        active_dependents = []
        all_dependents = list(set(required_by + wanted_by + consists_of))

        # Check which dependents are currently active
        for dep in all_dependents:
            dep_res = subprocess.run(
                base_cmd + ["is-active", dep],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=3
            )
            if dep_res.returncode == 0 and dep_res.stdout.strip() == "active":
                active_dependents.append(dep)

        # Check if any active dependent is critical
        is_critical_chain = is_crit
        chain_reason = crit_reason

        if not is_critical_chain:
            for dep in active_dependents:
                dep_info = resolve_unit_info(dep, user=user)
                dep_crit, dep_reason = evaluate_critical_status(dep, dep_info["aliases"])
                if dep_crit:
                    is_critical_chain = True
                    chain_reason = f"Impacts active critical dependent service '{dep}' ({dep_reason})"
                    break

        return {
            "success": True,
            "unit": unit_name,
            "isCritical": is_crit,
            "criticalReason": crit_reason,
            "requiredBy": required_by,
            "wantedBy": wanted_by,
            "activeDependents": active_dependents,
            "isCriticalChain": is_critical_chain,
            "chainReason": chain_reason,
            "error": None
        }
    except Exception as e:
        err_msg = f"Failed to calculate impact preview for {unit_name}: {str(e)}"
        sys.stderr.write(f"{err_msg}\n")
        return {
            "success": False,
            "unit": unit_name,
            "isCritical": False,
            "criticalReason": "",
            "requiredBy": [],
            "wantedBy": [],
            "activeDependents": [],
            "isCriticalChain": False,
            "chainReason": "",
            "error": err_msg
        }

def main():
    if len(sys.argv) > 1:
        mode = sys.argv[1]
        if mode == "list":
            is_user = len(sys.argv) > 2 and sys.argv[2] == "user"
            res = get_services(user=is_user)
            print(json.dumps(res))
        elif mode == "impact":
            if len(sys.argv) > 2:
                unit_name = sys.argv[2]
                is_user = len(sys.argv) > 3 and sys.argv[3] == "user"
                res = get_impact_preview(unit_name, user=is_user)
                print(json.dumps(res))
            else:
                sys.stderr.write("Error: missing unit name for impact subcommand\n")
                sys.exit(1)
        else:
            sys.stderr.write(f"Error: unknown mode '{mode}'\n")
            sys.exit(1)
    else:
        sys.stderr.write("Error: missing command\n")
        sys.exit(1)

if __name__ == "__main__":
    main()

