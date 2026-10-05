import QtQuick
import QtQuick.Effects

// Glass capsule slider. The track is a frosted capsule with a faint top
// highlight; the elapsed part is a bright, softly glowing fill. Hovering or
// dragging thickens it and shows a small bubble with `bubbleText` above the
// pointer. `value` is 0..1; `moved` fires while dragging, `released` at the end.
Item {
    id: root

    property real value: 0
    property bool interactive: true
    property bool wheelEnabled: false
    property real thickness: 7
    property real hoverThickness: 13
    // Text for the hover/drag bubble; bind it to `previewValue`.
    property string bubbleText: ""

    readonly property bool engaged: hover.hovered || area.pressed
    readonly property real shownValue: area.pressed ? dragValue : value
    readonly property real previewValue: area.pressed ? dragValue : hoverValue
    property real dragValue: 0
    property real hoverValue: 0

    signal moved(real value)
    signal released(real value)

    implicitHeight: 30
    opacity: interactive ? 1 : 0.45

    function valueAt(x: real): real {
        return Math.max(0, Math.min(1, x / Math.max(1, width)));
    }

    Item {
        id: capsule

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.engaged ? root.hoverThickness : root.thickness

        Behavior on height {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }

        // Frosted track with a faint top highlight.
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.engaged ? 0.26 : 0.2) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, root.engaged ? 0.14 : 0.1) }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)
        }

        Item {
            id: fillClip

            width: Math.max(capsule.height, capsule.width * root.shownValue)
            height: capsule.height
            visible: root.shownValue > 0

            layer.enabled: root.engaged
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(1, 1, 1, 0.55)
                shadowBlur: 0.7
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 18
                autoPaddingEnabled: true
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, root.engaged ? 0.86 : 0.7) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, root.engaged ? 1 : 0.9) }
                }
            }
        }
    }

    // Time bubble above the pointer.
    Rectangle {
        id: bubble

        readonly property real centre: root.width * root.previewValue

        visible: opacity > 0 && root.bubbleText !== ""
        opacity: root.engaged && root.interactive ? 1 : 0
        width: bubbleLabel.implicitWidth + 18
        height: bubbleLabel.implicitHeight + 10
        radius: height / 2
        x: Math.max(0, Math.min(root.width - width, centre - width / 2))
        y: capsule.y - height - 10 + (root.engaged ? 0 : 6)
        color: Qt.rgba(1, 1, 1, 0.16)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.22)

        Behavior on opacity {
            NumberAnimation {
                duration: 180
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutCubic
            }
        }

        Text {
            id: bubbleLabel

            anchors.centerIn: parent
            text: root.bubbleText
            color: "white"
            font.pixelSize: 13
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            renderType: Text.QtRendering
        }
    }

    HoverHandler {
        id: hover

        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        onPointChanged: root.hoverValue = root.valueAt(point.position.x)
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
