pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var network: Nmcli.networks.find(n => n.bssid.toUpperCase() === nState.selectedWifiBssid.toUpperCase())
        ?? Nmcli.networks.find(n => n.ssid === nState.selectedWifiSsid)
        ?? null
    readonly property string ssid: nState.selectedWifiSsid
    readonly property bool connected: Nmcli.wifiConnected && (Nmcli.active?.bssid.toUpperCase() === nState.selectedWifiBssid.toUpperCase() || (!nState.selectedWifiBssid && Nmcli.active?.ssid === ssid))
    readonly property bool saved: Nmcli.hasSavedProfile(ssid, root.network?.bssid || "", root.network?.frequency || 0)
    property bool busy
    property bool showPassword
    property string resultText
    property bool resultError

    title: ssid || qsTr("Wi-Fi network")
    isSubPage: true

    function finish(result): void {
        root.busy = false;
        root.resultError = !result?.success;
        root.resultText = result?.success
            ? qsTr("Connection updated")
            : (result?.error || qsTr("The operation failed"));
        Nmcli.refreshLiveWifiState();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: statusColumn.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: statusColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true

                    MaterialIcon {
                        text: root.network ? Icons.getNetworkIcon(root.network.strength) : "signal_wifi_off"
                        color: root.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.icon.large
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: root.connected ? qsTr("Connected") : (root.saved ? qsTr("Saved") : qsTr("Available"))
                            font: Tokens.font.body.medium
                        }

                        StyledText {
                            text: root.network ? qsTr("%1% signal").arg(root.network.strength) : qsTr("Currently out of range")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }
                    }
                }

                StyledText {
                    text: root.network
                        ? qsTr("%1 GHz • %2 • %3").arg(root.network.frequency >= 5000 ? "5" : "2.4").arg(root.network.security || qsTr("Open")).arg(root.network.bssid)
                        : qsTr("Saved NetworkManager profile")
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
        }

        SectionHeader {
            Layout.topMargin: Tokens.spacing.large
            text: root.saved ? qsTr("Update password") : qsTr("Password")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: passwordColumn.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: passwordColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Tokens.rounding.large
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                    StyledTextField {
                        id: passwordField

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                        placeholderText: root.saved ? qsTr("Leave blank to use saved password") : qsTr("Enter network password")
                    }
                }

                TextButton {
                    text: root.showPassword ? qsTr("Hide password") : qsTr("Show password")
                    onClicked: root.showPassword = !root.showPassword
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: root.connected ? qsTr("Reconnect") : qsTr("Connect")
                        enabled: !root.busy && (root.saved || passwordField.text.length > 0 || !root.network?.isSecure)
                        onClicked: {
                            root.busy = true;
                            root.resultText = "";
                            if (root.saved && passwordField.text.length > 0) {
                                Nmcli.updateSavedNetworkPassword(root.ssid, passwordField.text, root.finish, root.network?.bssid || "", root.network?.frequency || 0);
                            } else if (root.saved) {
                                Nmcli.connectToNetwork(root.ssid, "", root.network?.bssid || "", root.finish);
                            } else {
                                NetworkConnection.connectWithPassword(root.network, passwordField.text, root.finish);
                            }
                            passwordField.text = "";
                        }
                    }

                    TextButton {
                        text: qsTr("Disconnect")
                        visible: root.connected
                        enabled: !root.busy
                        onClicked: {
                            Nmcli.disconnectFromNetwork();
                            root.resultText = qsTr("Disconnected");
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    TextButton {
                        text: qsTr("Forget")
                        visible: root.saved
                        enabled: !root.busy
                        onClicked: {
                            root.busy = true;
                            Nmcli.forgetNetwork(root.ssid, result => {
                                root.finish(result);
                                if (result.success)
                                    root.nState.closeSubPage();
                            }, root.network?.bssid || "", root.network?.frequency || 0);
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.resultText.length > 0
                    text: root.resultText
                    color: root.resultError ? Colours.palette.m3error : Colours.palette.m3primary
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
