pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services

Singleton {
    id: root

    property bool enabled: true
    property int temperature: 4500
    readonly property real warmth: Math.max(0, Math.min(1, (6500 - temperature) / 4500))

    function setWarmth(w: real): void {
        const clamped = Math.max(0, Math.min(1, w));
        const temp = Math.round(6500 - clamped * 4500);
        setTemperature(temp);
    }

    function setTemperature(temp: int): void {
        const clampedTemp = Math.max(2000, Math.min(6500, temp));
        if (root.temperature === clampedTemp)
            return;
        root.temperature = clampedTemp;
        applyTemperature(clampedTemp);
    }

    function applyTemperature(temp: int): void {
        if (!root.enabled) {
            proc.command = [
                "bash", "-c",
                "pkill hyprsunset 2>/dev/null || true; " +
                "gammastep -x 2>/dev/null || true; " +
                "pkill wlsunset 2>/dev/null || true"
            ];
            proc.running = true;
            return;
        }

        proc.command = [
            "bash", "-c",
            `TEMP=${temp}; ` +
            `if command -v hyprsunset >/dev/null 2>&1; then ` +
                `pkill hyprsunset 2>/dev/null || true; ` +
                `if [ "$TEMP" -lt 6500 ]; then hyprsunset -t "$TEMP" & fi; ` +
            `elif command -v gammastep >/dev/null 2>&1; then ` +
                `if [ "$TEMP" -ge 6500 ]; then gammastep -x 2>/dev/null || true; ` +
                `else gammastep -P -O "$TEMP" & fi; ` +
            `elif command -v wlsunset >/dev/null 2>&1; then ` +
                `pkill wlsunset 2>/dev/null || true; ` +
                `if [ "$TEMP" -lt 6500 ]; then wlsunset -T "$TEMP" & fi; ` +
            `elif command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -q "org.gnome.settings-daemon.plugins.color"; then ` +
                `gsettings set org.gnome.settings-daemon.plugins.color night-light-temperature "$TEMP" 2>/dev/null || true; ` +
                `gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true 2>/dev/null || true; ` +
            `fi`
        ];
        proc.running = true;

        if (MonitorControl.available) {
            const mcTemp = temp >= 6500 ? "6500" : (temp <= 3000 ? "user" : String(temp));
            MonitorControl.setControl("temperature", mcTemp);
        }
    }

    Process {
        id: proc
    }
}
