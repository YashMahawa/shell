pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Scope {
    id: root

    property bool opened: false
    property bool phoneFocus: false
    property string query: ""
    property list<var> items: []
    readonly property list<var> filtered: items.filter(item => !query || (item.text ?? "").toLowerCase().includes(query.toLowerCase()))

    function close(): void {
        opened = false;
        query = "";
    }

    FileView {
        path: "/home/yash/.local/state/caelestia/clipboard-history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.items = JSON.parse(text()); }
            catch (error) { root.items = []; }
        }
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property bool targetScreen: (Hypr.focusedMonitor?.name ?? modelData.name) === modelData.name

            screen: modelData
            name: "continuity-clipboard"
            visible: root.opened && targetScreen
            implicitWidth: 620
            implicitHeight: 510
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors.top: true
            margins.top: 10

            onVisibleChanged: if (visible) surface.forceActiveFocus()

            Item {
                id: surface
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()

                StyledRect {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    radius: 30
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 0.98)
                    border.width: 1
                    border.color: Colours.layer(Colours.palette.m3primary, 0.38)

                    Column {
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        anchors.topMargin: 34
                        spacing: Tokens.spacing.medium

                        Row {
                            width: parent.width
                            height: 44
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                width: 40; height: 40; radius: 20
                                color: Colours.palette.m3primaryContainer
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: root.phoneFocus ? "mobile_screen_share" : "content_paste"
                                    color: Colours.palette.m3onPrimaryContainer
                                    fontStyle: Tokens.font.icon.medium
                                    renderType: Text.NativeRendering
                                }
                            }

                            Column {
                                width: parent.width - 144
                                StyledText { text: "Continuity"; font: Tokens.font.title.medium }
                                StyledText {
                                    text: root.phoneFocus ? "T2 5G • connected services • file sharing" : "Clipboard • screenshots • T2 5G"
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }
                            }

                            MiniButton { visible: !root.phoneFocus; icon: "delete_sweep"; tip: "Clear history"; onTriggered: Quickshell.execDetached(["caelestia-clipboard", "clear"]) }
                            MiniButton { icon: "close"; tip: "Close"; onTriggered: root.close() }
                        }

                        StyledRect {
                            visible: !root.phoneFocus
                            width: parent.width; height: 42; radius: 14
                            color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 1)
                            border.width: 1
                            border.color: search.activeFocus ? Colours.palette.m3primary : "transparent"

                            MaterialIcon {
                                anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: "search"; color: Colours.palette.m3outline; fontStyle: Tokens.font.icon.small
                            }
                            TextInput {
                                id: search
                                anchors.left: parent.left; anchors.leftMargin: 46
                                anchors.right: parent.right; anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.query
                                color: Colours.palette.m3onSurface
                                selectionColor: Colours.palette.m3primaryContainer
                                font: Tokens.font.body.medium
                                onTextChanged: root.query = text
                            }
                            StyledText {
                                anchors.left: search.left; anchors.verticalCenter: parent.verticalCenter
                                visible: !search.text
                                text: "Search clipboard history"
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.medium
                            }
                        }

                        ListView {
                            id: history
                            width: parent.width
                            visible: !root.phoneFocus
                            height: parent.height - 118
                            clip: true
                            spacing: Tokens.spacing.small
                            model: root.filtered

                            delegate: StyledRect {
                                id: card
                                required property var modelData
                                width: history.width
                                height: modelData.kind === "image" ? 92 : 68
                                radius: 16
                                color: mouse.containsMouse ? Colours.layer(Colours.palette.m3secondaryContainer, 0.52) : Colours.layer(Colours.palette.m3surfaceContainer, 0.9)

                                Image {
                                    id: preview
                                    visible: card.modelData.kind === "image"
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 72; height: 72
                                    source: visible ? "file://" + card.modelData.path : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: card.modelData.kind === "image" ? 94 : 16
                                    anchors.right: actions.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    StyledText {
                                        width: parent.width
                                        text: card.modelData.kind === "image" ? "Screenshot or copied image" : card.modelData.text
                                        font: Tokens.font.body.medium
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        wrapMode: Text.Wrap
                                    }
                                    StyledText {
                                        text: card.modelData.kind === "image" ? "Image • ready to send" : card.modelData.kind === "files" ? "Files" : "Text"
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.label.small
                                    }
                                }

                                Row {
                                    id: actions
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    MiniButton {
                                        icon: "send_to_mobile"; tip: "Send to T2 5G"
                                        onTriggered: Quickshell.execDetached(["caelestia-clipboard", "send", String(card.modelData.id)])
                                    }
                                    MiniButton {
                                        icon: "delete"; tip: "Remove"
                                        onTriggered: Quickshell.execDetached(["caelestia-clipboard", "delete", String(card.modelData.id)])
                                    }
                                }

                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    anchors.rightMargin: 94
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.execDetached(["caelestia-clipboard", "copy", String(card.modelData.id)]);
                                        root.close();
                                    }
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: history.count === 0
                                text: root.query ? "No matching clipboard item" : "Copy something to begin"
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.large
                            }
                        }

                        Column {
                            visible: root.phoneFocus
                            width: parent.width
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                width: parent.width; height: 90; radius: 20
                                color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 0.96)
                                border.width: 1
                                border.color: Colours.layer(Colours.palette.m3primary, 0.5)
                                StyledRect {
                                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                    width: 52; height: 52; radius: 18
                                    color: Colours.palette.m3primaryContainer
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        text: "smartphone"; color: Colours.palette.m3onPrimaryContainer; fontStyle: Tokens.font.icon.large; fill: 1
                                        renderType: Text.NativeRendering
                                    }
                                }
                                Column {
                                    anchors.left: parent.left; anchors.leftMargin: 82; anchors.verticalCenter: parent.verticalCenter
                                    StyledText { text: "T2 5G"; font: Tokens.font.title.large }
                                    StyledText { text: "Connected over Wi-Fi • background protected"; color: Colours.palette.m3primary; font: Tokens.font.label.medium }
                                }
                            }

                            Row {
                                width: parent.width; spacing: Tokens.spacing.medium
                                PhoneAction { width: (parent.width - parent.spacing) / 2; icon: "folder_shared"; title: "Browse phone"; detail: "Open phone storage"; onTriggered: Quickshell.execDetached(["caelestia-continuity", "browse"]) }
                                PhoneAction { width: (parent.width - parent.spacing) / 2; icon: "notifications_active"; title: "Find phone"; detail: "Ring T2 5G"; onTriggered: Quickshell.execDetached(["kdeconnect-cli", "-n", "T2 5G", "--ring"]) }
                            }
                            Row {
                                width: parent.width; spacing: Tokens.spacing.medium
                                PhoneAction { width: (parent.width - parent.spacing) / 2; icon: "sync"; title: "Sync selected paths"; detail: "Runs only configured rules"; onTriggered: Quickshell.execDetached(["caelestia-continuity", "sync"]) }
                                PhoneAction { width: (parent.width - parent.spacing) / 2; icon: "content_paste_go"; title: "Clipboard"; detail: "Screenshots and recent items"; onTriggered: root.phoneFocus = false }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        function open(): void { root.phoneFocus = false; root.opened = true; }
        function openPhone(): void { root.phoneFocus = true; root.opened = true; }
        function close(): void { root.close(); }
        function toggle(): void { root.opened ? root.close() : root.opened = true; }
        target: "clipboard"
    }

    component MiniButton: StyledRect {
        id: button
        required property string icon
        property string tip
        signal triggered()
        width: 38; height: 38; radius: 12
        color: hover.containsMouse ? Colours.palette.m3primaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 1)
        MaterialIcon {
            anchors.centerIn: parent
            text: button.icon
            color: hover.containsMouse ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
            renderType: Text.NativeRendering
        }
        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: button.triggered() }
    }

    component PhoneAction: StyledRect {
        id: action
        required property string icon
        required property string title
        required property string detail
        signal triggered()
        height: 86; radius: 18
        color: actionMouse.containsMouse ? Colours.layer(Colours.palette.m3secondaryContainer, 0.72) : Colours.layer(Colours.palette.m3surfaceContainerHighest, 0.92)
        MaterialIcon {
            anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
            text: action.icon; color: Colours.palette.m3primary; fontStyle: Tokens.font.icon.medium; fill: 1
            renderType: Text.NativeRendering
        }
        Column {
            anchors.left: parent.left; anchors.leftMargin: 60; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            StyledText { width: parent.width; text: action.title; font: Tokens.font.body.medium; elide: Text.ElideRight }
            StyledText { width: parent.width; text: action.detail; color: Colours.palette.m3outline; font: Tokens.font.label.small; elide: Text.ElideRight }
        }
        MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: action.triggered() }
    }
}
