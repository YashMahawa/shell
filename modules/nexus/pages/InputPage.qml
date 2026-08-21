pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Input")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Pointer")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            last: true
            label: qsTr("Mouse sensitivity")
            subtext: qsTr("Pointer speed multiplier")
            value: GlobalConfig.input.pointerSpeed
            from: -1.0
            to: 1.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.input.pointerSpeed = v
        }

        SectionHeader {
            text: qsTr("Touchpad")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Tap to click")
            subtext: qsTr("Tap the touchpad to perform a click")
            checked: GlobalConfig.input.touchpadTapToClick
            onToggled: GlobalConfig.input.touchpadTapToClick = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Natural scrolling")
            subtext: qsTr("Reverse scroll direction")
            checked: GlobalConfig.input.touchpadNaturalScroll
            onToggled: GlobalConfig.input.touchpadNaturalScroll = checked
        }

        SectionHeader {
            text: qsTr("Keyboard")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Repeat rate")
            subtext: qsTr("Characters per second when holding a key")
            value: GlobalConfig.input.keyboardRepeatRate
            from: 1
            to: 100
            stepSize: 1
            onMoved: v => GlobalConfig.input.keyboardRepeatRate = Math.round(v)
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Repeat delay")
            subtext: qsTr("Delay in milliseconds before repeating keys")
            value: GlobalConfig.input.keyboardRepeatDelay
            from: 100
            to: 1000
            stepSize: 10
            onMoved: v => GlobalConfig.input.keyboardRepeatDelay = Math.round(v)
        }
    }
}
