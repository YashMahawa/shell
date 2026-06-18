import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

GridLayout {
    id: root

    required property var lock

    readonly property bool isPortrait: lock.screen ? lock.screen.width < lock.screen.height : false
    
    // Scale proportionally to the smaller screen dimension. 1080 is used as a base reference.
    readonly property real fluidScale: Math.max(0.5, Math.min(lock.screen?.width ?? 1080, lock.screen?.height ?? 1080) / 1080.0)

    columns: isPortrait ? 1 : 3
    rows: isPortrait ? 3 : 1
    flow: isPortrait ? GridLayout.TopToBottom : GridLayout.LeftToRight

    rowSpacing: Tokens.spacing.largeIncreased * 2
    columnSpacing: Tokens.spacing.largeIncreased * 2

    // Primary priority: Center (Clock, login profile)
    Center {
        Layout.row: isPortrait ? 0 : 0
        Layout.column: isPortrait ? 0 : 1
        Layout.alignment: Qt.AlignHCenter
        lock: root.lock
        fluidScale: root.fluidScale
    }

    // Secondary priority: Weather, Fetch, Media
    ColumnLayout {
        Layout.row: isPortrait ? 1 : 0
        Layout.column: isPortrait ? 0 : 0
        Layout.fillWidth: true
        Layout.fillHeight: isPortrait ? false : true
        spacing: Tokens.spacing.medium

        WeatherInfo {
            Layout.fillWidth: true
            rootHeight: root.height
            fluidScale: root.fluidScale
        }

        Fetch {
            Layout.fillWidth: true
            rootHeight: root.height
            fluidScale: root.fluidScale
        }

        Media {
            Layout.fillWidth: true
            Layout.fillHeight: true
            lock: root.lock
        }
    }

    // Tertiary priority: Resources, Notifications
    ColumnLayout {
        Layout.row: isPortrait ? 2 : 0
        Layout.column: isPortrait ? 0 : 2
        Layout.fillWidth: true
        Layout.fillHeight: isPortrait ? false : true
        spacing: Tokens.spacing.medium

        Resources {
            Layout.fillWidth: true
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            bottomRightRadius: Tokens.rounding.extraLarge
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            NotifDock {
                lock: root.lock
            }
        }
    }
}
