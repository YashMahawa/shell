pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property bool m3ShapesActive: m3ShapesChecker.status === Loader.Ready && m3ShapesChecker.item !== null

    title: qsTr("Plugins")

    Loader {
        id: m3ShapesChecker

        active: true
        sourceComponent: Component {
            MaterialShape {
                visible: false
            }
        }
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
                        text: qsTr("Native C++ and QML plugin runtime status")
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
            value: CUtils && CUtils.version ? qsTr("Active (v%1)").arg(CUtils.version) : qsTr("Unavailable")
        }

        InfoRow {
            label: qsTr("M3Shapes Extension")
            value: root.m3ShapesActive ? qsTr("Active") : qsTr("Unavailable")
        }

        InfoRow {
            label: qsTr("Network Service Plugin")
            value: {
                if (typeof Nmcli === "undefined" || !Nmcli) return qsTr("Unavailable");
                if (Nmcli.wifiEnabled) return qsTr("Wi-Fi Active (%1 network(s))").arg(Network && Network.wifiNetworks ? Network.wifiNetworks.length : 0);
                if (Nmcli.networkingEnabled) return qsTr("Networking Active");
                if (Nmcli.deviceStatus !== null) return qsTr("Disabled");
                return qsTr("Unavailable");
            }
        }

        InfoRow {
            label: qsTr("Audio & Pipewire Service")
            value: {
                if (typeof Audio === "undefined" || !Audio) return qsTr("Unavailable");
                if (Audio.sink !== null && Audio.sinks) return qsTr("PipeWire Active (%1 sink(s))").arg(Audio.sinks.length);
                if (Audio.node !== null) return qsTr("PipeWire Active (0 sinks)");
                return qsTr("PipeWire Unavailable");
            }
        }

        InfoRow {
            label: qsTr("VPN Management Service")
            value: {
                if (typeof VPN === "undefined" || !VPN) return qsTr("Unavailable");
                if (VPN.active) return qsTr("Connected (%1)").arg(VPN.activeProfileName || "VPN");
                if (GlobalConfig && GlobalConfig.utilities && GlobalConfig.utilities.vpn && GlobalConfig.utilities.vpn.enabled) return qsTr("Enabled (Disconnected)");
                return qsTr("Disabled");
            }
        }

        InfoRow {
            label: qsTr("Weather & Location Service")
            value: {
                if (typeof Weather === "undefined" || !Weather) return qsTr("Unavailable");
                if (Weather.cc) return qsTr("Active (%1)").arg(Weather.city || Weather.description);
                if (Weather.ipApiRequestPending) return qsTr("Fetching location...");
                return qsTr("Unavailable");
            }
        }

        InfoRow {
            last: true
            label: qsTr("Display & Brightness Service")
            value: {
                if (typeof Brightness === "undefined" || !Brightness) return qsTr("Unavailable");
                if (Brightness.monitors && Brightness.monitors.length > 0) return qsTr("Active (%1 monitor(s))").arg(Brightness.monitors.length);
                if (Brightness.available) return qsTr("Standby / Auto");
                return qsTr("Unavailable");
            }
        }
    }
}
