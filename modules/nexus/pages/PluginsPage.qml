pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Plugins")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: heroLayout.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: heroLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "extension"
                    font: Tokens.font.icon.large
                    color: Colours.palette.m3primary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Plugin Engine")
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Native C++ and QML plugin runtime is active")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Active plugins & modules")
        }

        InfoRow {
            first: true
            label: qsTr("Caelestia Native Plugin")
            value: qsTr("Active (%1)").arg(CUtils.version || "1.0.0")
        }

        InfoRow {
            label: qsTr("M3Shapes Extension")
            value: qsTr("Active")
        }

        InfoRow {
            label: qsTr("Network Service Plugin")
            value: Nmcli.wifiEnabled ? qsTr("Wi-Fi Active") : qsTr("Enabled")
        }

        InfoRow {
            label: qsTr("Audio & Pipewire Service")
            value: qsTr("Active")
        }

        InfoRow {
            label: qsTr("VPN Management Service")
            value: GlobalConfig.utilities.vpn.enabled ? qsTr("Enabled") : qsTr("Standby")
        }

        InfoRow {
            last: true
            label: qsTr("Weather & Location Service")
            value: GlobalConfig.services.weatherLocation ? GlobalConfig.services.weatherLocation : qsTr("Auto-detect")
        }
    }
}
