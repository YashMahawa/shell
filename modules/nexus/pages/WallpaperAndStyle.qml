pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Wallpaper & style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: GlobalConfig.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: GlobalConfig.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: Wallpapers.current
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: qsTr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !GlobalConfig.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: qsTr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            Layout.fillWidth: true

            first: true
            text: qsTr("Display wallpaper")
            checked: GlobalConfig.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true

            text: qsTr("Transparency")
            subtext: qsTr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true

            last: true
            text: qsTr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        SectionHeader {
            text: qsTr("Desktop clock")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Show desktop clock")
            checked: GlobalConfig.background.desktopClock.enabled
            onToggled: GlobalConfig.background.desktopClock.enabled = checked
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Clock placement")
            subtext: qsTr("Position on the desktop")
            active: {
                switch (GlobalConfig.background.desktopClock.position) {
                case "top-left": return clockTopLeft;
                case "top-center": return clockTopCenter;
                case "top-right": return clockTopRight;
                case "middle-left": return clockMiddleLeft;
                case "middle-center": return clockMiddleCenter;
                case "middle-right": return clockMiddleRight;
                case "bottom-left": return clockBottomLeft;
                case "bottom-center": return clockBottomCenter;
                case "bottom-right":
                default: return clockBottomRight;
                }
            }
            onSelected: item => GlobalConfig.background.desktopClock.position = item.position
            menuItems: [
                MenuItem { id: clockTopLeft; text: qsTr("Top left"); property string position: "top-left" },
                MenuItem { id: clockTopCenter; text: qsTr("Top center"); property string position: "top-center" },
                MenuItem { id: clockTopRight; text: qsTr("Top right"); property string position: "top-right" },
                MenuItem { id: clockMiddleLeft; text: qsTr("Middle left"); property string position: "middle-left" },
                MenuItem { id: clockMiddleCenter; text: qsTr("Middle center"); property string position: "middle-center" },
                MenuItem { id: clockMiddleRight; text: qsTr("Middle right"); property string position: "middle-right" },
                MenuItem { id: clockBottomLeft; text: qsTr("Bottom left"); property string position: "bottom-left" },
                MenuItem { id: clockBottomCenter; text: qsTr("Bottom center"); property string position: "bottom-center" },
                MenuItem { id: clockBottomRight; text: qsTr("Bottom right"); property string position: "bottom-right" }
            ]
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Clock scale")
            subtext: qsTr("Size multiplier")
            value: GlobalConfig.background.desktopClock.scale
            from: 0.5
            to: 3.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.desktopClock.scale = v
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Horizontal offset")
            subtext: qsTr("Negative moves left; positive moves right")
            value: GlobalConfig.background.desktopClock.xOffset
            from: -800
            to: 800
            stepSize: 10
            onMoved: v => GlobalConfig.background.desktopClock.xOffset = v
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Vertical offset")
            subtext: qsTr("Negative moves up; positive moves down")
            value: GlobalConfig.background.desktopClock.yOffset
            from: -400
            to: 400
            stepSize: 10
            onMoved: v => GlobalConfig.background.desktopClock.yOffset = v
        }

        SelectRow {
            Layout.fillWidth: true
            label: qsTr("Clock style")
            subtext: qsTr("Arrange the time and date")
            active: {
                switch (GlobalConfig.background.desktopClock.style) {
                case "stacked-sections": return clockStyleStacked;
                case "vertical-time": return clockStyleVerticalTime;
                case "horizontal":
                default: return clockStyleHorizontal;
                }
            }
            onSelected: item => GlobalConfig.background.desktopClock.style = item.styleName
            menuItems: [
                MenuItem { id: clockStyleHorizontal; text: qsTr("Horizontal"); property string styleName: "horizontal" },
                MenuItem { id: clockStyleStacked; text: qsTr("Stacked sections"); property string styleName: "stacked-sections" },
                MenuItem { id: clockStyleVerticalTime; text: qsTr("Vertical time"); property string styleName: "vertical-time" }
            ]
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Show date")
            checked: GlobalConfig.background.desktopClock.showDate
            onToggled: GlobalConfig.background.desktopClock.showDate = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Invert clock colours")
            checked: GlobalConfig.background.desktopClock.invertColors
            onToggled: GlobalConfig.background.desktopClock.invertColors = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Clock shadow")
            checked: GlobalConfig.background.desktopClock.shadow.enabled
            onToggled: GlobalConfig.background.desktopClock.shadow.enabled = checked
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Shadow opacity")
            value: GlobalConfig.background.desktopClock.shadow.opacity
            from: 0
            to: 1
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.desktopClock.shadow.opacity = v
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Shadow blur")
            value: GlobalConfig.background.desktopClock.shadow.blur
            from: 0
            to: 1
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.desktopClock.shadow.blur = v
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Clock background")
            checked: GlobalConfig.background.desktopClock.background.enabled
            onToggled: GlobalConfig.background.desktopClock.background.enabled = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Blur clock background")
            checked: GlobalConfig.background.desktopClock.background.blur
            onToggled: GlobalConfig.background.desktopClock.background.blur = checked
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Clock background opacity")
            value: GlobalConfig.background.desktopClock.background.opacity
            from: 0
            to: 1
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.desktopClock.background.opacity = v
        }

        SectionHeader {
            text: qsTr("Desktop visualiser")
        }

        ToggleRow {
            Layout.fillWidth: true
            first: true
            text: qsTr("Show audio visualiser")
            checked: GlobalConfig.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.enabled = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Auto-hide behind windows")
            checked: GlobalConfig.background.visualiser.autoHide
            onToggled: GlobalConfig.background.visualiser.autoHide = checked
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Blur visualiser")
            checked: GlobalConfig.background.visualiser.blur
            onToggled: GlobalConfig.background.visualiser.blur = checked
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Visualiser rounding")
            value: GlobalConfig.background.visualiser.rounding
            from: 0
            to: 10
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.visualiser.rounding = v
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Visualiser spacing")
            value: GlobalConfig.background.visualiser.spacing
            from: 0
            to: 2
            stepSize: 0.1
            onMoved: v => GlobalConfig.background.visualiser.spacing = v
        }

        SectionHeader {
            text: qsTr("Design system tokens")
        }

        StepperRow {
            Layout.fillWidth: true
            first: true
            label: qsTr("Corner rounding scale")
            subtext: qsTr("Scale factor for corner rounding tokens")
            value: GlobalConfig.appearance.rounding.scale
            from: 0.5
            to: 2.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.rounding.scale = v
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Shell padding scale")
            subtext: qsTr("Scale factor for shell padding tokens")
            value: GlobalConfig.appearance.padding.scale
            from: 0.5
            to: 2.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.padding.scale = v
        }

        StepperRow {
            Layout.fillWidth: true
            label: qsTr("Shell spacing scale")
            subtext: qsTr("Scale factor for shell spacing tokens")
            value: GlobalConfig.appearance.spacing.scale
            from: 0.5
            to: 2.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.spacing.scale = v
        }

        StepperRow {
            Layout.fillWidth: true
            last: true
            label: qsTr("Font scale")
            subtext: qsTr("Scale factor for font tokens")
            value: GlobalConfig.appearance.font.scale
            from: 0.5
            to: 2.0
            stepSize: 0.1
            onMoved: v => GlobalConfig.appearance.font.scale = v
        }
    }
}
