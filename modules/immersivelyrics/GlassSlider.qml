import QtQuick
import QtQuick.Effects

// Apple Music style slider: a soft translucent track that thickens on hover,
// with a knob that appears while hovering or dragging. `value` is 0..1;
// `moved` fires while dragging and `released` once the drag ends.
Item {
    id: root

    property real value: 0
    property bool interactive: true
    property real thickness: 6
    property real hoverThickness: 11
    readonly property bool engaged: hover.hovered || area.pressed
    readonly property real shownValue: area.pressed ? dragValue : value
    property real dragValue: 0
    property bool wheelEnabled: false

    signal moved(real value)
    signal released(real value)

    implicitHeight: 28
    opacity: interactive ? 1 : 0.4

    function valueAt(x: real): real {
        return Math.max(0, Math.min(1, x / Math.max(1, width)));
    }

    Rectangle {
        id: track

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.engaged ? root.hoverThickness : root.thickness
        radius: height / 2
        color: Qt.rgba(1, 1, 1, root.engaged ? 0.24 : 0.18)
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: 240
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        Rectangle {
            width: Math.max(track.height, parent.width * root.shownValue)
            height: parent.height
            radius: parent.radius
            color: Qt.rgba(1, 1, 1, root.engaged ? 0.97 : 0.82)
            visible: root.shownValue > 0

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
    }

    Rectangle {
        id: knob

        width: root.hoverThickness + 8
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(root.width - width, root.width * root.shownValue - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        color: "white"
        opacity: root.engaged && root.interactive ? 1 : 0
        scale: area.pressed ? 1.15 : root.engaged ? 1 : 0.4

        layer.enabled: opacity > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.6
            shadowVerticalOffset: 2
            blurMax: 16
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 1.6
            }
        }
    }

    HoverHandler {
        id: hover

        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        id: area

        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        enabled: root.interactive
        preventStealing: true
        onPressed: mouse => {
            root.dragValue = root.valueAt(mouse.x);
            root.moved(root.dragValue);
        }
        onPositionChanged: mouse => {
            if (pressed) {
                root.dragValue = root.valueAt(mouse.x);
                root.moved(root.dragValue);
            }
        }
        onReleased: root.released(root.dragValue)
    }

    WheelHandler {
        enabled: root.interactive && root.wheelEnabled
        onWheel: event => {
            const step = (event.angleDelta.y || event.angleDelta.x) / 120 * 0.04;
            const next = Math.max(0, Math.min(1, root.value + step));
            root.moved(next);
            root.released(next);
        }
    }
}
