pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

Column {
    id: root

    property bool reachable: false
    property string connection: "offline"
    property string transport: "offline"
    property string transportLabel: "Disconnected"
    property bool autoSync: false
    property bool notificationsEnabled: true
    width: 390
    spacing: Tokens.spacing.medium

    function applySettings(value: var): void {
        root.autoSync = value.autoClipboardSync ?? false;
        root.notificationsEnabled = value.notificationsEnabled ?? true;
        root.transport = value.transport ?? "offline";
        root.transportLabel = value.transportLabel ?? (root.reachable ? "local network" : "Disconnected");
    }

    Process {
        command: ["caelestia-continuity", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.reachable = value.reachable ?? false;
                    root.connection = value.connection ?? (root.reachable ? "connected" : "offline");
                    root.applySettings(value);
                } catch (error) {
                    root.reachable = false;
                }
            }
        }
    }

    FileView {
        path: "/home/yash/.local/state/caelestia/continuity.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const value = JSON.parse(text());
                root.reachable = value.reachable ?? false;
                root.connection = value.connection ?? (root.reachable ? "connected" : "offline");
                root.applySettings(value);
            }
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
            spacing: 2
            StyledText {
                text: "Caelestia Link"
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.medium
            }
            StyledText {
                text: root.reachable ? `Phone connected over ${root.transportLabel}` : "Phone disconnected"
                color: root.reachable ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium
            }
        }
    }

    StyledRect {
        width: parent.width
        height: 62
        radius: 18
        color: Colours.tPalette.m3surfaceContainerHigh
        border.width: 1
        border.color: root.reachable ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

        Row {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.medium
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.reachable ? "wifi_tethering" : "portable_wifi_off"
                color: root.reachable ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
                fill: 1
                renderType: Text.NativeRendering
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                StyledText {
                    text: root.reachable ? `Ready over ${root.transportLabel}` : "Connection unavailable"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.medium
                }
                StyledText {
                    text: root.reachable ? "Encrypted local device transport" : "Reconnect when the phone is on the same network"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Tokens.spacing.small
        ActionChip {
            width: (parent.width - parent.spacing) / 2
            icon: root.reachable ? "content_paste_go" : "sync"
            label: root.reachable ? "Send clipboard" : "Reconnect"
            onTriggered: Quickshell.execDetached(root.reachable
                ? ["caelestia-clipboard", "send-latest"]
                : ["caelestia-continuity", "reconnect"])
        }
        ActionChip {
            width: (parent.width - parent.spacing) / 2
            icon: "notifications_active"
            label: "Find phone"
            onTriggered: Quickshell.execDetached(["caelestia-continuity", "ring"])
        }
    }

    StyledText {
        text: "Privacy"
        font: Tokens.font.label.medium
        color: Colours.palette.m3onSurfaceVariant
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
        color: chipMouse.containsMouse ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh
        Row {
            anchors.centerIn: parent
            spacing: 6
            MaterialIcon {
                text: chip.icon
                color: chipMouse.containsMouse ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
                renderType: Text.NativeRendering
            }
            StyledText {
                text: chip.label
                color: chipMouse.containsMouse ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                font: Tokens.font.label.medium
            }
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.triggered()
        }
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
        color: toggleMouse.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh

        MaterialIcon {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: toggle.icon
            color: toggle.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
            fill: toggle.checked ? 1 : 0
            renderType: Text.NativeRendering
        }
        Column {
            anchors.left: parent.left
            anchors.leftMargin: 52
            anchors.right: switchTrack.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            StyledText {
                width: parent.width
                text: toggle.title
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                text: toggle.detail
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
        StyledRect {
            id: switchTrack
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 24
            radius: 12
            color: toggle.checked ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest
            border.width: toggle.checked ? 0 : 1
            border.color: Colours.palette.m3outlineVariant
            StyledRect {
                width: 18
                height: 18
                radius: 9
                y: 3
                x: toggle.checked ? parent.width - width - 3 : 3
                color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                Behavior on x {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
        MouseArea {
            id: toggleMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.triggered()
        }
    }
}
