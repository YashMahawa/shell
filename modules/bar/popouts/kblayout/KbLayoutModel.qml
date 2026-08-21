pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services

Item {
    id: model

    property alias visibleModel: visibleModel
    property string activeLabel: ""
    property int activeIndex: -1
    property bool _notifiedLimit: false

    function start() {
        updateFromHypr();
    }

    function refresh() {
        _notifiedLimit = false;
        if (Hypr.extras)
            Hypr.extras.refreshDevices();
        updateFromHypr();
    }

    function switchTo(idx) {
        switchProc.command = ["hyprctl", "switchxkblayout", "all", String(idx)];
        switchProc.running = true;
    }

    function updateFromHypr() {
        const kb = Hypr.keyboard;
        if (!kb)
            return;

        const raw = (kb.layout || "").trim();
        if (raw.length > 0) {
            _setLayouts(raw);
        }

        const ipcObj = kb.lastIpcObject || {};
        const idx = ipcObj.active_layout_index ?? -1;

        model.activeIndex = idx >= 0 ? idx : 0;
        model.activeLabel = (model.activeIndex >= 0 && model.activeIndex < layoutsModel.count)
            ? layoutsModel.get(model.activeIndex).label
            : "";

        _rebuildVisible();
    }

    function _setLayouts(raw) {
        if (!raw)
            return;
        const parts = raw.split(",").map(s => s.trim()).filter(Boolean);

        layoutsModel.clear();
        for (let idx = 0; idx < parts.length; idx++) {
            const token = parts[idx];
            layoutsModel.append({
                layoutIndex: idx,
                token: token,
                label: _pretty(token)
            });
        }
    }

    function _pretty(token) {
        if (!token)
            return "";

        const match = token.match(/^([a-zA-Z0-9_-]+)(?:\(([^)]+)\))?$/);
        if (!match)
            return token.toUpperCase();

        const code = match[1];
        const variant = match[2] || "";
        const cache = Hypr.layoutCache || {};

        if (variant) {
            const exactDesc = cache[token] || cache[`${code}:${variant}`];
            if (exactDesc)
                return `${code.toUpperCase()} (${variant}) - ${exactDesc}`;

            const baseDesc = cache[code];
            if (baseDesc)
                return `${code.toUpperCase()} (${variant}) - ${baseDesc} (${variant})`;

            return `${code.toUpperCase()} (${variant}) - ${code} (${variant})`;
        } else {
            const baseDesc = cache[code];
            if (baseDesc)
                return `${code.toUpperCase()} - ${baseDesc}`;

            return `${code.toUpperCase()} - ${code}`;
        }
    }

    function _rebuildVisible() {
        const desired = [];
        for (let i = 0; i < layoutsModel.count; i++) {
            const item = layoutsModel.get(i);
            if (item.layoutIndex !== activeIndex) {
                desired.push({
                    layoutIndex: item.layoutIndex,
                    token: item.token,
                    label: item.label
                });
            }
        }

        // In-place reconciliation of visibleModel
        for (let i = 0; i < desired.length; i++) {
            const target = desired[i];
            if (i < visibleModel.count) {
                const current = visibleModel.get(i);
                if (current.layoutIndex === target.layoutIndex) {
                    if (current.label !== target.label || current.token !== target.token) {
                        visibleModel.setProperty(i, "label", target.label);
                        visibleModel.setProperty(i, "token", target.token);
                    }
                } else {
                    let foundIdx = -1;
                    for (let j = i + 1; j < visibleModel.count; j++) {
                        if (visibleModel.get(j).layoutIndex === target.layoutIndex) {
                            foundIdx = j;
                            break;
                        }
                    }
                    if (foundIdx !== -1) {
                        visibleModel.move(foundIdx, i, 1);
                        visibleModel.setProperty(i, "label", target.label);
                        visibleModel.setProperty(i, "token", target.token);
                    } else {
                        visibleModel.insert(i, target);
                    }
                }
            } else {
                visibleModel.append(target);
            }
        }

        while (visibleModel.count > desired.length) {
            visibleModel.remove(visibleModel.count - 1);
        }

        if (GlobalConfig.utilities.toasts.kbLimit && layoutsModel.count > 4) {
            if (!_notifiedLimit) {
                _notifiedLimit = true;
                Toaster.toast(qsTr("Keyboard layout limit"), qsTr("XKB supports only 4 layouts at a time"), "warning");
            }
        }
    }

    visible: false

    ListModel {
        id: visibleModel
    }

    ListModel {
        id: layoutsModel
    }

    Connections {
        target: Hypr
        function onLayoutCacheChanged() {
            model.updateFromHypr();
        }
    }

    Connections {
        target: Hypr.keyboard ? Hypr.keyboard : null
        function onLastIpcObjectChanged() {
            model.updateFromHypr();
        }
        function onLayoutChanged() {
            model.updateFromHypr();
        }
    }

    Process {
        id: switchProc

        onRunningChanged: if (!running) {
            if (Hypr.extras)
                Hypr.extras.refreshDevices();
            model.updateFromHypr();
        }
    }
}
