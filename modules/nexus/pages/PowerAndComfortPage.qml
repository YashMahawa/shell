pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    function formatSeconds(s: int, fallback: string): string {
        if (!s || s <= 0)
            return fallback;
        const day = Math.floor(s / 86400);
        const hr = Math.floor(s / 3600) % 24;
        const min = Math.floor(s / 60) % 60;

        let comps = [];
        if (day > 0)
            comps.push(`${day} days`);
        if (hr > 0)
            comps.push(`${hr} hours`);
        if (min > 0)
            comps.push(`${min} mins`);

        return comps.join(", ") || fallback;
    }

    title: qsTr("Power & Comfort")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Hardware Battery Status Overview
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: overviewLayout.implicitHeight + overviewLayout.anchors.margins * 2

            ColumnLayout {
                id: overviewLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.large

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.large

                    StyledRect {
                        implicitWidth: 64
                        implicitHeight: 64
                        radius: Tokens.rounding.large
                        color: UltraPower.active
                            ? Colours.palette.m3tertiaryContainer
                            : ([UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)
                                ? Colours.palette.m3primaryContainer
                                : Colours.palette.m3secondaryContainer)

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: UPower.displayDevice.isLaptopBattery
                                ? Icons.getBatteryIcon(UPower.displayDevice.percentage, [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state))
                                : "power"
                            fontStyle: Tokens.font.icon.large
                            color: UltraPower.active
                                ? Colours.palette.m3tertiary
                                : ([UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)
                                    ? Colours.palette.m3primary
                                    : Colours.palette.m3secondary)
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: UPower.displayDevice.isLaptopBattery
                                ? `${Math.round(UPower.displayDevice.percentage * 100)}%`
                                : qsTr("AC Power")
                            font: Tokens.font.title.large
                        }

                        StyledText {
                            text: UPower.displayDevice.isLaptopBattery
                                ? (UPower.displayDevice.state === UPowerDeviceState.FullyCharged
                                    ? qsTr("Fully charged")
                                    : ([UPowerDeviceState.Charging, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state)
                                        ? qsTr("Charging")
                                        : qsTr("Discharging")))
                                : qsTr("Connected to power supply")
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            visible: UPower.displayDevice.isLaptopBattery
                            text: qsTr("Time %1: %2").arg(UPower.onBattery ? "remaining" : "until charged").arg(UPower.onBattery ? root.formatSeconds(UPower.displayDevice.timeToEmpty, "Calculating...") : root.formatSeconds(UPower.displayDevice.timeToFull, "Fully charged!"))
                            font: Tokens.font.label.small
                            color: Colours.palette.m3outline
                        }
                    }
                }

                StyledProgressBar {
                    Layout.fillWidth: true
                    visible: UPower.displayDevice.isLaptopBattery
                    value: UPower.displayDevice.percentage
                }
            }
        }

        // Power Profiles
        SectionHeader {
            first: true
            text: qsTr("Power profiles")
        }

        ProfileRow {
            Layout.fillWidth: true
            first: true
            iconName: "rocket_launch"
            titleText: qsTr("Performance")
            descriptionText: qsTr("High performance, maximum system responsiveness")
            selected: !UltraPower.active && PowerProfiles.profile === PowerProfile.Performance
            onClicked: UltraPower.selectProfile("performance")
        }

        ProfileRow {
            Layout.fillWidth: true
            iconName: "balance"
            titleText: qsTr("Balanced")
            descriptionText: qsTr("Standard balance between speed and battery consumption")
            selected: !UltraPower.active && PowerProfiles.profile === PowerProfile.Balanced
            onClicked: UltraPower.selectProfile("balanced")
        }

        ProfileRow {
            Layout.fillWidth: true
            iconName: "energy_savings_leaf"
            titleText: qsTr("Power Saver")
            descriptionText: qsTr("Preserves battery life by limiting CPU power usage")
            selected: !UltraPower.active && PowerProfiles.profile === PowerProfile.PowerSaver
            onClicked: UltraPower.selectProfile("power-saver")
        }

        ProfileRow {
            Layout.fillWidth: true
            last: true
            iconName: "battery_saver"
            titleText: qsTr("Ultra Power Saver")
            descriptionText: qsTr("Aggressive energy saving with limited CPU power and disabled animations")
            selected: UltraPower.active
            onClicked: {
                if (!UltraPower.active)
                    UltraPower.toggle();
            }
        }

        // Display Comfort (Night Light)
        SectionHeader {
            text: qsTr("Display comfort")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Night Light")
            subtext: NightLight.backendAvailable
                ? qsTr("Warm screen colors to reduce blue light and eye strain")
                : qsTr("No supported Night Light backend available")
            checked: NightLight.enabled
            enabled: NightLight.backendAvailable
            onToggled: checked => NightLight.setEnabled(checked)
        }

        SliderRow {
            Layout.fillWidth: true
            last: true
            icon: "thermostat"
            label: qsTr("Night Light temperature")
            valueLabel: NightLight.backendAvailable ? `${NightLight.temperature} K` : qsTr("Unavailable")
            value: NightLight.warmth
            enabled: NightLight.enabled && NightLight.backendAvailable
            onMoved: v => NightLight.setWarmth(v)
        }
    }

    component ProfileRow: ConnectedRect {
        id: pRow

        required property string iconName
        required property string titleText
        required property string descriptionText
        required property bool selected

        signal clicked

        Layout.fillWidth: true
        implicitHeight: pLayout.implicitHeight + pLayout.anchors.margins * 2

        StateLayer {
            anchors.fill: parent
            onClicked: pRow.clicked()
        }

        RowLayout {
            id: pLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: pRow.iconName
                fontStyle: Tokens.font.icon.medium
                color: pRow.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: pRow.titleText
                    font: Tokens.font.body.small
                    color: pRow.selected ? Colours.palette.m3primary : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: pRow.descriptionText
                    font: Tokens.font.label.small
                    color: Colours.palette.m3outline
                }
            }

            MaterialIcon {
                text: pRow.selected ? "radio_button_checked" : "radio_button_unchecked"
                fontStyle: Tokens.font.icon.medium
                color: pRow.selected ? Colours.palette.m3primary : Colours.palette.m3outline
            }
        }
    }
}
