pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property Item wallpaper
    required property real absX
    required property real absY

    property real clockScale: Config.background.desktopClock.scale
    readonly property bool bgEnabled: Config.background.desktopClock.background.enabled
    readonly property bool blurEnabled: bgEnabled && Config.background.desktopClock.background.blur && !GameMode.enabled && TrueLite.effectsEnabled
    readonly property bool invertColors: Config.background.desktopClock.invertColors
    readonly property string layoutStyle: Config.background.desktopClock.style
    readonly property bool stackedSections: layoutStyle === "stacked-sections"
    readonly property bool verticalTime: layoutStyle === "vertical-time"
    readonly property bool showDate: Config.background.desktopClock.showDate
    readonly property bool useLightSet: Colours.light ? !invertColors : invertColors
    readonly property color safePrimary: useLightSet ? Colours.palette.m3primaryContainer : Colours.palette.m3primary
    readonly property color safeSecondary: useLightSet ? Colours.palette.m3secondaryContainer : Colours.palette.m3secondary
    readonly property color safeTertiary: useLightSet ? Colours.palette.m3tertiaryContainer : Colours.palette.m3tertiary

    implicitWidth: layout.implicitWidth + (Tokens.padding.large * 4 * root.clockScale)
    implicitHeight: layout.implicitHeight + (Tokens.padding.extraLargeIncreased * root.clockScale)

    Item {
        id: clockContainer

        anchors.fill: parent

        layer.enabled: Config.background.desktopClock.shadow.enabled
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Colours.palette.m3shadow
            shadowOpacity: Config.background.desktopClock.shadow.opacity
            shadowBlur: Config.background.desktopClock.shadow.blur
        }

        Loader {
            asynchronous: true
            anchors.fill: parent
            active: root.blurEnabled

            sourceComponent: MultiEffect {
                source: ShaderEffectSource {
                    sourceItem: root.wallpaper
                    sourceRect: Qt.rect(root.absX, root.absY, root.width, root.height)
                }
                maskSource: backgroundPlate
                maskEnabled: true
                blurEnabled: true
                blur: 1
                blurMax: 64
                autoPaddingEnabled: false
            }
        }

        StyledRect {
            id: backgroundPlate

            visible: root.bgEnabled
            anchors.fill: parent
            radius: Tokens.rounding.extraLarge * root.clockScale
            opacity: Config.background.desktopClock.background.opacity
            color: Colours.palette.m3surface

            layer.enabled: root.blurEnabled
        }

        GridLayout {
            id: layout

            anchors.centerIn: parent
            rowSpacing: Tokens.spacing.large * root.clockScale
            columnSpacing: Tokens.spacing.large * root.clockScale
            columns: root.stackedSections ? 1 : 3
            rows: root.stackedSections ? 3 : 1

            GridLayout {
                rowSpacing: 0
                columnSpacing: Tokens.spacing.small
                columns: root.verticalTime ? 1 : 4
                rows: root.verticalTime ? 3 : 1

                StyledText {
                    text: Time.hourStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * root.clockScale).weight(Font.Bold).build()
                    color: root.safePrimary
                    Layout.alignment: root.verticalTime ? Qt.AlignHCenter : Qt.AlignVCenter
                }

                StyledText {
                    visible: !root.verticalTime
                    text: ":"
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * root.clockScale).build()
                    color: root.safeTertiary
                    opacity: 0.8
                    Layout.topMargin: -Tokens.padding.large * 1.5 * root.clockScale
                }

                StyledText {
                    text: Time.minuteStr
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * 3 * root.clockScale).weight(Font.Bold).build()
                    color: root.safeSecondary
                    Layout.alignment: root.verticalTime ? Qt.AlignHCenter : Qt.AlignVCenter
                }

                Loader {
                    asynchronous: true
                    Layout.alignment: root.verticalTime ? Qt.AlignHCenter : Qt.AlignTop
                    Layout.topMargin: root.verticalTime ? 0 : Tokens.padding.large * 1.4 * root.clockScale

                    active: GlobalConfig.services.useTwelveHourClock
                    visible: active

                    sourceComponent: StyledText {
                        text: Time.amPmStr
                        font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.clockScale).build()
                        color: root.safeSecondary
                    }
                }
            }

            StyledRect {
                visible: root.showDate
                Layout.fillHeight: !root.stackedSections
                Layout.fillWidth: root.stackedSections
                Layout.preferredWidth: root.stackedSections ? -1 : 4 * root.clockScale
                Layout.preferredHeight: root.stackedSections ? 4 * root.clockScale : -1
                Layout.topMargin: root.stackedSections ? 0 : Tokens.spacing.large * root.clockScale
                Layout.bottomMargin: root.stackedSections ? 0 : Tokens.spacing.large * root.clockScale
                Layout.leftMargin: root.stackedSections ? Tokens.spacing.large * root.clockScale : 0
                Layout.rightMargin: root.stackedSections ? Tokens.spacing.large * root.clockScale : 0
                radius: Tokens.rounding.full
                color: root.safePrimary
                opacity: 0.8
            }

            ColumnLayout {
                visible: root.showDate
                spacing: 0

                StyledText {
                    text: Time.format("MMMM").toUpperCase()
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.clockScale).letterSpacing(4).weight(Font.Bold).build()
                    color: root.safeSecondary
                }

                StyledText {
                    text: Time.format("dd")
                    font: Tokens.font.clock.size(Tokens.font.headline.medium.pointSize * root.clockScale).letterSpacing(2).weight(Font.Medium).build()
                    color: root.safePrimary
                }

                StyledText {
                    text: Time.format("dddd")
                    font: Tokens.font.clock.size(Tokens.font.body.large.pointSize * root.clockScale).letterSpacing(2).build()
                    color: root.safeSecondary
                }
            }
        }
    }

    Behavior on clockScale {
        Anim {}
    }

    Behavior on implicitWidth {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
