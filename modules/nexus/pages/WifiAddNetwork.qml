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

    title: qsTr("Add network")
    isSubPage: true

    property string ssid: ""
    property string password: ""
    property int securityIndex: 0
    readonly property string security: securityIndex === 0 ? "wpa-psk" : "none"
    property bool hidden: true
    property bool showPassword: false
    property bool busy: false
    property string resultText: ""
    property bool resultError: false

    readonly property bool canConnect: !busy && ssid.trim().length > 0 && (security === "none" || password.length >= 8)

    readonly property list<MenuItem> securityItems: [
        MenuItem {
            text: qsTr("WPA/WPA2/WPA3 Personal")
        },
        MenuItem {
            text: qsTr("Open (No security)")
        }
    ]

    function finish(result): void {
        root.busy = false;
        root.resultError = !result?.success;
        root.resultText = result?.success
            ? qsTr("Connected")
            : (result?.error || qsTr("Failed to connect to network"));
        Nmcli.refreshLiveWifiState();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Network details")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: false
            implicitHeight: ssidColumn.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: ssidColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledText {
                    text: qsTr("Network name (SSID)")
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: Tokens.rounding.large
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                    StyledTextField {
                        id: ssidField

                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        placeholderText: qsTr("Enter network name")
                        text: root.ssid
                        onTextChanged: root.ssid = text
                    }
                }
            }
        }

        SelectRow {
            Layout.fillWidth: true
            first: false
            last: false
            label: qsTr("Security")
            subtext: qsTr("Personal (WPA/WPA2/WPA3) and Open networks supported")
            menuItems: root.securityItems
            active: root.securityItems[root.securityIndex] ?? root.securityItems[0]
            onSelected: item => {
                root.securityIndex = root.securityItems.indexOf(item);
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            first: false
            last: root.security === "none"
            text: qsTr("Hidden network")
            subtext: qsTr("Network does not broadcast its SSID")
            checked: root.hidden
            onToggled: checked => root.hidden = checked
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: root.security !== "none"

            SectionHeader {
                Layout.topMargin: Tokens.spacing.large
                text: qsTr("Password")
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

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.small

                            StyledTextField {
                                id: passwordField

                                Layout.fillWidth: true
                                echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                                placeholderText: qsTr("Enter network password")
                                text: root.password
                                onTextChanged: root.password = text
                            }

                            IconButton {
                                icon: root.showPassword ? "visibility_off" : "visibility"
                                font: Tokens.font.icon.medium
                                type: IconButton.Ghost
                                onClicked: root.showPassword = !root.showPassword
                            }
                        }
                    }

                    StyledText {
                        visible: root.password.length > 0 && root.password.length < 8
                        text: qsTr("Password must be at least 8 characters")
                        color: Colours.palette.m3error
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            first: true
            last: true
            implicitHeight: actionsColumn.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: actionsColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    TextButton {
                        text: qsTr("Connect")
                        enabled: root.canConnect
                        onClicked: {
                            root.busy = true;
                            root.resultText = "";
                            Nmcli.connectHiddenNetwork(root.ssid.trim(), root.password, root.security, root.hidden, result => {
                                root.finish(result);
                                if (result && result.success) {
                                    root.nState.closeSubPage();
                                }
                            });
                        }
                    }

                    TextButton {
                        text: qsTr("Cancel")
                        enabled: !root.busy
                        onClicked: {
                            Nmcli.cancelPendingWifiOperation();
                            root.nState.closeSubPage();
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    LoadingIndicator {
                        visible: root.busy
                        implicitSize: Math.round(Tokens.font.icon.medium.pointSize * 1.3)
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
