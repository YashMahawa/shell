pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components

Column {
    id: root

    property bool reachable: false
    property bool autoSync: false
    property bool callsEnabled: true
    property bool notificationsEnabled: true
    width: 390
    spacing: Tokens.spacing.medium

    function applySettings(value: var): void {
        root.autoSync = value.autoClipboardSync ?? false;
        root.callsEnabled = value.callsEnabled ?? true;
        root.notificationsEnabled = value.notificationsEnabled ?? true;
    }

    Process {
        command: ["caelestia-continuity", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.reachable = value.reachable ?? false;
                    root.applySettings(value);
                } catch (error) {
                    root.reachable = false;
                }
            }
        }
    }

    FileView {
        path: "/home/yash/.config/caelestia/continuity.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.applySettings(JSON.parse(text())); }
            catch (error) {}
        }
    }

    Row {
        width: parent.width
        spacing: Tokens.spacing.medium

        StyledRect {
            width: 42; height: 42; radius: 15
            color: Colours.palette.m3primaryContainer
            MaterialIcon {
                anchors.centerIn: parent
                text: "hub"
                color: Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.medium
                fill: 1
                renderType: Text.NativeRendering
            }
        }
        Column {
            width: parent.width - 58
            StyledText { text: "Caelestia Link"; color: Colours.palette.m3onSurface; font: Tokens.font.title.medium }
            StyledText {
                text: root.reachable ? "Phone connected over Wi-Fi" : "Phone is offline"
                color: root.reachable ? Colours.palette.m3secondary : Colours.palette.m3outline
                font: Tokens.font.label.medium
            }
        }
    }

    StyledRect {
        width: parent.width; height: 62; radius: 18
        color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 0.92)
        border.width: 1
        border.color: Colours.layer(root.reachable ? Colours.palette.m3primary : Colours.palette.m3outline, 0.45)

        Row {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.reachable ? "wifi_tethering" : "portable_wifi_off"
                color: root.reachable ? Colours.palette.m3secondary : Colours.palette.m3outline
                fontStyle: Tokens.font.icon.medium
                fill: 1
                renderType: Text.NativeRendering
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                StyledText { text: root.reachable ? "Ready to share" : "Waiting for phone"; color: Colours.palette.m3onSurface; font: Tokens.font.body.medium }
                StyledText { text: "Encrypted local device transport"; color: Colours.palette.m3outline; font: Tokens.font.label.small }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Tokens.spacing.small
        ActionChip {
            width: (parent.width - parent.spacing) / 2
            icon: "content_paste_go"
            label: "Send clipboard"
            onTriggered: Quickshell.execDetached(["caelestia-clipboard", "send-latest"])
        }
        ActionChip {
            width: (parent.width - parent.spacing) / 2
            icon: "notifications_active"
            label: "Find phone"
            onTriggered: Quickshell.execDetached(["caelestia-continuity", "ring"])
        }
    }

    StyledText {
        text: "Phone on this laptop"
        font: Tokens.font.label.medium
        color: Colours.palette.m3outline
    }

    PrivacyToggle {
        title: "Calls"
        detail: checked ? "Incoming calls can appear and pause media" : "Call events stay on the phone"
        icon: "phone_in_talk"
        checked: root.callsEnabled
        onTriggered: {
            root.callsEnabled = !root.callsEnabled;
            Quickshell.execDetached(["caelestia-continuity", "calls", root.callsEnabled ? "on" : "off"]);
        }
    }

    PrivacyToggle {
        title: "Phone notifications"
        detail: checked ? "Phone notifications appear on the laptop" : "Phone notifications remain private"
        icon: "notifications"
        checked: root.notificationsEnabled
        onTriggered: {
            root.notificationsEnabled = !root.notificationsEnabled;
            Quickshell.execDetached(["caelestia-continuity", "notifications", root.notificationsEnabled ? "on" : "off"]);
        }
    }

    PrivacyToggle {
        title: "Automatic clipboard sync"
        detail: checked ? "Clipboard mirrors automatically" : "Only Send clipboard shares it"
        icon: checked ? "sync_alt" : "sync_disabled"
        checked: root.autoSync
        onTriggered: {
            root.autoSync = !root.autoSync;
            Quickshell.execDetached(["caelestia-continuity", "auto-clipboard", root.autoSync ? "on" : "off"]);
        }
    }

    component ActionChip: StyledRect {
        id: chip
        required property string icon
        required property string label
        signal triggered()
        height: 48
        radius: 15
        color: chipMouse.containsMouse ? Colours.palette.m3primaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 0.9)
        Row {
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon { text: chip.icon; color: Colours.palette.m3secondary; fontStyle: Tokens.font.icon.small; renderType: Text.NativeRendering }
            StyledText { text: chip.label; color: Colours.palette.m3onSurface; font: Tokens.font.label.medium }
        }
        MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.triggered() }
    }

    component PrivacyToggle: StyledRect {
        id: toggle
        required property string title
        required property string detail
        required property string icon
        required property bool checked
        signal triggered()
        width: root.width
        height: 60
        radius: 17
        color: toggleMouse.containsMouse ? Colours.layer(Colours.palette.m3secondaryContainer, 0.58) : Colours.layer(Colours.palette.m3surfaceContainerHighest, 0.82)

        MaterialIcon {
            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
            text: toggle.icon
            color: toggle.checked ? Colours.palette.m3secondary : Colours.palette.m3outline
            fontStyle: Tokens.font.icon.small
            fill: toggle.checked ? 1 : 0
            renderType: Text.NativeRendering
        }
        Column {
            anchors.left: parent.left; anchors.leftMargin: 52
            anchors.right: switchTrack.left; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            StyledText { width: parent.width; text: toggle.title; color: Colours.palette.m3onSurface; font: Tokens.font.body.medium; elide: Text.ElideRight }
            StyledText { width: parent.width; text: toggle.detail; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
        }
        StyledRect {
            id: switchTrack
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 24; radius: 12
            color: toggle.checked ? Colours.palette.m3secondary : Colours.palette.m3surfaceContainerHighest
            border.width: toggle.checked ? 0 : 1
            border.color: Colours.palette.m3outline
            StyledRect {
                width: 18; height: 18; radius: 9
                y: 3
                x: toggle.checked ? parent.width - width - 3 : 3
                color: toggle.checked ? Colours.palette.m3onSecondary : Colours.palette.m3outline
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { id: toggleMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: toggle.triggered() }
    }
}
