import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.immersivelyrics

Item {
    id: root

    required property bool active
    property bool toolsOpen: false
    property bool retained: false

    function syncRetention(): void {
        if (active && !retained) {
            SyllableLyrics.retain();
            retained = true;
        } else if (!active && retained) {
            SyllableLyrics.release();
            retained = false;
        }
    }

    onActiveChanged: syncRetention()
    Component.onCompleted: syncRetention()
    Component.onDestruction: {
        if (retained)
            SyllableLyrics.release();
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        spacing: Tokens.spacing.small

        RowLayout {
            spacing: Tokens.spacing.small

            StyledText {
                text: qsTr("Lyrics")
                font: Tokens.font.title.medium
            }

            // Which provider is showing; also opens the source tools.
            StyledRect {
                Layout.fillWidth: true
                Layout.maximumWidth: implicitWidth
                implicitWidth: chipLabel.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: chipLabel.implicitHeight + Tokens.padding.extraSmall * 2
                visible: !!SyllableLyrics.provider
                radius: Tokens.rounding.full
                color: chipMouse.containsMouse ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh

                StyledText {
                    id: chipLabel

                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - Tokens.padding.medium * 2)
                    text: SyllableLyrics.provider
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                    animate: true
                }

                MouseArea {
                    id: chipMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toolsOpen = !root.toolsOpen
                }
            }

            Item {
                Layout.fillWidth: true
            }

            IconButton {
                icon: "open_in_full"
                type: IconButton.Text
                disabled: !Players.active
                onClicked: ImmersiveLyricsState.open((QsWindow.window as QsWindow)?.screen?.name ?? "")
            }

            IconButton {
                icon: "tune"
                type: root.toolsOpen ? IconButton.Tonal : IconButton.Text
                onClicked: root.toolsOpen = !root.toolsOpen
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ImmersiveLyricList {
                anchors.fill: parent
                visible: opacity > 0
                opacity: root.toolsOpen ? 0 : 1
                active: root.active && !root.toolsOpen
                textColor: Colours.palette.m3onSurface
                activeColor: Colours.palette.m3primary
                fontPixelSize: Math.round(Math.max(17, Math.min(24, stableWidth * 0.06)))
                anchorRatio: 0.3
                fadeTop: 0.22
                fadeBottom: 0.38

                Behavior on opacity {
                    Anim {}
                }
            }

            LyricsInfo {
                anchors.fill: parent
                visible: opacity > 0
                opacity: root.toolsOpen ? 1 : 0
                scale: root.toolsOpen ? 1 : 0.97

                Behavior on opacity {
                    Anim {}
                }

                Behavior on scale {
                    Anim {}
                }
            }
        }
    }
}
