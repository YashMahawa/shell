pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property BluetoothDevice device: nState.selectedBtDevice
    readonly property bool connected: device?.state === BluetoothDeviceState.Connected // qmllint disable unresolved-type
    readonly property bool loading: device?.state === BluetoothDeviceState.Connecting || device?.state === BluetoothDeviceState.Disconnecting // qmllint disable unresolved-type
    readonly property var btCard: Audio.getBluetoothCardForDevice(root.device)

    readonly property string statusText: {
        if (!device)
            return "";
        let s = connected ? qsTr("Connected") : (device.bonded ? qsTr("Paired") : qsTr("Not paired"));
        if (connected && device.batteryAvailable)
            s += " • " + Math.round(device.battery * 100) + "%";
        return s;
    }

    onDeviceChanged: {
        // Auto close when device lost
        if (!device)
            nState.closeSubPage();
    }

    title: device?.name ?? qsTr("Device")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Big buttons
        ButtonRow {
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            Layout.minimumWidth: Math.round(root.cappedWidth * 0.7)
            spacing: Tokens.spacing.small

            ButtonBase {
                id: forgetBtn

                fillWidth: true
                shapeMorph: true
                isRound: true

                inactiveColour: Colours.palette.m3errorContainer
                inactiveOnColour: Colours.palette.m3onErrorContainer

                implicitWidth: forgetBtnLayout.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: forgetBtnLayout.implicitHeight + Tokens.padding.medium * 2

                onClicked: {
                    root.device?.forget();
                    root.nState.closeSubPage();
                }

                ColumnLayout {
                    id: forgetBtnLayout

                    anchors.centerIn: parent
                    spacing: 0

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "delete"
                        color: forgetBtn.onColour
                        font: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Forget")
                        color: forgetBtn.onColour
                    }
                }
            }

            ButtonBase {
                id: connectBtn

                fillWidth: true
                shapeMorph: true
                isRound: true

                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                stateLayer.disabled: root.loading

                implicitWidth: connectBtnContent.implicitWidth + Tokens.padding.extraLarge * 2
                implicitHeight: connectBtnContent.implicitHeight + Tokens.padding.medium * 2

                onClicked: root.device.connected = !root.connected

                AnimLoader {
                    id: connectBtnContent

                    anchors.centerIn: parent
                    sourceComp: root.loading ? loadingComp : textComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: loadingComp

                    LoadingIndicator {
                        implicitSize: connectBtn.height - Tokens.padding.large * 2
                    }
                }

                Component {
                    id: textComp

                    ColumnLayout {
                        spacing: 0

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.connected ? "close" : "add"
                            color: connectBtn.inactiveOnColour
                            font: Tokens.font.icon.medium
                            animate: true
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.connected ? qsTr("Disconnect") : qsTr("Connect")
                            color: connectBtn.inactiveOnColour
                            animate: true
                        }
                    }
                }
            }
        }

        // Connection group
        ToggleRow {
            Layout.fillWidth: true
            verticalPadding: Tokens.padding.large
            first: true
            text: qsTr("Trusted")
            subtext: qsTr("Allow this device to connect automatically")
            checked: root.device?.trusted ?? false
            onToggled: {
                if (root.device)
                    root.device.trusted = checked;
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            verticalPadding: Tokens.padding.large
            text: qsTr("Blocked")
            subtext: qsTr("Prevent this device from connecting")
            checked: root.device?.blocked ?? false
            onToggled: {
                if (root.device)
                    root.device.blocked = checked;
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            verticalPadding: Tokens.padding.large
            last: true
            text: qsTr("Wake allowed")
            subtext: qsTr("Allow this device to wake the system")
            checked: root.device?.wakeAllowed ?? false
            onToggled: {
                if (root.device)
                    root.device.wakeAllowed = checked;
            }
        }

        // Audio configuration
        SectionHeader {
            visible: root.connected && !!root.btCard && root.btCard.profileGroups && root.btCard.profileGroups.length > 0
            text: qsTr("Audio configuration")
        }

        Component {
            id: btMenuItemComp

            MenuItem {}
        }

        QtObject {
            id: btMenuHelper

            property var profileItems: []
            property MenuItem activeProfileItem: null

            property var codecItems: []
            property MenuItem activeCodecItem: null

            function refresh() {
                if (!root.btCard || !root.btCard.profileGroups) {
                    profileItems = [];
                    activeProfileItem = null;
                    codecItems = [];
                    activeCodecItem = null;
                    return;
                }

                const pItems = [];
                let aP = null;

                for (const g of root.btCard.profileGroups) {
                    const item = btMenuItemComp.createObject(btMenuHelper, {
                        text: g.name,
                        icon: g.icon || "tune"
                    });
                    item.groupId = g.id;
                    pItems.push(item);
                    if (g.id === root.btCard.activeGroup)
                        aP = item;
                }

                profileItems = pItems;
                activeProfileItem = aP || pItems[0] || null;

                const cItems = [];
                let aC = null;

                const codecs = root.btCard.activeGroupCodecs || [];
                for (const c of codecs) {
                    const item = btMenuItemComp.createObject(btMenuHelper, {
                        text: c.name,
                        icon: "graphic_eq"
                    });
                    item.codecKey = c.key;
                    cItems.push(item);
                    if (c.key === root.btCard.activeProfileKey || c.codecKey === root.btCard.activeCodecKey)
                        aC = item;
                }

                codecItems = cItems;
                activeCodecItem = aC || cItems[0] || null;
            }
        }

        Connections {
            target: Audio
            function onBluetoothCardsChanged() {
                btMenuHelper.refresh();
            }
        }

        Component.onCompleted: btMenuHelper.refresh()

        SelectRow {
            id: btProfileSelect

            Layout.fillWidth: true
            visible: root.connected && !!root.btCard && root.btCard.profileGroups && root.btCard.profileGroups.length > 0
            first: true
            last: !btCodecSelect.visible
            label: qsTr("Profile")
            subtext: qsTr("Audio profile mode")
            fallbackIcon: "tune"
            fallbackText: root.btCard?.activeGroupName || qsTr("Default")
            menuItems: btMenuHelper.profileItems
            active: btMenuHelper.activeProfileItem
            onSelected: item => {
                if (item && item.groupId && root.btCard)
                    Audio.setProfileGroup(root.btCard.cardName, item.groupId);
            }
        }

        SelectRow {
            id: btCodecSelect

            Layout.fillWidth: true
            visible: root.connected && !!root.btCard && btMenuHelper.codecItems.length > 0
            last: true
            label: qsTr("Codec")
            subtext: qsTr("Bluetooth audio codec")
            fallbackIcon: "graphic_eq"
            fallbackText: root.btCard?.activeCodecName || qsTr("Default")
            menuItems: btMenuHelper.codecItems
            active: btMenuHelper.activeCodecItem
            onSelected: item => {
                if (item && item.codecKey && root.btCard)
                    Audio.setCardProfile(root.btCard.cardName, item.codecKey);
            }
        }

        // Information
        ConnectedRect {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            Layout.fillWidth: true
            implicitHeight: batteryLayout.implicitHeight + Tokens.padding.large * 2
            first: true

            ColumnLayout {
                id: batteryLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Battery")
                    }

                    StyledText {
                        text: root.device?.batteryAvailable ? Math.round(root.device.battery * 100) + "%" : qsTr("Unavailable")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: root.device?.batteryAvailable ?? false
                    visible: active
                    asynchronous: true

                    sourceComponent: StyledProgressBar {
                        implicitHeight: Tokens.padding.medium
                        value: root.device.battery
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: addrLayout.implicitHeight + Tokens.padding.large * 2
            last: true

            RowLayout {
                id: addrLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Address")
                }

                StyledText {
                    text: root.device?.address ?? ""
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
