pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

// Native Caelestia clipboard panel (side hover or center detach).
// Click a row to copy the item (image bytes / text). No drag.
Item {
    id: root

    signal closed()
    property bool compact: false
    // Optional PopoutState (hover). Do NOT set sticky=true for search — that
    // trapped the panel open until the center clipboard was toggled.
    property var popouts: null

    property string query: ""
    property list<var> items: []
    property bool dropActive: false
    property int editingId: -1
    property string editDraft: ""
    // Search text *and* image OCR content (item.text on images is OCR).
    readonly property list<var> filtered: items.filter(item => root.matchesQuery(item, root.query))

    implicitWidth: compact ? 390 : 640
    implicitHeight: compact ? 360 : 520
    // Panel can receive Keys (Escape) once layer-shell keyboard is enabled.
    focus: true

    function close(): void {
        query = "";
        editingId = -1;
        if (root.popouts)
            root.popouts.sticky = false;
        // Drop keyboard claim so the next hover is clean.
        if (search.activeFocus)
            root.forceActiveFocus();
        search.focus = false;
        closed();
    }

    // Claim keyboard on the layer-shell (via Wrapper needsKeyboard) and focus search.
    // Stay hover-dismissable: leave/tap outside still closes (no sticky lock).
    function focusSearch(): void {
        root.forceActiveFocus();
        search.forceActiveFocus();
        // Re-assert after the compositor enables OnDemand keyboard interactivity.
        searchFocusTimer.restart();
    }

    Timer {
        id: searchFocusTimer
        interval: 80
        onTriggered: {
            if (search.visible)
                search.forceActiveFocus();
        }
    }

    Keys.onEscapePressed: {
        if (search.activeFocus && search.text.length) {
            search.text = "";
            root.query = "";
            return;
        }
        root.close();
    }

    function isPlaceholder(text: string): bool {
        const t = (text ?? "").trim();
        return !t || t === "Copied image" || t === "Image" || t === "Scanning…";
    }

    // Snippet shown in the list: OCR text for images, body for text items.
    function previewText(item: var): string {
        if (!item)
            return "";
        const raw = String(item.text ?? "").replace(/\s+/g, " ").trim();
        if (item.kind === "image") {
            if (root.isPlaceholder(raw))
                return "";
            return raw;
        }
        return raw;
    }

    // Haystack for search — always includes OCR text when present on images.
    function searchHaystack(item: var): string {
        if (!item)
            return "";
        const text = String(item.text ?? "");
        const path = String(item.path ?? "");
        const base = path.includes("/") ? path.split("/").pop() : path;
        return [
            String(item.kind ?? ""),
            String(item.mime ?? ""),
            text,
            base ?? ""
        ].join("\n").toLowerCase().replace(/\s+/g, " ").trim();
    }

    // Multi-word AND match so "dashboard agents" finds image OCR rows.
    function matchesQuery(item: var, q: string): bool {
        const query = (q ?? "").trim().toLowerCase();
        if (!query)
            return true;
        const hay = root.searchHaystack(item);
        if (!hay)
            return false;
        const tokens = query.split(/\s+/).filter(t => t.length > 0);
        return tokens.every(t => hay.includes(t));
    }

    function previewSnippet(item: var): string {
        const t = root.previewText(item);
        if (item?.kind === "image") {
            if (!t)
                return qsTr("Image");
            return t.length > 90 ? t.slice(0, 90) + "…" : t;
        }
        if (!t)
            return qsTr("(empty)");
        return t.length > 120 ? t.slice(0, 120) + "…" : t;
    }

    function hasOcrText(item: var): bool {
        return item?.kind === "image" && !root.isPlaceholder(String(item.text ?? ""));
    }

    function copyItem(item: var): void {
        if (!item || item.id === undefined || item.id === null)
            return;
        Quickshell.execDetached(["caelestia-clipboard", "copy", String(item.id)]);
        // Always dismiss after copy; side hover animates closed via ClipWrapper.
        root.close();
    }

    function copyOcrText(item: var): void {
        if (!item || item.id === undefined || item.id === null)
            return;
        Quickshell.execDetached(["caelestia-clipboard", "copy-text", String(item.id)]);
    }

    function ensureOcr(item: var): void {
        if (!item || item.kind !== "image" || root.hasOcrText(item))
            return;
        Quickshell.execDetached(["caelestia-clipboard", "ocr", String(item.id)]);
    }

    FileView {
        path: `${Paths.state}/clipboard-history.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.items = JSON.parse(text()); }
            catch (error) { root.items = []; }
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer
        border.width: 1
        border.color: root.dropActive ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

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
                    width: parent.width - (root.compact ? 52 : 144)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    StyledText {
                        text: qsTr("Clipboard")
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.title.medium
                    }
                    StyledText {
                        text: root.dropActive ? qsTr("Drop text, images, or files here") : qsTr("Clipboard history")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }

                MiniButton {
                    visible: !root.compact
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "delete_sweep"
                    iconFill: 1
                    tone: "danger"
                    tooltip: qsTr("Clear history")
                    onTriggered: Quickshell.execDetached(["caelestia-clipboard", "clear"])
                }
                MiniButton {
                    visible: !root.compact
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"
                    tooltip: qsTr("Close")
                    onTriggered: root.close()
                }
            }

            StyledRect {
                width: parent.width
                height: 42
                radius: 14
                color: Colours.tPalette.m3surfaceContainerHigh
                border.width: 1
                border.color: search.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant

                MaterialIcon {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    z: 1
                    text: "search"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                    renderType: Text.NativeRendering
                }
                // Capture clicks on the whole search chrome (including placeholder)
                // and claim keyboard so keys don't pass through to the app below.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    // Let TextInput handle selection/caret when it already has focus.
                    propagateComposedEvents: true
                    onPressed: event => {
                        root.focusSearch();
                        event.accepted = false;
                    }
                }
                TextInput {
                    id: search
                    anchors.left: parent.left
                    anchors.leftMargin: 46
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    z: 2
                    text: root.query
                    color: Colours.palette.m3onSurface
                    selectionColor: Colours.palette.m3primaryContainer
                    font: Tokens.font.body.medium
                    activeFocusOnPress: true
                    focus: false
                    onTextChanged: root.query = text
                    Component.onCompleted: if (!root.compact) root.focusSearch()
                    // TextInput already consumes typed characters once the layer-shell
                    // has keyboard focus — don't re-accept them here (that can block insert).
                    Keys.onEscapePressed: event => {
                        if (text.length) {
                            text = "";
                            root.query = "";
                        } else {
                            root.close();
                        }
                        event.accepted = true;
                    }
                }
                StyledText {
                    anchors.left: search.left
                    anchors.verticalCenter: parent.verticalCenter
                    z: 1
                    visible: !search.text && !search.activeFocus
                    text: qsTr("Search text and image OCR…")
                    color: Colours.palette.m3onSurfaceVariant
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
                    height: modelData.kind === "image" ? (root.compact ? 112 : 132) : (root.editingId === modelData.id ? 104 : 72)
                    radius: 16
                    color: cardMouse.containsMouse ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

                    Component.onCompleted: root.ensureOcr(card.modelData)
                    // Keep OCR warm while browsing / searching so image text is matchable.
                    onModelDataChanged: root.ensureOcr(card.modelData)

                    StyledRect {
                        visible: card.modelData.kind === "image"
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.compact ? 88 : 104
                        height: root.compact ? 88 : 104
                        radius: 13
                        color: Colours.palette.m3surfaceContainerHighest
                        clip: true
                        Image {
                            anchors.fill: parent
                            anchors.margins: 5
                            source: parent.visible ? "file://" + card.modelData.path : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: card.modelData.kind === "image" ? (root.compact ? 110 : 128) : 16
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
                                    // Prefer OCR snippet / real text body — never instructional filler.
                                    text: root.previewSnippet(card.modelData)
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.body.medium
                                    elide: Text.ElideRight
                                    maximumLineCount: card.modelData.kind === "image" ? 3 : 2
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
                                    Keys.onEscapePressed: root.editingId = -1
                                }
                            }
                        }
                        StyledText {
                            visible: card.modelData.kind === "image" && root.hasOcrText(card.modelData)
                            text: qsTr("From image")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }

                    Row {
                        id: actions
                        visible: !root.compact
                        z: 2
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        MiniButton {
                            // Center panel only: copy all OCR text from this image.
                            visible: card.modelData.kind === "image"
                            icon: "article"
                            tooltip: qsTr("Copy OCR text")
                            onTriggered: root.copyOcrText(card.modelData)
                        }
                        MiniButton {
                            icon: card.modelData.pinned ? "keep_off" : "keep"
                            iconFill: card.modelData.pinned ? 1 : 0
                            tooltip: card.modelData.pinned ? qsTr("Unpin") : qsTr("Pin")
                            onTriggered: Quickshell.execDetached(["caelestia-clipboard", "pin", String(card.modelData.id)])
                        }
                        MiniButton {
                            visible: card.modelData.kind === "text"
                            icon: root.editingId === card.modelData.id ? "save" : "edit"
                            tooltip: root.editingId === card.modelData.id ? qsTr("Save") : qsTr("Edit")
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
                            // mobile_share exists in Material Symbols; send_to_mobile does not.
                            icon: "mobile_share"
                            iconFill: 1
                            tone: "accent"
                            tooltip: qsTr("Send to phone")
                            onTriggered: Quickshell.execDetached(["caelestia-clipboard", "send", String(card.modelData.id)])
                        }
                        MiniButton {
                            icon: "delete"
                            iconFill: 1
                            tone: "danger"
                            tooltip: qsTr("Delete")
                            onTriggered: Quickshell.execDetached(["caelestia-clipboard", "delete", String(card.modelData.id)])
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        z: 1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        anchors.rightMargin: root.compact ? 0 : 200
                        onClicked: root.copyItem(card.modelData)
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: history.count === 0
                    text: root.query ? qsTr("No matching clipboard item") : qsTr("Copy something to begin")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.large
                }
            }
        }
    }

    component MiniButton: StyledRect {
        id: button
        required property string icon
        property real iconFill: 0
        // default | accent | danger — soft tint for send / delete
        property string tone: "default"
        property string tooltip: ""
        signal triggered()
        width: 36
        height: 36
        radius: 18
        color: {
            if (!hover.containsMouse)
                return Colours.tPalette.m3surfaceContainerHighest;
            if (button.tone === "danger")
                return Colours.palette.m3errorContainer;
            if (button.tone === "accent")
                return Colours.palette.m3primaryContainer;
            return Colours.palette.m3secondaryContainer;
        }
        border.width: hover.containsMouse ? 0 : 1
        border.color: Colours.palette.m3outlineVariant

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: button.icon
            fill: button.iconFill
            color: {
                if (!hover.containsMouse) {
                    if (button.tone === "danger")
                        return Colours.palette.m3error;
                    if (button.tone === "accent")
                        return Colours.palette.m3primary;
                    return Colours.palette.m3onSurfaceVariant;
                }
                if (button.tone === "danger")
                    return Colours.palette.m3onErrorContainer;
                if (button.tone === "accent")
                    return Colours.palette.m3onPrimaryContainer;
                return Colours.palette.m3onSecondaryContainer;
            }
            fontStyle: Tokens.font.icon.small
            renderType: Text.NativeRendering
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.triggered()
        }
        // Lightweight tooltip for icon-only actions
        StyledRect {
            visible: hover.containsMouse && button.tooltip.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: 6
            z: 20
            radius: 8
            color: Colours.palette.m3inverseSurface
            implicitWidth: tipLabel.implicitWidth + 16
            implicitHeight: tipLabel.implicitHeight + 10
            StyledText {
                id: tipLabel
                anchors.centerIn: parent
                text: button.tooltip
                color: Colours.palette.m3inverseOnSurface
                font: Tokens.font.label.small
            }
        }
    }
}
