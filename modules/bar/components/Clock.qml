pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    readonly property color colour: Colours.palette.m3tertiary
    readonly property int padding: Config.bar.clock.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property var font: Tokens.font.body.builders.small.scale(1.1)

    implicitWidth: isVertical ? Tokens.sizes.bar.innerWidth : layout.implicitWidth + root.padding * 2
    implicitHeight: isVertical ? layout.implicitHeight + root.padding * 2 : Tokens.sizes.bar.innerWidth

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, Config.bar.clock.background ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    GridLayout {
        id: layout
        flow: root.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

        anchors.centerIn: parent
        rowSpacing: Tokens.spacing.extraSmall
        columnSpacing: Tokens.spacing.extraSmall

        Loader {
            Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
            asynchronous: true
            active: Config.bar.clock.showIcon
            visible: active

            sourceComponent: MaterialIcon {
                text: "calendar_month"
                color: root.colour
            }
        }

        StyledText {
            Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
            visible: Config.bar.clock.showDate

            horizontalAlignment: StyledText.AlignHCenter
            text: root.isVertical ? Time.format("ddd\nd") : Time.format("ddd d")
            font: Tokens.font.body.small
            color: root.colour
        }

        Rectangle {
            Layout.fillWidth: root.isVertical
            Layout.fillHeight: !root.isVertical
            visible: Config.bar.clock.showDate
            implicitHeight: root.isVertical ? 1 : -1
            implicitWidth: root.isVertical ? -1 : 1
            color: Colours.palette.m3outlineVariant
        }

        StyledText {
            Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
            text: Time.hourStr
            font: {
                const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / hourMetrics.width);
                return root.font.width(scale * 100).letterSpacing(scale).build();
            }
            color: root.colour

            TextMetrics {
                id: hourMetrics

                font: root.font.build()
                text: Time.hourStr
            }
        }

        StyledText {
            Layout.topMargin: root.isVertical ? -parent.rowSpacing - 4 : 0
            Layout.leftMargin: !root.isVertical ? -parent.columnSpacing - 4 : 0
            Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
            text: Time.minuteStr
            font: {
                const scale = text === "11" ? 1.15 : Math.min(1.05, Math.max(hourMetrics.width, minMetrics.width) / minMetrics.width);
                return root.font.width(scale * 100).letterSpacing(scale).build();
            }
            color: root.colour

            TextMetrics {
                id: minMetrics

                font: root.font.build()
                text: Time.minuteStr
            }
        }

        Loader {
            Layout.topMargin: root.isVertical ? -parent.rowSpacing - 4 : 0
            Layout.leftMargin: !root.isVertical ? -parent.columnSpacing - 4 : 0
            Layout.alignment: root.isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
            asynchronous: true
            active: GlobalConfig.services.useTwelveHourClock
            visible: active

            sourceComponent: StyledText {
                text: Time.amPmStr.toLowerCase()
                font: Tokens.font.body.builders.small.scale(0.9).build()
                color: root.colour
            }
        }
    }
}
