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
            value: CUtils.version ? qsTr("Active (v%1)").arg(CUtils.version) : qsTr("Unavailable")
        }

        InfoRow {
            label: qsTr("M3Shapes Extension")
            value: CUtils.version ? qsTr("Active") : qsTr("Unavailable")
        }

        InfoRow {
            label: qsTr("Network Service Plugin")
            value: Nmcli.wifiEnabled ? qsTr("Wi-Fi Active (%1 network(s))").arg(Network.wifiNetworks ? Network.wifiNetworks.length : 0) : Nmcli.networkingEnabled ? qsTr("Networking Active") : qsTr("Disabled")
        }

        InfoRow {
            label: qsTr("Audio & Pipewire Service")
            value: Audio.sink ? qsTr("PipeWire Active (%1 sink(s))").arg(Audio.sinks ? Audio.sinks.length : 1) : qsTr("PipeWire Unavailable")
        }

        InfoRow {
            label: qsTr("VPN Management Service")
            value: VPN.active ? qsTr("Connected (%1)").arg(VPN.activeProfileName || "VPN") : GlobalConfig.utilities.vpn.enabled ? qsTr("Enabled (Disconnected)") : qsTr("Disabled")
        }

        InfoRow {
            label: qsTr("Weather & Location Service")
            value: Weather.cc ? qsTr("Active (%1)").arg(Weather.city || Weather.description) : Weather.ipApiRequestPending ? qsTr("Fetching location...") : qsTr("Unavailable")
        }

        InfoRow {
            last: true
            label: qsTr("Display & Brightness Service")
            value: Brightness.monitors && Brightness.monitors.length > 0 ? qsTr("Active (%1 monitor(s))").arg(Brightness.monitors.length) : qsTr("Standby / Auto")
        }
    }
}
