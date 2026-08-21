pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import qs.services

PageBase {
    id: root

    title: qsTr("Dashboard")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Enabled")
            checked: GlobalConfig.dashboard.enabled
            onToggled: GlobalConfig.dashboard.enabled = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal when the cursor reaches the screen edge")
            checked: GlobalConfig.dashboard.showOnHover
            onToggled: GlobalConfig.dashboard.showOnHover = checked
        }

        // Tabs
        SectionHeader {
            text: qsTr("Tabs")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Dashboard")
            checked: GlobalConfig.dashboard.showDashboard
            onToggled: GlobalConfig.dashboard.showDashboard = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Media")
            checked: GlobalConfig.dashboard.showMedia
            onToggled: GlobalConfig.dashboard.showMedia = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Performance")
            checked: GlobalConfig.dashboard.showPerformance
            onToggled: GlobalConfig.dashboard.showPerformance = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Weather")
            checked: GlobalConfig.dashboard.showWeather
            onToggled: GlobalConfig.dashboard.showWeather = checked
        }

        // Calendar
        SectionHeader {
            text: qsTr("Calendar")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("National holidays")
            subtext: qsTr("Show country-wide public holidays in the dashboard")
            checked: GlobalConfig.dashboard.showNationalHolidays
            onToggled: GlobalConfig.dashboard.showNationalHolidays = checked
        }

        ConnectedRect {
            Layout.fillWidth: true
            last: true
            implicitHeight: countryRow.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: countryRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: qsTr("Holiday country")
                        font: Tokens.font.body.small
                    }

                    StyledText {
                        text: qsTr("Auto-detected as %1; enter a two-letter code to override").arg(CalendarEvents.countryCode || qsTr("unknown"))
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }

                StyledTextField {
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignHCenter
                    text: GlobalConfig.dashboard.calendarCountryCode
                    placeholderText: CalendarEvents.countryCode || "IN"
                    maximumLength: 2
                    validator: RegularExpressionValidator {
                        regularExpression: /[A-Za-z]{0,2}/
                    }
                    onEditingFinished: GlobalConfig.dashboard.calendarCountryCode = text.trim().toUpperCase()
                }
            }
        }

        // Performance widgets
        SectionHeader {
            text: qsTr("Performance widgets")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Battery")
            checked: GlobalConfig.dashboard.performance.showBattery
            onToggled: GlobalConfig.dashboard.performance.showBattery = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("GPU")
            checked: GlobalConfig.dashboard.performance.showGpu
            onToggled: GlobalConfig.dashboard.performance.showGpu = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("CPU")
            checked: GlobalConfig.dashboard.performance.showCpu
            onToggled: GlobalConfig.dashboard.performance.showCpu = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Memory")
            checked: GlobalConfig.dashboard.performance.showMemory
            onToggled: GlobalConfig.dashboard.performance.showMemory = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Storage")
            checked: GlobalConfig.dashboard.performance.showStorage
            onToggled: GlobalConfig.dashboard.performance.showStorage = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Network")
            checked: GlobalConfig.dashboard.performance.showNetwork
            onToggled: GlobalConfig.dashboard.performance.showNetwork = checked
        }

        // Behaviour
        SectionHeader {
            text: qsTr("Behaviour")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the dashboard opens")
            value: GlobalConfig.dashboard.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.dashboard.dragThreshold = v
        }
    }
}
