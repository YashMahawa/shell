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
        values: [...root.nodes, ...root.profiles].filter(node => !!node).sort((a, b) => (a.description || a.name || "").localeCompare(b.description || b.name || ""))
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
                        text: device.node?.isSink ? Audio.outputDisplayName(device.node)
                            : (device.modelData?.description || device.modelData?.name || qsTr("Unknown"))
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

                AudioMenuItem {}
            }

            QtObject {
                id: menuHelper

                property var profileItems: []
                property AudioMenuItem activeProfileItem: null

                property var codecItems: []
                property AudioMenuItem activeCodecItem: null

                property var itemCache: ({})

                function clearAll(): void {
                    for (const id in itemCache) {
                        if (itemCache[id])
                            itemCache[id].destroy();
                    }
                    itemCache = ({});
                    profileItems = [];
                    codecItems = [];
                    activeProfileItem = null;
                    activeCodecItem = null;
                }

                function refresh(): void {
                    if (!device.btCard || !device.btCard.profileGroups) {
                        clearAll();
                        return;
                    }

                    const newCache = ({});
                    const pItems = [];
                    let aP = null;

                    for (const g of device.btCard.profileGroups) {
                        const itemId = "profile:" + g.id;
                        let item = itemCache[itemId];
                        if (item) {
                            item.text = g.name;
                            item.icon = g.icon || "tune";
                            item.groupId = g.id;
                        } else {
                            item = menuItemComp.createObject(menuHelper, {
                                text: g.name,
                                icon: g.icon || "tune",
                                groupId: g.id
                            });
                        }
                        if (item) {
                            newCache[itemId] = item;
                            pItems.push(item);
                            if (g.id === device.btCard.activeGroup)
                                aP = item;
                        }
                    }

                    const cItems = [];
                    let aC = null;
                    const codecs = device.btCard.activeGroupCodecs || [];

                    for (const c of codecs) {
                        const itemId = "codec:" + (device.btCard.activeGroup || "") + ":" + c.key;
                        let item = itemCache[itemId];
                        if (item) {
                            item.text = c.name;
                            item.icon = "graphic_eq";
                            item.codecKey = c.key;
                            item.codecShortKey = c.codecKey;
                        } else {
                            item = menuItemComp.createObject(menuHelper, {
                                text: c.name,
                                icon: "graphic_eq",
                                codecKey: c.key,
                                codecShortKey: c.codecKey
                            });
                        }
                        if (item) {
                            newCache[itemId] = item;
                            cItems.push(item);
                            if (c.key === device.btCard.activeProfileKey)
                                aC = item;
                        }
                    }

                    if (!aC && cItems.length > 0 && device.btCard.activeCodecKey) {
                        aC = cItems.find(it => it.codecShortKey === device.btCard.activeCodecKey) || null;
                    }

                    for (const id in itemCache) {
                        if (!newCache[id] && itemCache[id])
                            itemCache[id].destroy();
                    }

                    itemCache = newCache;
                    profileItems = pItems;
                    activeProfileItem = aP || pItems[0] || null;
                    codecItems = cItems;
                    activeCodecItem = aC || cItems[0] || null;
                }
            }

            Component.onDestruction: menuHelper.clearAll()

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
