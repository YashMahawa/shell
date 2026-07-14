pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components

Rectangle {
    id: root

    required property string icon
    property bool primary: false
    property bool disabled: false
    signal clicked

    implicitWidth: primary ? 58 : 50
    implicitHeight: implicitWidth
    radius: implicitWidth / 2
    opacity: disabled ? 0.32 : 1
    scale: mouse.pressed ? 0.84 : mouse.containsMouse ? 1.045 : 1
    color: {
        if (primary)
            return mouse.pressed ? "#d7dbe0" : "#f3f5f7";
        return mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.055);
    }
    border.width: primary ? 0 : 1
    border.color: Qt.rgba(1, 1, 1, 0.13)

    MaterialIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: root.icon
        color: root.primary ? "#12151a" : "#d6dce4"
        fontStyle: root.primary ? Tokens.font.icon.large : Tokens.font.icon.medium
        fill: 1
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Behavior on scale {
        SpringAnimation {
            spring: 5.4
            damping: 0.31
            epsilon: 0.002
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }
}
