pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.images
import qs.services

FocusScope {
    id: root

    required property bool active
    signal exitRequested

    readonly property bool landscape: width >= height * 1.12
    readonly property color primaryText: "#e1e6ed"
    readonly property color secondaryText: "#abb3bd"
    property real displayPosition: Players.active?.position ?? 0
    property string displayedTitle: Players.active?.trackTitle || qsTr("Nothing playing")
    property string displayedArtist: Players.active?.trackArtist || qsTr("Choose a song to begin")

    function formatTime(value: real): string {
        const seconds = Math.max(0, Math.floor(value || 0));
        return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
    }

    function scheduleMetadataSwap(): void {
        if (root.active)
            metadataDelay.restart();
        else
            root.commitMetadata();
    }

    function commitMetadata(): void {
        const title = Players.active?.trackTitle || "";
        const artist = Players.active?.trackArtist || "";
        // Browsers briefly clear MPRIS metadata while changing tracks. Keep the
        // previous identity until the actual song has arrived.
        if (!title && !artist)
            return;
        root.displayedTitle = title || qsTr("Nothing playing");
        root.displayedArtist = artist || qsTr("Choose a song to begin");
    }

    focus: true
    opacity: active ? 1 : 0
    Keys.onEscapePressed: root.exitRequested()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_I && (event.modifiers & Qt.AltModifier)) {
            root.exitRequested();
            event.accepted = true;
        }
    }

    onActiveChanged: {
        if (active) {
            root.displayPosition = Players.active?.position ?? 0;
            forceActiveFocus();
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.active ? 520 : 390
            easing.type: Easing.OutCubic
        }
    }

    Timer {
        interval: 100
        running: root.active && (Players.active?.isPlaying ?? false)
        repeat: true
        onTriggered: root.displayPosition = Players.active?.position ?? root.displayPosition
    }

    Timer {
        id: metadataDelay

        interval: 300
        repeat: false
        onTriggered: metadataSwap.restart()
    }

    SequentialAnimation {
        id: metadataSwap

        ParallelAnimation {
            NumberAnimation {
                target: metadata
                property: "opacity"
                to: 0
                duration: 150
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: metadata
                property: "scale"
                to: 0.975
                duration: 170
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: root.commitMetadata()
        }
        ParallelAnimation {
            NumberAnimation {
                target: metadata
                property: "opacity"
                to: 1
                duration: 330
                easing.type: Easing.OutCubic
            }
            SpringAnimation {
                target: metadata
                property: "scale"
                to: 1
                spring: 3.8
                damping: 0.42
                epsilon: 0.001
            }
        }
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true

        function onPositionChanged(): void {
            root.displayPosition = Players.active?.position ?? 0;
        }
        function onPostTrackChanged(): void {
            root.scheduleMetadataSwap();
        }
        function onTrackTitleChanged(): void {
            root.scheduleMetadataSwap();
        }
        function onTrackArtistChanged(): void {
            root.scheduleMetadataSwap();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#10151c"
    }

    FadeImage {
        id: ambientArt

        anchors.fill: parent
        source: HighResArtwork.source
        fillMode: Image.PreserveAspectCrop
        scale: root.active ? 1.045 : 1.14

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 96
            saturation: 0.82
        }

        Behavior on scale {
            SpringAnimation {
                spring: 2.3
                damping: 0.42
                epsilon: 0.002
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ambientArt.status === Image.Ready ? Qt.rgba(0.018, 0.022, 0.03, 0.64) : "#11151b"

        Behavior on color {
            ColorAnimation {
                duration: 620
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                color: Qt.rgba(0.015, 0.02, 0.028, 0.13)
                position: 0
            }
            GradientStop {
                color: Qt.rgba(0.015, 0.02, 0.028, root.landscape ? 0.34 : 0.2)
                position: 0.5
            }
            GradientStop {
                color: Qt.rgba(0.015, 0.02, 0.028, 0.62)
                position: 1
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical

            GradientStop {
                color: Qt.rgba(0.01, 0.014, 0.02, 0.18)
                position: 0
            }
            GradientStop {
                color: "transparent"
                position: 0.52
            }
            GradientStop {
                color: Qt.rgba(0.01, 0.014, 0.02, 0.48)
                position: 1
            }
        }
    }

    Item {
        id: artPane

        x: (root.landscape ? root.width * 0.055 : root.width * 0.08) + (root.active ? 0 : -48)
        y: root.landscape ? root.height * 0.07 : root.height * 0.045
        width: root.landscape ? root.width * 0.41 : root.width * 0.84
        height: root.landscape ? root.height * 0.86 : root.height * 0.4
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.84

        Behavior on x {
            SpringAnimation {
                spring: 2.8
                damping: 0.38
                epsilon: 0.02
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.active ? 520 : 280
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            SpringAnimation {
                spring: 3.3
                damping: 0.34
                epsilon: 0.002
            }
        }

        Item {
            id: coverFrame

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width * (root.landscape ? 0.85 : 0.57), parent.height * (root.landscape ? 0.69 : 0.74))
            height: width

            function updateArtworkRequest(): void {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                HighResArtwork.requestSize(width * dpr * 1.2);
            }

            onWidthChanged: updateArtworkRequest()
            Component.onCompleted: updateArtworkRequest()

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0.005, 0.008, 0.014, 0.88)
                shadowOpacity: 0.9
                shadowBlur: 0.72
                shadowVerticalOffset: 22
                blurMax: 58
            }

            StyledClippingRect {
                anchors.fill: parent
                radius: Math.max(18, width * 0.045)
                color: "#1b2027"

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "album"
                    color: "#68717c"
                    fontStyle: Tokens.font.icon.size(Math.max(64, parent.width * 0.25)).build()
                }

                FadeImage {
                    anchors.fill: parent
                    source: HighResArtwork.source
                    z: 1
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Math.max(18, coverFrame.width * 0.045)
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                    z: 2
                }
            }
        }

        Column {
            id: metadata

            anchors.top: coverFrame.bottom
            anchors.topMargin: Math.max(20, parent.height * 0.032)
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            spacing: 5

            Text {
                width: parent.width
                text: root.displayedTitle
                color: root.primaryText
                font.family: Tokens.font.headline.small.family
                font.pixelSize: Math.max(23, Math.min(34, root.width * 0.023))
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                renderType: Text.QtRendering
                renderTypeQuality: Text.VeryHighRenderTypeQuality
            }

            Text {
                width: parent.width
                text: root.displayedArtist
                color: root.secondaryText
                font: Tokens.font.title.medium
                elide: Text.ElideRight
                renderType: Text.QtRendering
                renderTypeQuality: Text.VeryHighRenderTypeQuality
            }
        }

        Item {
            id: progress

            anchors.top: metadata.bottom
            anchors.topMargin: 18
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            height: 24

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 3
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.16)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.displayPosition / Math.max(1, Players.active?.length ?? 1)))
                    height: parent.height
                    radius: parent.radius
                    color: "#edf0f3"
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: Players.active?.canSeek ?? false
                onClicked: mouse => {
                    const player = Players.active;
                    if (player)
                        player.position = Math.max(0, Math.min(1, mouse.x / width)) * player.length;
                }
            }
        }

        Row {
            anchors.top: progress.bottom
            anchors.topMargin: 10
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right

            Text {
                text: root.formatTime(root.displayPosition)
                color: "#919aa5"
                font: Tokens.font.label.small
                renderType: Text.QtRendering
            }

            Item {
                width: parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth
                height: 1
            }

            Text {
                text: root.formatTime(Players.active?.length ?? 0)
                color: "#919aa5"
                font: Tokens.font.label.small
                renderType: Text.QtRendering
            }
        }

        Rectangle {
            anchors.horizontalCenter: coverFrame.horizontalCenter
            anchors.bottom: parent.bottom
            width: 232
            height: 70
            radius: 35
            color: Qt.rgba(0.045, 0.052, 0.064, 0.48)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.14)

            Item {
                anchors.centerIn: parent
                width: 184
                height: 58

                TransportButton {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_previous"
                    disabled: !Players.active?.canGoPrevious
                    onClicked: Players.active?.previous()
                }

                TransportButton {
                    anchors.centerIn: parent
                    primary: true
                    icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                    disabled: !Players.active?.canTogglePlaying
                    onClicked: Players.active?.togglePlaying()
                }

                TransportButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "skip_next"
                    disabled: !Players.active?.canGoNext
                    onClicked: Players.active?.next()
                }
            }
        }
    }

    Item {
        id: lyricsPane

        x: (root.landscape ? root.width * 0.505 : root.width * 0.07)
            + (root.active ? (HighResArtwork.transitioning ? 30 : 0) : 64)
        y: root.landscape ? root.height * 0.065 : root.height * 0.49
        width: root.landscape ? root.width * 0.43 : root.width * 0.86
        height: root.landscape ? root.height * 0.87 : root.height * 0.46
        opacity: root.active && !HighResArtwork.transitioning ? 1 : 0

        ImmersiveLyricList {
            anchors.fill: parent
            active: root.active
        }

        Behavior on x {
            SpringAnimation {
                spring: 2.65
                damping: 0.4
                epsilon: 0.02
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.active && !HighResArtwork.transitioning ? 540 : 210
                easing.type: Easing.OutCubic
            }
        }
    }
}
