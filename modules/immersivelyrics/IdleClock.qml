import QtQuick
import Caelestia.Config
import qs.services

// Large, light clock shown in the lyrics pane when nothing is playing.
Item {
    id: root

    property bool shown: false

    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.width * 0.04
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            text: Time.format(GlobalConfig.services.useTwelveHourClock ? "h:mm" : "hh:mm")
            color: "white"
            font.family: Tokens.font.headline.large.family
            font.pixelSize: Math.round(Math.max(96, Math.min(210, root.width * 0.24)))
            font.variableAxes: { "wght": 260, "ROND": 40 }
            font.features: { "tnum": 1 }
            renderType: Text.QtRendering
        }

        Text {
            text: Time.format("dddd, d MMMM")
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: Tokens.font.headline.large.family
            font.pixelSize: Math.round(Math.max(22, Math.min(40, root.width * 0.045)))
            font.variableAxes: { "wght": 480, "ROND": 30 }
            renderType: Text.QtRendering
        }
    }
}
