import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

GridLayout {
    id: root

    Layout.fillWidth: true
    Layout.margins: Tokens.padding.large

    rowSpacing: Tokens.spacing.large
    columnSpacing: Tokens.spacing.large
    rows: 2
    columns: 2

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    Resource {
        Layout.topMargin: Tokens.padding.large
        icon: "memory"
        value: Cpu.percentage
        colour: Colours.palette.m3primary
    }

    Resource {
        Layout.topMargin: Tokens.padding.large
        icon: "thermostat"
        value: Math.min(1, Cpu.temperature / 90)
        colour: Colours.palette.m3secondary
    }

    Resource {
        Layout.bottomMargin: Tokens.padding.large
        icon: "memory_alt"
        value: Memory.percentage
        colour: Colours.palette.m3secondary
    }

    Resource {
        Layout.bottomMargin: Tokens.padding.large
        icon: "hard_disk"
        value: Storage.percentage
        colour: Colours.palette.m3tertiary
    }

    component Resource: StyledRect {
        id: res

        required property string icon
        required property real value
        required property color colour

        Layout.fillWidth: true
        implicitHeight: width

        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
        radius: Tokens.rounding.large

        CircularProgress {
            id: circ

            anchors.fill: parent
            value: res.value
            padding: Tokens.padding.large * 3
            fgColour: res.colour
            bgColour: Colours.layer(Colours.palette.m3surfaceContainerHighest, 3)
            strokeWidth: width < 200 ? Tokens.padding.extraSmall : Tokens.padding.medium
        }

        MaterialIcon {
            id: icon

            anchors.centerIn: parent
            text: res.icon
            color: res.colour
            font.pointSize: (circ.arcRadius * 0.7) || 1
            font.weight: 600
        }

        Behavior on value {
            Anim {
                type: Anim.StandardLarge
            }
        }
    }
}
