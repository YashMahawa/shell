import QtQuick
import QtQuick.Templates
import Caelestia.Config
import qs.components
import qs.services

Slider {
    id: root

    background: Item {
        StyledRect {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.topMargin: root.implicitHeight / 6
            anchors.bottomMargin: root.implicitHeight / 6

            implicitWidth: root.handle.x - root.implicitHeight / 6

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
            topRightRadius: root.implicitHeight / 15
            bottomRightRadius: root.implicitHeight / 15
        }

        StyledRect {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.topMargin: root.implicitHeight / 6
            anchors.bottomMargin: root.implicitHeight / 6

            implicitWidth: parent.width - root.handle.x - root.handle.implicitWidth - root.implicitHeight / 6

            color: Colours.palette.m3surfaceContainerHighest
            radius: Tokens.rounding.full
            topLeftRadius: root.implicitHeight / 15
            bottomLeftRadius: root.implicitHeight / 15
        }

        StyledRect {
            visible: root.to > 1.0
            x: (1.0 / root.to) * parent.width - (implicitWidth / 2)
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: root.implicitHeight / 4
            implicitHeight: root.implicitHeight * 0.8
            color: Colours.palette.m3outline
            radius: Tokens.rounding.full
            z: 1
        }
    }

    handle: StyledRect {
        x: root.visualPosition * root.availableWidth - implicitWidth / 2

        implicitWidth: root.implicitHeight / 4.5
        implicitHeight: root.implicitHeight

        color: Colours.palette.m3primary
        radius: Tokens.rounding.full

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            cursorShape: Qt.PointingHandCursor
        }
    }
}