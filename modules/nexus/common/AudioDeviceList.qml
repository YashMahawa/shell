pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ItemList {
    id: root

    property var nodes: []
    property var profiles: []
    property int currentId: -1
    property string iconName: "speaker"

    signal selected(node: PwNode)
    signal profileSelected(var profile)

    last: true
    showList: true

    model: ScriptModel {
        values: [...root.nodes, ...root.profiles].sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""))
    }

    delegate: ColumnLayout {
        id: device

        required property var modelData
        required property int index

        readonly property PwNode node: device.modelData?.isProfile ? null : device.modelData
        readonly property bool isBt: Audio.isBluetoothSink(device.node)
        readonly property var btCard: device.isBt ? Audio.getBluetoothCardForNode(device.node) : null
        readonly property bool active: !device.modelData?.isProfile && device.modelData?.id === root.currentId

        anchors.left: root.list.contentItem.left
        anchors.right: root.list.contentItem.right
        spacing: 0

        Item {
            id: mainRowItem

            Layout.fillWidth: true
            implicitHeight: deviceLayout.implicitHeight + deviceLayout.anchors.margins * 2

            StateLayer {
                radius: Tokens.rounding.extraSmall
                bottomLeftRadius: (device.index === root?.list.count - 1 && (!btConfigSection.visible || !btConfigSection.expanded)) ? Tokens.rounding.extraLarge : radius
                bottomRightRadius: (device.index === root?.list.count - 1 && (!btConfigSection.visible || !btConfigSection.expanded)) ? Tokens.rounding.extraLarge : radius
                onClicked: {
                    if (device.modelData?.isProfile)
                        root.profileSelected(device.modelData);
                    else
                        root.selected(device.modelData);
                }
            }

            RowLayout {
                id: deviceLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: devIcon.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: device.active ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        id: devIcon

                        anchors.centerIn: parent
                        text: device.isBt ? Icons.getBluetoothIcon(device.node?.properties?.["device.icon_name"] ?? "headset") : root.iconName
                        color: device.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                        font: Tokens.font.icon.medium
                        fill: device.active ? 1 : 0

                        Behavior on fill {
                            Anim {}
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: device.modelData?.description || device.modelData?.name || qsTr("Unknown")
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: device.isBt && !!device.btCard
                        text: device.btCard ? `${device.btCard.activeGroupName}${device.btCard.activeCodecName ? " • " + device.btCard.activeCodecName : ""}` : ""
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        elide: Text.ElideRight
                    }
                }

                MaterialIcon {
                    text: "check"
                    color: Colours.palette.m3primary
                    font: Tokens.font.icon.medium
                    opacity: device.active ? 1 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }
        }

        CollapsibleSection {
            id: btConfigSection

            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.large
            Layout.rightMargin: Tokens.padding.large
            Layout.bottomMargin: Tokens.spacing.small

            visible: device.isBt && !!device.btCard && device.btCard.profileGroups && device.btCard.profileGroups.length > 0
            title: qsTr("Profile & Codec")
            expanded: device.active

            Component {
                id: menuItemComp

                MenuItem {}
            }

            QtObject {
                id: menuHelper

                property var profileItems: []
                property MenuItem activeProfileItem: null

                property var codecItems: []
                property MenuItem activeCodecItem: null

                function refresh() {
                    if (!device.btCard || !device.btCard.profileGroups) {
                        profileItems = [];
                        activeProfileItem = null;
                        codecItems = [];
                        activeCodecItem = null;
                        return;
                    }

                    const pItems = [];
                    let aP = null;

                    for (const g of device.btCard.profileGroups) {
                        const item = menuItemComp.createObject(menuHelper, {
                            text: g.name,
                            icon: g.icon || "tune"
                        });
                        item.groupId = g.id;
                        pItems.push(item);
                        if (g.id === device.btCard.activeGroup)
                            aP = item;
                    }

                    profileItems = pItems;
                    activeProfileItem = aP || pItems[0] || null;

                    const cItems = [];
                    let aC = null;

                    const codecs = device.btCard.activeGroupCodecs || [];
                    for (const c of codecs) {
                        const item = menuItemComp.createObject(menuHelper, {
                            text: c.name,
                            icon: "graphic_eq"
                        });
                        item.codecKey = c.key;
                        cItems.push(item);
                        if (c.key === device.btCard.activeProfileKey || c.codecKey === device.btCard.activeCodecKey)
                            aC = item;
                    }

                    codecItems = cItems;
                    activeCodecItem = aC || cItems[0] || null;
                }
            }

            Connections {
                target: Audio
                function onBluetoothCardsChanged() {
                    menuHelper.refresh();
                }
            }

            Component.onCompleted: menuHelper.refresh()

            SelectRow {
                id: profileSelect

                Layout.fillWidth: true
                first: true
                label: qsTr("Profile")
                subtext: qsTr("Audio profile mode")
                fallbackIcon: "tune"
                fallbackText: device.btCard?.activeGroupName || qsTr("Default")
                menuItems: menuHelper.profileItems
                active: menuHelper.activeProfileItem
                onSelected: item => {
                    if (item && item.groupId && device.btCard)
                        Audio.setProfileGroup(device.btCard.cardName, item.groupId);
                }
            }

            SelectRow {
                id: codecSelect

                Layout.fillWidth: true
                last: true
                visible: menuHelper.codecItems.length > 0
                label: qsTr("Codec")
                subtext: qsTr("Bluetooth audio codec")
                fallbackIcon: "graphic_eq"
                fallbackText: device.btCard?.activeCodecName || qsTr("Default")
                menuItems: menuHelper.codecItems
                active: menuHelper.activeCodecItem
                onSelected: item => {
                    if (item && item.codecKey && device.btCard)
                        Audio.setCardProfile(device.btCard.cardName, item.codecKey);
                }
            }
        }
    }
}
