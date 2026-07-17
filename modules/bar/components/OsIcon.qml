import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

GridLayout {
    id: root
    readonly property bool isVertical: Config.bar.edge === "left" || Config.bar.edge === "right"
    readonly property real iconSize: Math.round(Tokens.font.body.large.pointSize * 1.6)
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rowSpacing: Tokens.spacing.small
    columnSpacing: Tokens.spacing.small

    Item {
        implicitWidth: root.iconSize
        implicitHeight: root.iconSize

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                const visibilities = Visibilities.getForActive();
                visibilities.launcher = !visibilities.launcher;
            }
        }

        Loader {
            asynchronous: true
            anchors.centerIn: parent
            sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
        }
    }

    ContinuityButton {
        icon: "content_paste_search"
        colour: Colours.palette.m3secondary
        onTriggered: Quickshell.execDetached(["caelestia", "shell", "clipboard", "open"])
    }

    ContinuityButton {
        iconSource: Quickshell.iconPath("kdeconnect-symbolic", "kdeconnect")
        colour: Colours.palette.m3primary
        onTriggered: Quickshell.execDetached(["caelestia", "shell", "clipboard", "openPhone"])
    }

    Component {
        id: caelestiaLogo
        Logo { implicitWidth: root.iconSize; implicitHeight: root.iconSize }
    }

    Component {
        id: distroIcon
        ColouredIcon {
            source: SysInfo.osLogo
            implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2)
            colour: Colours.palette.m3tertiary
        }
    }

    component ContinuityButton: Item {
        id: button
        property string icon
        property string iconSource
        required property color colour
        signal triggered()
        implicitWidth: root.iconSize
        implicitHeight: root.iconSize

        StateLayer {
            anchors.fill: parent
            radius: Tokens.rounding.full
            onClicked: button.triggered()
        }
        Loader {
            anchors.centerIn: parent
            sourceComponent: button.iconSource ? connectGraphic : materialGraphic
        }
        Component {
            id: materialGraphic
            MaterialIcon {
                text: button.icon
                color: button.colour
                fontStyle: Tokens.font.icon.small
                fill: 1
                renderType: Text.NativeRendering
            }
        }
        Component {
            id: connectGraphic
            ColouredIcon {
                source: button.iconSource
                implicitSize: Math.round(Tokens.font.body.large.pointSize * 1.2)
                colour: button.colour
            }
        }
    }
}
