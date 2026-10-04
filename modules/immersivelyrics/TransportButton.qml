pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

// Apple Music style transport glyph: rounded vector triangles and bars drawn
// with the curve renderer, a soft circular hover and a springy press.
Item {
    id: root

    // "play", "pause", "next" or "previous".
    required property string kind
    property bool primary: false
    property bool disabled: false
    signal clicked

    readonly property real glyph: primary ? 46 : 34
    readonly property real stroke: glyph * 0.11

    implicitWidth: primary ? 84 : 66
    implicitHeight: implicitWidth
    opacity: disabled ? 0.3 : 1

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: width
        radius: width / 2
        color: "white"
        opacity: mouse.containsMouse && !root.disabled ? (mouse.pressed ? 0.16 : 0.1) : 0
        scale: mouse.containsMouse ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutCubic
            }
        }
    }

    component Triangle: Shape {
        id: triangle

        property real size
        property real stroke

        width: size
        height: size
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "white"
            strokeColor: "white"
            strokeWidth: triangle.stroke
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            startX: triangle.stroke / 2
            startY: triangle.stroke / 2 + triangle.size * 0.04

            PathLine {
                x: triangle.size - triangle.stroke / 2
                y: triangle.size / 2
            }
            PathLine {
                x: triangle.stroke / 2
                y: triangle.size - triangle.stroke / 2 - triangle.size * 0.04
            }
            PathLine {
                x: triangle.stroke / 2
                y: triangle.stroke / 2 + triangle.size * 0.04
            }
        }
    }

    Item {
        id: icon

        anchors.centerIn: parent
        width: root.glyph
        height: root.glyph
        scale: mouse.pressed ? 0.84 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 2.2
            }
        }

        Triangle {
            visible: root.kind === "play"
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.glyph * 0.06
            size: root.glyph * 0.86
            stroke: root.stroke
        }

        Row {
            visible: root.kind === "pause"
            anchors.centerIn: parent
            spacing: root.glyph * 0.2

            Repeater {
                model: 2

                Rectangle {
                    width: root.glyph * 0.24
                    height: root.glyph * 0.82
                    radius: width * 0.32
                    color: "white"
                }
            }
        }

        Row {
            visible: root.kind === "next" || root.kind === "previous"
            anchors.centerIn: parent
            spacing: -root.stroke * 0.6
            rotation: root.kind === "previous" ? 180 : 0

            Repeater {
                model: 2

                Triangle {
                    size: root.glyph * 0.56
                    stroke: root.stroke * 0.8
                }
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
