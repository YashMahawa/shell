pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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

    readonly property real glyph: primary ? 40 : 40
    readonly property real stroke: glyph * 0.13

    implicitWidth: primary ? 92 : 72
    implicitHeight: implicitWidth
    opacity: disabled ? 0.3 : 1
    // Group opacity, so the glyph's overlapping fill and stroke stay solid.
    layer.enabled: opacity < 1

    // Hover halo for the bare skip glyphs.
    Rectangle {
        visible: !root.primary
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

    // Frosted glass disc behind play/pause: top-lit gradient, hairline rim and
    // a soft drop shadow; it brightens on hover.
    Item {
        visible: root.primary
        anchors.fill: parent
        scale: mouse.pressed ? 0.92 : mouse.containsMouse ? 1.04 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 340
                easing.type: Easing.OutBack
                easing.overshoot: 2
            }
        }

        Rectangle {
            id: disc

            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.32 : 0.24) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.16 : 0.1) }
            }
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, mouse.containsMouse ? 0.42 : 0.3)

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.35)
                shadowBlur: 0.8
                shadowVerticalOffset: 6
                blurMax: 32
            }
        }

        // Specular highlight along the top edge.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.06
            width: parent.width * 0.62
            height: parent.height * 0.32
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.22) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
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
