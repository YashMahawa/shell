pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

Column {
    id: root

    property bool reachable: false
    property bool autoSync: false
    property list<var> items: []
    width: 390
    spacing: Tokens.spacing.medium

    Process {
        command: ["caelestia-continuity", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text);
                    root.reachable = value.reachable ?? false;
                    root.autoSync = value.autoClipboardSync ?? false;
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
            try { root.autoSync = JSON.parse(text()).autoClipboardSync ?? false; }
            catch (error) { root.autoSync = false; }
        }
    }

    FileView {
        path: "/home/yash/.local/state/caelestia/clipboard-history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.items = JSON.parse(text()).slice(0, 3); }
            catch (error) { root.items = []; }
        }
    }

    Row {
        width: parent.width
        spacing: Tokens.spacing.medium

        StyledRect {
            width: 42; height: 42; radius: 15
            color: Colours.palette.m3primaryContainer
            ColouredIcon {
                anchors.centerIn: parent
                source: Quickshell.iconPath("kdeconnect-symbolic", "kdeconnect")
                implicitSize: 23
                colour: Colours.palette.m3onPrimaryContainer
            }
        }
        Column {
            width: parent.width - 58
            StyledText { text: "Continuity"; font: Tokens.font.title.medium }
            StyledText {
                text: root.reachable ? "T2 5G connected over Wi-Fi" : "T2 5G is offline"
                color: root.reachable ? Colours.palette.m3primary : Colours.palette.m3outline
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
                color: root.reachable ? Colours.palette.m3primary : Colours.palette.m3outline
                fontStyle: Tokens.font.icon.medium
                fill: 1
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                StyledText { text: root.reachable ? "Ready to share" : "Waiting for phone"; font: Tokens.font.body.medium }
                StyledText { text: "Encrypted KDE Connect transport"; color: Colours.palette.m3outline; font: Tokens.font.label.small }
            }
        }
    }

    Row {
        width: parent.width
        spacing: Tokens.spacing.small
        ActionChip { width: (parent.width - parent.spacing * 2) / 3; icon: "folder_shared"; label: "Browse"; onTriggered: Quickshell.execDetached(["caelestia-continuity", "browse"]) }
        ActionChip { width: (parent.width - parent.spacing * 2) / 3; icon: "notifications_active"; label: "Find phone"; onTriggered: Quickshell.execDetached(["kdeconnect-cli", "-n", "T2 5G", "--ring"]) }
        ActionChip { width: (parent.width - parent.spacing * 2) / 3; icon: "sync"; label: "File sync"; onTriggered: Quickshell.execDetached(["caelestia-continuity", "sync"]) }
    }

    StyledRect {
        width: parent.width; height: 56; radius: 17
        color: autoMouse.containsMouse ? Colours.layer(Colours.palette.m3secondaryContainer, 0.58) : Colours.layer(Colours.palette.m3surfaceContainerHighest, 0.82)

        MaterialIcon {
            anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
            text: root.autoSync ? "sync_alt" : "sync_disabled"
            color: root.autoSync ? Colours.palette.m3primary : Colours.palette.m3outline
            fontStyle: Tokens.font.icon.small
        }
        Column {
            anchors.left: parent.left; anchors.leftMargin: 52; anchors.verticalCenter: parent.verticalCenter
            StyledText { text: "Automatic clipboard sync"; font: Tokens.font.body.medium }
            StyledText { text: root.autoSync ? "On • clipboard mirrors between devices" : "Off • only explicit Send actions share"; color: Colours.palette.m3outline; font: Tokens.font.label.small }
        }
        StyledText {
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            text: root.autoSync ? "ON" : "OFF"
            color: root.autoSync ? Colours.palette.m3primary : Colours.palette.m3outline
            font: Tokens.font.label.medium
        }
        MouseArea {
            id: autoMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.autoSync = !root.autoSync;
                Quickshell.execDetached(["caelestia-continuity", "auto-clipboard", root.autoSync ? "on" : "off"]);
            }
        }
    }

    StyledText {
        text: "Recent clipboard"
        font: Tokens.font.label.medium
        color: Colours.palette.m3outline
    }

    Repeater {
        model: root.items

        StyledRect {
            id: recent
            required property var modelData
            width: root.width; height: 52; radius: 15
            color: Colours.layer(Colours.palette.m3surfaceContainer, 0.9)

            MaterialIcon {
                anchors.left: parent.left; anchors.leftMargin: 13; anchors.verticalCenter: parent.verticalCenter
                text: recent.modelData.kind === "image" ? "image" : recent.modelData.kind === "files" ? "draft" : "notes"
                color: Colours.palette.m3secondary
            }
            StyledText {
                anchors.left: parent.left; anchors.leftMargin: 47; anchors.right: send.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                text: recent.modelData.kind === "image" ? "Copied image or screenshot" : recent.modelData.text
                elide: Text.ElideRight
                font: Tokens.font.body.medium
            }
            MaterialIcon {
                id: send
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                text: "send_to_mobile"
                color: Colours.palette.m3primary
                StateLayer {
                    anchors.fill: parent
                    anchors.margins: -9
                    radius: Tokens.rounding.full
                    onClicked: Quickshell.execDetached(["caelestia-clipboard", "send", String(recent.modelData.id)])
                }
            }
        }
    }

    StyledText {
        visible: root.items.length === 0
        text: "Nothing copied yet"
        color: Colours.palette.m3outline
        anchors.horizontalCenter: parent.horizontalCenter
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
            MaterialIcon { text: chip.icon; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.small }
            StyledText { text: chip.label; font: Tokens.font.label.medium }
        }
        MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.triggered() }
    }
}
