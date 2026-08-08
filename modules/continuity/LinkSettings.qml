pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

StyledClippingRect {
    id: root

    property string initialPage: "overview"
    property int currentPage: Math.max(0, ["overview", "devices", "commands", "features", "sharing", "connection"].indexOf(initialPage))
    property var statusData: ({})
    property var commandData: []
    property var pluginData: []
    property var deviceData: []
    property string editingId: ""
    property string pendingUnpairId: ""
    signal closeRequested()

    readonly property var pages: [
        { key: "overview", title: "Overview", subtitle: "Device and quick actions", icon: "devices" },
        { key: "devices", title: "Devices", subtitle: "Pair, choose or disconnect", icon: "devices_other" },
        { key: "commands", title: "Remote commands", subtitle: "Commands available on your phone", icon: "terminal" },
        { key: "features", title: "Features", subtitle: "Phone and laptop integrations", icon: "extension" },
        { key: "sharing", title: "Sharing & privacy", subtitle: "Clipboard and notifications", icon: "share" },
        { key: "connection", title: "Connection", subtitle: "Transport and security", icon: "lan" }
    ]

    function refresh(): void {
        if (!statusProc.running)
            statusProc.running = true;
        if (!commandsProc.running)
            commandsProc.running = true;
        if (!pluginsProc.running)
            pluginsProc.running = true;
        if (!devicesProc.running)
            devicesProc.running = true;
    }

    function runAction(command: list<string>): void {
        if (actionProc.running)
            return;
        actionProc.command = command;
        actionProc.running = true;
    }

    function saveCommand(): void {
        if (!commandField.text.trim())
            return;
        runAction(editingId
            ? ["caelestia-continuity", "command-update", editingId, nameField.text, commandField.text]
            : ["caelestia-continuity", "command-add", nameField.text, commandField.text]);
        editingId = "";
        nameField.text = "";
        commandField.text = "";
    }

    implicitWidth: 1040
    implicitHeight: 720
    width: implicitWidth
    height: implicitHeight
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer
    border.width: 1
    border.color: Colours.palette.m3outlineVariant

    Component.onCompleted: refresh()
    onInitialPageChanged: currentPage = Math.max(0, ["overview", "devices", "commands", "features", "sharing", "connection"].indexOf(initialPage))

    Process {
        id: statusProc
        command: ["caelestia-continuity", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.statusData = JSON.parse(text); } catch (error) { root.statusData = {}; }
            }
        }
    }

    Process {
        id: commandsProc
        command: ["caelestia-continuity", "commands"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.commandData = JSON.parse(text); } catch (error) { root.commandData = []; }
            }
        }
    }

    Process {
        id: pluginsProc
        command: ["caelestia-continuity", "plugins"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.pluginData = JSON.parse(text); } catch (error) { root.pluginData = []; }
            }
        }
    }

    Process {
        id: devicesProc
        command: ["caelestia-continuity", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.deviceData = JSON.parse(text); } catch (error) { root.deviceData = []; }
            }
        }
    }

    Process {
        id: actionProc
        onExited: Qt.callLater(root.refresh)
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainerHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium
                    StyledRect {
                        implicitWidth: 46; implicitHeight: 46
                        radius: 16
                        color: Colours.palette.m3primaryContainer
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "hub"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: "Caelestia Link"; font: Tokens.font.title.medium; color: Colours.palette.m3onSurface }
                        StyledText {
                            text: root.statusData.reachable ? "Connected" : "Offline"
                            font: Tokens.font.label.medium
                            color: root.statusData.reachable ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                Repeater {
                    model: root.pages
                    delegate: StyledRect {
                        id: nav
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 66
                        radius: Tokens.rounding.large
                        color: index === root.currentPage ? Colours.palette.m3secondaryContainer : "transparent"
                        StateLayer {
                            onClicked: root.currentPage = nav.index
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            spacing: Tokens.spacing.medium
                            MaterialIcon {
                                text: nav.modelData.icon
                                color: nav.index === root.currentPage ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.medium
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { text: nav.modelData.title; font: Tokens.font.body.medium; color: Colours.palette.m3onSurface }
                                StyledText { text: nav.modelData.subtitle; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                StyledText {
                    Layout.fillWidth: true
                    text: "Encrypted local transport\nNo cloud relay"
                    horizontalAlignment: Text.AlignHCenter
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Tokens.padding.medium
                    StyledText {
                        Layout.fillWidth: true
                        text: root.pages[root.currentPage].title
                        font: Tokens.font.headline.small
                        color: Colours.palette.m3onSurface
                    }
                    Item {
                        implicitWidth: 42; implicitHeight: 42
                        StateLayer {
                            radius: Tokens.rounding.full
                            onClicked: root.closeRequested()
                        }
                        MaterialIcon { anchors.centerIn: parent; text: "close"; color: Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
                    }
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.currentPage

                    Flickable {
                        contentHeight: overview.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ColumnLayout {
                            id: overview
                            width: parent.width
                            spacing: Tokens.spacing.medium
                            InfoCard {
                                title: root.statusData.deviceName ?? "Phone"
                                detail: root.statusData.reachable ? `Connected over ${root.statusData.transportLabel ?? "local network"}` : "Not currently reachable"
                                icon: root.statusData.reachable ? "phone_in_talk" : "phone_disabled"
                                accent: root.statusData.reachable ?? false
                            }
                            SectionTitle { text: "Quick actions" }
                            RowLayout {
                                Layout.fillWidth: true
                                ActionButton { Layout.fillWidth: true; icon: "content_paste_go"; text: "Send clipboard"; onClicked: root.runAction(["caelestia-clipboard", "send-latest"]) }
                                ActionButton { Layout.fillWidth: true; icon: "notifications_active"; text: "Find phone"; onClicked: root.runAction(["caelestia-continuity", "ring"]) }
                                ActionButton { Layout.fillWidth: true; icon: "sync"; text: "Reconnect"; onClicked: root.runAction(["caelestia-continuity", "reconnect"]) }
                            }
                            SectionTitle { text: "Capabilities" }
                            InfoCard { title: "Clipboard sharing"; detail: "Send text, images and files securely to the paired phone"; icon: "content_paste"; accent: true; actionable: true; onClicked: root.currentPage = 4 }
                            InfoCard { title: "Remote commands"; detail: `${root.commandData.length} commands are available from the phone`; icon: "terminal"; accent: root.commandData.length > 0; actionable: true; onClicked: root.currentPage = 2 }
                            InfoCard { title: "Files and links"; detail: "Share files, URLs and selected text between devices"; icon: "folder_shared"; accent: true; actionable: true; onClicked: root.currentPage = 3 }
                            InfoCard { title: "Remote input"; detail: "Use the phone as a touchpad, keyboard or presentation remote"; icon: "touch_app"; accent: true; actionable: true; onClicked: root.currentPage = 3 }
                            InfoCard { title: "Phone notifications"; detail: root.statusData.notificationsEnabled ? "Mirrored to this laptop" : "Kept private on the phone"; icon: "notifications"; accent: root.statusData.notificationsEnabled ?? false; actionable: true; onClicked: root.currentPage = 4 }
                        }
                    }

                    Flickable {
                        contentHeight: devicesColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: devicesColumn
                            width: parent.width
                            spacing: Tokens.spacing.small

                            SectionTitle { text: "Nearby and remembered devices" }
                            Repeater {
                                model: ScriptModel { values: root.deviceData }
                                delegate: StyledRect {
                                    id: deviceRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 92
                                    radius: Tokens.rounding.large
                                    color: Colours.tPalette.m3surfaceContainerHigh
                                    border.width: modelData.selected ? 1 : 0
                                    border.color: Colours.palette.m3primary

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.medium
                                        spacing: Tokens.spacing.medium
                                        MaterialIcon {
                                            text: deviceRow.modelData.type === "desktop" ? "computer" : "smartphone"
                                            color: deviceRow.modelData.reachable ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                            fontStyle: Tokens.font.icon.medium
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            StyledText { text: deviceRow.modelData.name; font: Tokens.font.body.medium; color: Colours.palette.m3onSurface }
                                            StyledText {
                                                text: deviceRow.modelData.selected ? "Current device"
                                                    : deviceRow.modelData.paired ? (deviceRow.modelData.reachable ? "Paired · available" : "Paired · offline")
                                                    : (deviceRow.modelData.reachable ? "Available to pair" : "Unavailable")
                                                font: Tokens.font.label.small
                                                color: deviceRow.modelData.reachable ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                            }
                                        }
                                        ActionButton {
                                            text: deviceRow.modelData.paired ? (deviceRow.modelData.selected ? "Current" : "Use") : "Pair"
                                            icon: deviceRow.modelData.paired ? (deviceRow.modelData.selected ? "check" : "sync_alt") : "link"
                                            disabled: deviceRow.modelData.selected || (!deviceRow.modelData.paired && !deviceRow.modelData.reachable)
                                            onClicked: root.runAction([
                                                "caelestia-continuity",
                                                deviceRow.modelData.paired ? "select-device" : "pair-device",
                                                deviceRow.modelData.id
                                            ])
                                        }
                                        ActionButton {
                                            visible: deviceRow.modelData.paired
                                            danger: true
                                            text: root.pendingUnpairId === deviceRow.modelData.id ? "Confirm" : "Disconnect"
                                            icon: root.pendingUnpairId === deviceRow.modelData.id ? "warning" : "link_off"
                                            onClicked: {
                                                if (root.pendingUnpairId === deviceRow.modelData.id) {
                                                    root.pendingUnpairId = "";
                                                    root.runAction(["caelestia-continuity", "unpair-device", deviceRow.modelData.id]);
                                                } else {
                                                    root.pendingUnpairId = deviceRow.modelData.id;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Tokens.spacing.medium
                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: Tokens.spacing.small
                                model: ScriptModel { values: root.commandData }
                                delegate: StyledRect {
                                    id: commandRow
                                    required property var modelData
                                    width: ListView.view.width
                                    implicitHeight: 72
                                    radius: Tokens.rounding.large
                                    color: Colours.tPalette.m3surfaceContainerHigh
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.padding.medium
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            StyledText { text: commandRow.modelData.name; font: Tokens.font.body.medium; color: Colours.palette.m3onSurface }
                                            StyledText { Layout.fillWidth: true; text: commandRow.modelData.command; elide: Text.ElideMiddle; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant }
                                        }
                                        MiniAction { icon: "edit"; onClicked: { root.editingId = commandRow.modelData.id; nameField.text = commandRow.modelData.name; commandField.text = commandRow.modelData.command; } }
                                        MiniAction { icon: "delete"; danger: true; onClicked: root.runAction(["caelestia-continuity", "command-remove", commandRow.modelData.id]) }
                                    }
                                }
                            }
                            StyledRect {
                                Layout.fillWidth: true
                                implicitHeight: editor.implicitHeight + Tokens.padding.medium * 2
                                radius: Tokens.rounding.large
                                color: Colours.tPalette.m3surfaceContainerHigh
                                ColumnLayout {
                                    id: editor
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Tokens.padding.medium
                                    StyledText { text: root.editingId ? "Edit command" : "Add command"; font: Tokens.font.title.small; color: Colours.palette.m3onSurface }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        LinkField { id: nameField; Layout.preferredWidth: 210; placeholderText: "Name" }
                                        LinkField { id: commandField; Layout.fillWidth: true; placeholderText: "Shell command"; onAccepted: root.saveCommand() }
                                        ActionButton { icon: root.editingId ? "save" : "add"; text: root.editingId ? "Save" : "Add"; onClicked: root.saveCommand() }
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        contentHeight: featuresColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: featuresColumn
                            width: parent.width
                            spacing: Tokens.spacing.small

                            Repeater {
                                model: ScriptModel { values: root.pluginData }
                                delegate: ToggleCard {
                                    required property var modelData
                                    title: modelData.name
                                    detail: modelData.detail
                                    icon: modelData.icon
                                    checked: modelData.enabled
                                    onClicked: root.runAction([
                                        "caelestia-continuity", "plugin", modelData.id,
                                        checked ? "off" : "on"
                                    ])
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: Tokens.spacing.medium
                        SectionTitle { text: "Privacy controls" }
                        ToggleCard {
                            title: "Phone notifications"
                            detail: checked ? "Notifications appear in Caelestia" : "Notifications remain private on the phone"
                            icon: "notifications"
                            checked: root.statusData.notificationsEnabled ?? false
                            onClicked: root.runAction(["caelestia-continuity", "notifications", checked ? "off" : "on"])
                        }
                        ToggleCard {
                            title: "Automatic clipboard sync"
                            detail: checked ? "Clipboard changes mirror automatically" : "Clipboard is shared only when you choose Send"
                            icon: "sync_alt"
                            checked: root.statusData.autoClipboardSync ?? false
                            onClicked: root.runAction(["caelestia-continuity", "auto-clipboard", checked ? "off" : "on"])
                        }
                        InfoCard { title: "Files and links"; detail: "Incoming shares use the system portal and remain local to your devices"; icon: "folder_shared"; accent: true }
                        InfoCard { title: "Remote input"; detail: "Touchpad, keyboard and presentation controls require an explicitly paired device"; icon: "touch_app"; accent: true }
                        Item { Layout.fillHeight: true }
                    }

                    ColumnLayout {
                        spacing: Tokens.spacing.medium
                        InfoCard { title: "Transport"; detail: root.statusData.transportLabel ?? "Disconnected"; icon: "lan"; accent: root.statusData.reachable ?? false }
                        InfoCard { title: "Device identity"; detail: root.statusData.deviceId ?? "No paired device"; icon: "fingerprint"; accent: false }
                        InfoCard { title: "Network addresses"; detail: (root.statusData.addresses ?? []).join("\n") || "No live address"; icon: "router"; accent: false }
                        InfoCard { title: "Security"; detail: "Pairing identity and traffic encryption are provided by the KDE Connect protocol; Caelestia owns the desktop UI."; icon: "encrypted"; accent: true }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    component SectionTitle: StyledText {
        Layout.fillWidth: true
        font: Tokens.font.title.small
        color: Colours.palette.m3onSurfaceVariant
    }

    component InfoCard: StyledRect {
        id: card
        required property string title
        required property string detail
        required property string icon
        property bool accent: false
        property bool actionable: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 86
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh
        border.width: accent ? 1 : 0
        border.color: Colours.palette.m3primary
        StateLayer { disabled: !card.actionable; onClicked: card.clicked() }
        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium
            StyledRect {
                implicitWidth: 46; implicitHeight: 46; radius: 15
                color: card.accent ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
                MaterialIcon { anchors.centerIn: parent; text: card.icon; color: card.accent ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.medium }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText { text: card.title; font: Tokens.font.body.medium; color: Colours.palette.m3onSurface }
                StyledText { Layout.fillWidth: true; text: card.detail; wrapMode: Text.Wrap; font: Tokens.font.label.medium; color: Colours.palette.m3onSurfaceVariant }
            }
            MaterialIcon {
                visible: card.actionable
                text: "chevron_right"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }

    component ActionButton: StyledRect {
        id: button
        required property string icon
        required property string text
        signal clicked()
        property bool danger: false
        property bool disabled: false
        implicitWidth: buttonContent.implicitWidth + Tokens.padding.large * 2
        implicitHeight: 48
        radius: Tokens.rounding.full
        color: button.danger ? Colours.palette.m3errorContainer : Colours.palette.m3secondaryContainer
        opacity: button.disabled ? 0.5 : 1
        StateLayer { disabled: button.disabled; onClicked: button.clicked() }
        Row {
            id: buttonContent
            anchors.centerIn: parent
            spacing: 7
            MaterialIcon { text: button.icon; color: button.danger ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSecondaryContainer; fontStyle: Tokens.font.icon.small }
            StyledText { text: button.text; color: button.danger ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSecondaryContainer; font: Tokens.font.label.medium }
        }
    }

    component MiniAction: Item {
        id: mini
        required property string icon
        property bool danger: false
        signal clicked()
        implicitWidth: 38; implicitHeight: 38
        StateLayer { radius: Tokens.rounding.full; onClicked: mini.clicked() }
        MaterialIcon { anchors.centerIn: parent; text: mini.icon; color: mini.danger ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.small }
    }

    component LinkField: TextField {
        color: Colours.palette.m3onSurface
        placeholderTextColor: Colours.palette.m3onSurfaceVariant
        selectionColor: Colours.palette.m3primary
        selectedTextColor: Colours.palette.m3onPrimary
        font: Tokens.font.body.medium
        padding: Tokens.padding.medium
        background: StyledRect { radius: Tokens.rounding.medium; color: Colours.palette.m3surfaceContainerHighest; border.width: 1; border.color: parent.activeFocus ? Colours.palette.m3primary : Colours.palette.m3outlineVariant }
    }

    component ToggleCard: StyledRect {
        id: toggle
        required property string title
        required property string detail
        required property string icon
        required property bool checked
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 78
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh
        StateLayer { onClicked: toggle.clicked() }
        RowLayout {
            anchors.fill: parent; anchors.margins: Tokens.padding.large; spacing: Tokens.spacing.medium
            MaterialIcon { text: toggle.icon; color: toggle.checked ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant; fontStyle: Tokens.font.icon.medium }
            ColumnLayout { Layout.fillWidth: true; spacing: 1; StyledText { text: toggle.title; font: Tokens.font.body.medium; color: Colours.palette.m3onSurface } StyledText { Layout.fillWidth: true; text: toggle.detail; elide: Text.ElideRight; font: Tokens.font.label.medium; color: Colours.palette.m3onSurfaceVariant } }
            StyledRect {
                implicitWidth: 48; implicitHeight: 28; radius: 14
                color: toggle.checked ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest
                border.width: toggle.checked ? 0 : 1; border.color: Colours.palette.m3outline
                StyledRect { width: 20; height: 20; radius: 10; y: 4; x: toggle.checked ? parent.width - width - 4 : 4; color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant; Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } }
            }
        }
    }
}
