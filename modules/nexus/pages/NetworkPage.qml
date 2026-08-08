pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    signal networkSelected(ap: Nmcli.AccessPoint)

    title: qsTr("Network")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Timer {
            running: root.visible && Nmcli.wifiEnabled
            repeat: true
            triggeredOnStart: true
            interval: GlobalConfig.nexus.networkRescanInterval
            onTriggered: Nmcli.rescanWifi()
        }

        Timer {
            id: wifiScanDelay

            interval: 100
            onTriggered: Nmcli.rescanWifi()
        }

        Connections {
            function onWifiEnabledChanged(): void {
                if (Nmcli.wifiEnabled)
                    wifiScanDelay.start();
            }

            target: Nmcli
        }

        // Ethernet Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: Nmcli.ethernetDevices.length > 0

            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: Nmcli.ethernetDevices.length === 0
                implicitHeight: ethTitleLayout.implicitHeight + ethTitleLayout.anchors.margins * 2

                RowLayout {
                    id: ethTitleLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "settings_ethernet"
                        font: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Ethernet")
                        font: Tokens.font.body.medium
                    }
                }
            }

            Repeater {
                model: Nmcli.ethernetDevices
                delegate: ToggleRow {
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    first: false
                    last: index === Nmcli.ethernetDevices.length - 1
                    text: modelData.connection || modelData.interface
                    subtext: `${modelData.interface} · ${modelData.connected ? qsTr("Connected") : qsTr("Disconnected")}`
                    checked: modelData.connected
                    onClicked: {
                        if (checked) {
                            Nmcli.connectEthernet(modelData.connection, modelData.interface, () => {});
                        } else {
                            Nmcli.disconnect(modelData.interface, () => {
                                Nmcli.getEthernetInterfaces(() => {});
                            });
                        }
                    }
                }
            }
        }

        // VPN Section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: Nmcli.vpnConnections.length > 0

            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: false
                implicitHeight: vpnTitleLayout.implicitHeight + vpnTitleLayout.anchors.margins * 2

                RowLayout {
                    id: vpnTitleLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "vpn_key"
                        font: Tokens.font.icon.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("VPN Profiles")
                        font: Tokens.font.body.medium
                    }
                }
            }

            Repeater {
                model: Nmcli.vpnConnections
                delegate: ToggleRow {
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    first: false
                    last: index === Nmcli.vpnConnections.length - 1
                    text: modelData.name
                    subtext: modelData.type
                    checked: modelData.active
                    onClicked: {
                        if (checked) {
                            Nmcli.connectVpn(modelData.name);
                        } else {
                            Nmcli.disconnectVpn(modelData.name);
                        }
                    }
                }
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Wi-Fi")
            font: Tokens.font.body.medium
            horizontalPadding: Tokens.padding.largeIncreased
            checked: Nmcli.wifiEnabled
            // Avoid changing the hardware radio when status refreshes update
            // the checked binding; only an explicit user click may do that.
            onClicked: Nmcli.enableWifi(checked)
        }

        ItemList {
            id: networkList

            showList: Nmcli.wifiEnabled
            placeholderIcon: Nmcli.wifiEnabled ? "wifi_find" : "signal_wifi_off"
            placeholderText: Nmcli.wifiEnabled ? qsTr("No networks found") : qsTr("Wi-Fi disabled")
            extraHeight: Nmcli.scanning ? Tokens.rounding.extraSmall : 0 // Inline so it isn't affected by anim
            list.anchors.top: scanningIndicator.bottom

            model: ScriptModel {
                values: {
                    // Lower rank sorts higher in the list
                    const rank = n => n.active ? 0 : Nmcli.isWifiOperationPending(n.ssid, n.bssid) ? 1 : Nmcli.hasSavedProfile(n.ssid, n.bssid, n.frequency) ? 2 : 3;
                    // NetworkManager briefly exposes null entries while it
                    // tears Wi-Fi down for suspend. Do not incubate delegates
                    // for objects that have already disappeared.
                    return [...Nmcli.networks].filter(n => n).sort((a, b) => rank(a) - rank(b) || b.strength - a.strength);
                }
            }

            delegate: StateLayer {
                id: network

                required property var modelData
                property bool currentSelected
                property real textOpacity: disabled ? 0.5 : 1
                readonly property bool valid: modelData !== null && modelData !== undefined
                readonly property string ssid: valid ? modelData.ssid : ""
                readonly property string bssid: valid ? modelData.bssid : ""
                readonly property string displayName: valid ? modelData.displayName : ""
                readonly property int strength: valid ? modelData.strength : 0
                readonly property int frequency: valid ? modelData.frequency : 0
                readonly property bool active: valid && modelData.active
                readonly property string security: valid ? modelData.security : ""

                visible: valid
                // Other rows remain clickable so a new selection can cancel
                // and supersede a slow or stuck activation immediately.
                disabled: !valid || Nmcli.isWifiOperationPending(ssid, bssid)

                anchors.left: networkList.list.contentItem.left
                anchors.right: networkList.list.contentItem.right
                implicitHeight: networkLayout.implicitHeight + networkLayout.anchors.margins * 2
                radius: Tokens.rounding.extraSmall
                anchors.fill: undefined

                onClicked: {
                    if (!valid)
                        return;
                    root.nState.selectedWifiSsid = ssid;
                    root.nState.selectedWifiBssid = bssid;
                    root.nState.openSubPage(1);
                }

                Behavior on textOpacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Connections {
                    function onActiveChanged(): void {
                        if (network.active)
                            network.currentSelected = false;
                    }

                    target: network.valid ? network.modelData : null
                }

                Connections {
                    function onNetworkSelected(ap: Nmcli.AccessPoint): void {
                        if (ap !== network.modelData)
                            network.currentSelected = false;
                    }

                    target: root
                }

                RowLayout {
                    id: networkLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large
                    anchors.leftMargin: Tokens.padding.extraLarge
                    anchors.rightMargin: Tokens.padding.extraLarge
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: Icons.getNetworkIcon(network.strength)
                        color: network.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.icon.medium
                        opacity: network.textOpacity
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        opacity: network.textOpacity

                        StyledText {
                            Layout.fillWidth: true
                            text: network.displayName
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("%1% signal • %2%3").arg(network.strength).arg(network.security || qsTr("Open")).arg(Nmcli.hasSavedProfile(network.ssid, network.bssid, network.frequency) ? qsTr(" • Saved") : "")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    AnimLoader {
                        sourceComp: Nmcli.isWifiOperationPending(network.ssid, network.bssid) ? loadingComp : iconComp

                        Component {
                            id: iconComp

                            MaterialIcon {
                                text: network.active || Nmcli.hasSavedProfile(network.ssid, network.bssid, network.frequency) ? "settings" : "chevron_right"
                                color: network.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.icon.medium
                                opacity: network.textOpacity
                            }
                        }

                        Component {
                            id: loadingComp

                            LoadingIndicator {
                                implicitSize: Math.round(Tokens.font.icon.medium.pointSize * 1.3)
                            }
                        }
                    }
                }
            }

            StyledProgressBar {
                id: scanningIndicator

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                implicitHeight: Nmcli.scanning ? Tokens.rounding.extraSmall : 0
                indeterminate: true

                Behavior on implicitHeight {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: addNetworkLayout.implicitHeight + addNetworkLayout.anchors.margins * 2
            last: true

            StateLayer {}

            RowLayout {
                id: addNetworkLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased

                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "add"
                    font: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Add network")
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }
    }
}
