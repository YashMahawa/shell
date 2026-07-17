pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

Scope {
    id: root

    property bool opened: false
    property string query: ""
    property list<var> items: []
    property bool dropActive: false
    property int editingId: -1
    property string editDraft: ""
    readonly property list<var> filtered: items.filter(item => !query || (item.text ?? "").toLowerCase().includes(query.toLowerCase()))

    function close(): void {
        opened = false;
        query = "";
        editingId = -1;
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

        FloatingWindow {
            id: window
            required property ShellScreen modelData
            readonly property bool targetScreen: (Hypr.focusedMonitor?.name ?? modelData.name) === modelData.name

            screen: modelData
            visible: root.opened && targetScreen
            implicitWidth: 700
            implicitHeight: 580
            minimumSize.width: 560
            minimumSize.height: 420
            color: "transparent"
            title: qsTr("Clipboard")
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
                    border.color: root.dropActive ? Colours.palette.m3primary : Colours.layer(Colours.palette.m3primary, 0.38)

                    DropArea {
                        anchors.fill: parent
                        onEntered: event => { root.dropActive = true; event.acceptProposedAction(); }
                        onExited: root.dropActive = false
                        onDropped: event => {
                            const urls = event.urls ?? [];
                            if (urls.length) {
                                for (const url of urls)
                                    Quickshell.execDetached(["caelestia-clipboard", "add-path", String(url)]);
                            } else if ((event.text ?? "").length) {
                                Quickshell.execDetached(["wl-copy", String(event.text)]);
                            }
                            root.dropActive = false;
                            event.acceptProposedAction();
                        }
                    }

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
                                    text: "content_paste_search"
                                    color: Colours.palette.m3onPrimaryContainer
                                    fontStyle: Tokens.font.icon.medium
                                    renderType: Text.NativeRendering
                                }
                            }

                            Column {
                                width: parent.width - 144
                                StyledText { text: "Clipboard"; font: Tokens.font.title.medium }
                                StyledText {
                                    text: root.dropActive ? "Drop text, images, or files here" : "Search • pin • edit • drag • explicitly share"
                                    color: Colours.palette.m3outline
                                    font: Tokens.font.label.small
                                }
                            }

                            MiniButton { icon: "delete_sweep"; tip: "Clear history"; onTriggered: Quickshell.execDetached(["caelestia-clipboard", "clear"]) }
                            MiniButton { icon: "close"; tip: "Close"; onTriggered: root.close() }
                        }

                        StyledRect {
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
                            height: parent.height - 118
                            clip: true
                            spacing: Tokens.spacing.small
                            model: root.filtered

                            delegate: StyledRect {
                                id: card
                                required property var modelData
                                width: history.width
                                height: modelData.kind === "image" ? 124 : (root.editingId === modelData.id ? 104 : 72)
                                radius: 16
                                color: dragHover.hovered ? Colours.layer(Colours.palette.m3secondaryContainer, 0.52) : Colours.layer(Colours.palette.m3surfaceContainer, 0.9)

                                StyledRect {
                                    visible: card.modelData.kind === "image"
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 104; height: 104; radius: 13
                                    color: Colours.layer(Colours.palette.m3surface, 0.96)
                                    clip: true
                                    Image {
                                        id: thumbnailImage
                                        anchors.fill: parent; anchors.margins: 5
                                        source: parent.visible ? "file://" + card.modelData.path : ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                    }
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: card.modelData.kind === "image" ? 128 : 16
                                    anchors.right: actions.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 3
                                    Loader {
                                        width: parent.width
                                        sourceComponent: root.editingId === card.modelData.id ? editor : label
                                        Component {
                                            id: label
                                            StyledText {
                                                text: card.modelData.kind === "image" ? card.modelData.text : card.modelData.text
                                                font: Tokens.font.body.medium
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                        Component {
                                            id: editor
                                            TextInput {
                                                text: root.editDraft
                                                color: Colours.palette.m3onSurface
                                                selectionColor: Colours.palette.m3primaryContainer
                                                font: Tokens.font.body.medium
                                                onTextChanged: root.editDraft = text
                                                Component.onCompleted: forceActiveFocus()
                                                Keys.onReturnPressed: {
                                                    Quickshell.execDetached(["caelestia-clipboard", "edit", String(card.modelData.id), root.editDraft]);
                                                    root.editingId = -1;
                                                }
                                            }
                                        }
                                    }
                                    StyledText {
                                        text: `${card.modelData.pinned ? "Pinned • " : ""}${card.modelData.kind === "image" ? "Image" : card.modelData.kind === "files" ? "Files" : "Text"} • hold and drag into any app`
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
                                        icon: card.modelData.pinned ? "keep_off" : "keep"; tip: card.modelData.pinned ? "Unpin" : "Pin"
                                        onTriggered: Quickshell.execDetached(["caelestia-clipboard", "pin", String(card.modelData.id)])
                                    }
                                    MiniButton {
                                        visible: card.modelData.kind === "text"
                                        icon: root.editingId === card.modelData.id ? "save" : "edit"; tip: "Edit text"
                                        onTriggered: {
                                            if (root.editingId === card.modelData.id) {
                                                Quickshell.execDetached(["caelestia-clipboard", "edit", String(card.modelData.id), root.editDraft]);
                                                root.editingId = -1;
                                            } else {
                                                root.editDraft = card.modelData.text;
                                                root.editingId = card.modelData.id;
                                            }
                                        }
                                    }
                                    MiniButton {
                                        icon: "send_to_mobile"; tip: "Send to phone"
                                        onTriggered: Quickshell.execDetached(["caelestia-clipboard", "send", String(card.modelData.id)])
                                    }
                                    MiniButton {
                                        icon: "delete"; tip: "Remove"
                                        onTriggered: Quickshell.execDetached(["caelestia-clipboard", "delete", String(card.modelData.id)])
                                    }
                                }

                                Item {
                                    id: dragZone
                                    anchors.fill: parent
                                    anchors.rightMargin: card.modelData.kind === "text" ? 182 : 138

                                    HoverHandler {
                                        id: dragHover
                                        cursorShape: dragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    }

                                    TapHandler {
                                        onTapped: {
                                            Quickshell.execDetached(["caelestia-clipboard", "copy", String(card.modelData.id)]);
                                            root.close();
                                        }
                                    }

                                    DragHandler {
                                        id: dragHandler
                                        target: null
                                        dragThreshold: 6
                                        onActiveChanged: {
                                            if (!active) {
                                                card.Drag.active = false;
                                                DropShare.active = false;
                                                return;
                                            }
                                            DropShare.active = true;
                                            const payload = card.modelData.kind === "image" ? thumbnailImage : dragPayloadPreview;
                                            payload.grabToImage(result => {
                                                if (!dragHandler.active)
                                                    return;
                                                card.Drag.imageSource = result.url;
                                                card.Drag.active = true;
                                            });
                                        }
                                    }
                                }

                                Drag.dragType: Drag.Automatic
                                Drag.supportedActions: Qt.CopyAction
                                Drag.mimeData: card.modelData.kind === "image" ? { "text/uri-list": `file://${card.modelData.path}` } : { "text/plain": card.modelData.text }
                                Drag.hotSpot.x: card.modelData.kind === "image" ? 47 : 20
                                Drag.hotSpot.y: card.modelData.kind === "image" ? 47 : 20

                                StyledRect {
                                    id: dragPayloadPreview
                                    z: 20
                                    visible: dragHandler.active && card.modelData.kind !== "image"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(320, card.width - actions.width - 38)
                                    height: 56
                                    radius: 14
                                    color: Colours.palette.m3primary

                                    Row {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 9
                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: card.modelData.kind === "files" ? "draft" : "notes"
                                            color: Colours.palette.m3onPrimary
                                            fontStyle: Tokens.font.icon.small
                                            renderType: Text.NativeRendering
                                        }
                                        StyledText {
                                            width: parent.width - 34
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: card.modelData.text
                                            color: Colours.palette.m3onPrimary
                                            font: Tokens.font.body.small
                                            maximumLineCount: 2
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideRight
                                        }
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

                    }
                }
            }
        }
    }

    IpcHandler {
        function open(): void { root.opened = true; }
        function openPhone(): void { root.opened = true; }
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
