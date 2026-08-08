pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.Images
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    property bool completed
    property string displayedVideoSource: ""
    readonly property bool sourceIsVideo: Wallpapers.isVideo(source)
    readonly property string backgroundSource: sourceIsVideo ? Wallpapers.videoThumbnailPath(source) : source

    function toFileUrl(path: string): string {
        const clean = Wallpapers.cleanPath(path);
        return clean ? `file://${clean}` : "";
    }

    Component.onCompleted: {
        WallpaperEngine.source = Qt.binding(() => root.backgroundSource);
        if (sourceIsVideo)
            displayedVideoSource = toFileUrl(source);
        completed = true;
    }

    onSourceChanged: {
        if (sourceIsVideo) {
            stopVideoTimer.stop();
            displayedVideoSource = toFileUrl(source);
        } else {
            stopVideoTimer.restart();
        }
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: qsTr("Select a wallpaper")
                            filterLabel: qsTr("Image files")
                            filters: Images.validImageExtensions
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: qsTr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Repeater {
        model: WallpaperEngine
        delegate: Item {
            id: delegateRoot

            required property int index
            required property string path

            anchors.fill: parent

            CachingImage {
                id: img

                anchors.fill: parent

                path: delegateRoot.path

                opacity: status === Image.Ready ? 1 : 0

                onStatusChanged: {
                    if (status === Image.Ready) {
                        WallpaperEngine.markReady(delegateRoot.index);
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }
        }
    }

    Loader {
        id: videoLoader

        anchors.fill: parent
        active: root.displayedVideoSource !== ""
        source: "VideoWallpaper.qml"
        opacity: root.sourceIsVideo && item?.ready ? 1 : 0

        onLoaded: {
            item.videoSource = root.displayedVideoSource;
        }

        Behavior on opacity {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }

    onDisplayedVideoSourceChanged: {
        if (videoLoader.item)
            videoLoader.item.videoSource = displayedVideoSource;
    }

    Binding {
        target: videoLoader.item
        property: "autoStart"
        value: !WallpaperPauser.paused
        when: videoLoader.item !== null
    }

    Timer {
        id: stopVideoTimer
        interval: 600
        onTriggered: root.displayedVideoSource = ""
    }
}
