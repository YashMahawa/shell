import QtQuick

// Cover shown when nothing is playing: a frosted glass card with a softly
// breathing equaliser, instead of an empty placeholder.
Item {
    id: root

    property bool shown: false
    property bool running: false

    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: 500
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.16) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.06) }
        }
    }

    property real phase: 0

    NumberAnimation on phase {
        running: root.running && root.visible
        from: 0
        to: Math.PI * 2
        duration: 3200
        loops: Animation.Infinite
    }

    Row {
        anchors.centerIn: parent
        spacing: root.width * 0.035
        height: root.height * 0.3

        Repeater {
            model: 5

            Rectangle {
                required property int index
                // Each bar breathes on its own offset, like a quiet room.
                readonly property real level: 0.28 + 0.5 * (0.5 + 0.5 * Math.sin(root.phase * (1 + index * 0.17) + index * 1.3))

                anchors.bottom: parent.bottom
                width: root.width * 0.055
                height: parent.height * level
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.78)
            }
        }
    }
}
