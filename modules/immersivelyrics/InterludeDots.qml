import QtQuick

// Three dots shown during instrumental breaks. They fill one after another
// across the gap and breathe gently; just before the next line they swell and
// shrink away, as in Apple Music.
Item {
    id: root

    // 0..1 through the instrumental gap; negative when inactive.
    property real progress: -1
    property real dotSize: 14
    property bool reduceMotion: false
    readonly property bool active: progress >= 0
    readonly property real exit: progress > 0.88 ? (progress - 0.88) / 0.12 : 0

    implicitWidth: dotSize * 3 + dotSize * 0.9 * 2
    implicitHeight: dotSize * 2.4

    property real breath: 0

    NumberAnimation on breath {
        running: root.active && root.visible && !root.reduceMotion
        from: 0
        to: Math.PI * 2
        duration: 2600
        loops: Animation.Infinite
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.dotSize * 0.9
        transformOrigin: Item.Left
        scale: root.reduceMotion ? 1 : (1 + 0.1 * Math.sin(root.breath)) * (1 + 0.25 * Math.sin(Math.PI * Math.min(1, root.exit * 1.4))) * (1 - root.exit * 0.9)
        opacity: 1 - Math.max(0, root.exit - 0.55) / 0.45

        Repeater {
            model: 3

            Rectangle {
                required property int index
                readonly property real fill: Math.max(0, Math.min(1, root.progress * 3.3 - index))

                width: root.dotSize
                height: root.dotSize
                radius: root.dotSize / 2
                color: "white"
                opacity: 0.28 + 0.72 * fill
            }
        }
    }
}
