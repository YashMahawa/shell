import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"

    required property DrawerVisibilities visibilities

    implicitWidth: isVertical ? icon.implicitHeight + Tokens.padding.small : icon.implicitHeight
    implicitHeight: isVertical ? icon.implicitHeight : icon.implicitHeight + Tokens.padding.small

    StateLayer {
        // Cursed workaround to make the height larger than the parent
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: isVertical ? implicitHeight : icon.implicitHeight + Tokens.padding.small
        implicitHeight: isVertical ? icon.implicitHeight + Tokens.padding.small : implicitWidth
        radius: Tokens.rounding.full
        onClicked: root.visibilities.session = !root.visibilities.session
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        text: "power_settings_new"
        color: Colours.palette.m3error
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
    }
}
