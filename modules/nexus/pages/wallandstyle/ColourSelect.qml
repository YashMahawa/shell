pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Colours")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Colour mode & scheme")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Dark mode")
            subtext: qsTr("Use dark background and high-contrast elements")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Smart scheme")
            subtext: qsTr("Extract colour palette dynamically from wallpaper")
            checked: GlobalConfig.services.smartScheme
            onToggled: GlobalConfig.services.smartScheme = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            last: true
            text: qsTr("Transparency")
            subtext: qsTr("Enable alpha blending for shell panels")
            checked: GlobalConfig.appearance.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }
    }
}
