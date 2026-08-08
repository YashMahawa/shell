import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Images
import Caelestia.Models
import qs.components
import qs.components.effects
import qs.components.images
import qs.services

Item {
    id: root

    required property var modelData
    required property DrawerVisibilities visibilities
    required property int index

    scale: PathView.onPath ? (PathView.itemScale ?? 0.74) : 0.5
    opacity: PathView.onPath ? (PathView.itemOpacity ?? 0.68) : 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    implicitWidth: image.width + Tokens.padding.medium * 2
    implicitHeight: image.height + label.height + Tokens.spacing.extraSmall + Tokens.padding.large + Tokens.padding.medium

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            if (!root.PathView.isCurrentItem) {
                root.PathView.view.userSelecting = true;
                root.PathView.view.currentIndex = root.index;
            } else {
                Wallpapers.setWallpaper(root.modelData.path);
                root.visibilities.launcher = false;
            }
        }
    }

    Elevation {
        anchors.fill: image
        radius: image.radius
        opacity: root.PathView.isCurrentItem ? 1 : 0
        level: 4

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledClippingRect {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.padding.large
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        implicitWidth: Tokens.sizes.launcher.wallpaperWidth
        implicitHeight: implicitWidth / 16 * 9

        MaterialIcon {
            anchors.centerIn: parent
            text: Wallpapers.isVideo(root.modelData.path) ? "movie" : "image"
            color: Colours.tPalette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
        }

        CachingImage {
            anchors.fill: parent
            path: root.modelData.path
            source: Wallpapers.isVideo(root.modelData.path)
                ? Wallpapers.videoThumbnail(root.modelData.path)
                : IUtils.urlForPath(root.modelData.path, fillMode)
            smooth: !root.PathView.view.moving
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(image.implicitWidth * dpr, image.implicitHeight * dpr);
            }
        }

        StyledRect {
            visible: Wallpapers.isVideo(root.modelData.path)
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.small
            implicitWidth: videoIcon.implicitWidth + Tokens.padding.small * 2
            implicitHeight: implicitWidth
            radius: Tokens.rounding.full
            color: Colours.palette.m3surface

            MaterialIcon {
                id: videoIcon
                anchors.centerIn: parent
                text: "play_arrow"
                color: Colours.palette.m3onSurface
            }
        }
    }

    StyledText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: Tokens.spacing.extraSmall
        anchors.horizontalCenter: parent.horizontalCenter

        width: image.width - Tokens.padding.medium * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
        text: root.modelData.relativePath
        font: Tokens.font.label.medium
    }

}
