pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.images
import qs.services

// Apple Music style full-screen player: flowing artwork backdrop, (animated)
// cover with transport on one side and synced lyrics on the other.
FocusScope {
    id: root

    required property bool active
    signal exitRequested

    readonly property bool landscape: width >= height * 1.12
    readonly property string artSource: HighResArtwork.displaySource
    property real displayPosition: Players.active?.position ?? 0
    property string displayedTitle: Players.active?.trackTitle || qsTr("Nothing playing")
    property string displayedArtist: Players.active?.trackArtist || qsTr("Choose a song to begin")
    property bool seeking: false
    property real seekPreview: 0

    function formatTime(value: real): string {
        const seconds = Math.max(0, Math.floor(value || 0));
        return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
    }

    function commitMetadata(): void {
        const title = Players.active?.trackTitle || "";
        const artist = Players.active?.trackArtist || "";
        // Browsers briefly clear MPRIS metadata while changing tracks.
        if (!title && !artist)
            return;
        root.displayedTitle = title || qsTr("Nothing playing");
        root.displayedArtist = artist || qsTr("Choose a song to begin");
    }

    focus: active
    Keys.onEscapePressed: root.exitRequested()
    Keys.onSpacePressed: Players.active?.togglePlaying()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_I && (event.modifiers & Qt.AltModifier)) {
            root.exitRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Right && Players.active?.canSeek) {
            Players.active.position = Math.min(Players.activeLength, Players.active.position + 5);
            event.accepted = true;
        } else if (event.key === Qt.Key_Left && Players.active?.canSeek) {
            Players.active.position = Math.max(0, Players.active.position - 5);
            event.accepted = true;
        }
    }

    onActiveChanged: {
        if (active) {
            root.commitMetadata();
            root.displayPosition = Players.active?.position ?? 0;
            forceActiveFocus();
        }
    }

    Timer {
        interval: 250
        running: root.active && (Players.active?.isPlaying ?? false)
        repeat: true
        onTriggered: root.displayPosition = Players.active?.position ?? root.displayPosition
    }

    Timer {
        id: metadataDelay

        interval: 260
        repeat: false
        onTriggered: metadataSwap.restart()
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true

        function onPositionChanged(): void {
            root.displayPosition = Players.active?.position ?? 0;
        }
        function onPostTrackChanged(): void {
            metadataDelay.restart();
        }
        function onTrackTitleChanged(): void {
            metadataDelay.restart();
        }
        function onTrackArtistChanged(): void {
            metadataDelay.restart();
        }
    }

    SequentialAnimation {
        id: metadataSwap

        NumberAnimation {
            target: metadata
            property: "opacity"
            to: 0
            duration: 160
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: root.commitMetadata()
        }
        NumberAnimation {
            target: metadata
            property: "opacity"
            to: 1
            duration: 360
            easing.type: Easing.OutCubic
        }
    }

    // ---- backdrop ---------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        color: "#0d1016"
        opacity: root.active ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutCubic
            }
        }
    }

    FluidBackdrop {
        anchors.fill: parent
        source: root.artSource
        running: root.active
        playing: Players.active?.isPlaying ?? false
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 1.08

        Behavior on opacity {
            NumberAnimation {
                duration: 520
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 900
                easing.type: Easing.OutQuint
            }
        }
    }

    // ---- artwork and transport -----------------------------------------------------

    Item {
        id: artPane

        x: root.landscape ? root.width * 0.065 : root.width * 0.08
        y: (root.landscape ? root.height * 0.1 : root.height * 0.05) + (root.active ? 0 : root.height * 0.035)
        width: root.landscape ? root.width * 0.38 : root.width * 0.84
        height: root.landscape ? root.height * 0.8 : root.height * 0.42
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.94

        Behavior on y {
            NumberAnimation {
                duration: 760
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1, 1]
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 420
                easing.type: Easing.OutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 760
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1, 1]
            }
        }

        Item {
            id: coverFrame

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Math.min(parent.width * (root.landscape ? 0.86 : 0.6), parent.height * (root.landscape ? 0.66 : 0.72))
            height: width
            // A playing cover breathes slightly larger, as in Apple Music.
            scale: Players.active?.isPlaying ?? false ? 1 : 0.9

            Behavior on scale {
                NumberAnimation {
                    duration: 650
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.2, 1.1, 0.3, 1, 1, 1]
                }
            }

            function updateArtworkRequest(): void {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                HighResArtwork.requestSize(width * dpr * 1.2);
            }

            onWidthChanged: updateArtworkRequest()
            Component.onCompleted: updateArtworkRequest()

            RectangularShadow {
                anchors.fill: cover
                anchors.topMargin: coverFrame.height * 0.05
                radius: cover.radius
                blur: coverFrame.width * 0.12
                spread: -coverFrame.width * 0.02
                color: Qt.rgba(0, 0, 0, 0.5)
            }

            StyledClippingRect {
                id: cover

                anchors.fill: parent
                radius: Math.max(12, width * 0.035)
                color: Qt.rgba(1, 1, 1, 0.08)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "album"
                    color: Qt.rgba(1, 1, 1, 0.4)
                    fontStyle: Tokens.font.icon.size(Math.max(64, parent.width * 0.25)).build()
                }

                FadeImage {
                    anchors.fill: parent
                    source: root.artSource
                }

                MotionCover {
                    anchors.fill: parent
                    source: MotionArtwork.source
                    playing: root.active && (Players.active?.isPlaying ?? false)
                }
            }
        }

        Item {
            id: metadata

            anchors.top: coverFrame.bottom
            anchors.topMargin: Math.max(22, parent.height * 0.04)
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            height: titleText.implicitHeight + artistText.implicitHeight + 2

            Text {
                id: titleText

                width: parent.width
                text: root.displayedTitle
                color: "white"
                font.family: Tokens.font.headline.small.family
                font.pixelSize: Math.round(Math.max(22, Math.min(34, root.width * 0.0145)))
                font.variableAxes: { "wght": 580, "ROND": 30 }
                font.weight: Font.Bold
                elide: Text.ElideRight
                renderType: Text.QtRendering
            }

            Text {
                id: artistText

                anchors.top: titleText.bottom
                anchors.topMargin: 2
                width: parent.width
                text: root.displayedArtist
                color: Qt.rgba(1, 1, 1, 0.62)
                font.family: Tokens.font.headline.small.family
                font.pixelSize: Math.round(titleText.font.pixelSize * 0.82)
                font.weight: Font.Medium
                font.variableAxes: { "wght": 460, "ROND": 30 }
                elide: Text.ElideRight
                renderType: Text.QtRendering
            }
        }

        Item {
            id: progress

            readonly property real length: Math.max(1, Players.activeLength)
            readonly property real shownPosition: root.seeking ? root.seekPreview : root.displayPosition
            readonly property bool engaged: progressHover.hovered || root.seeking

            anchors.top: metadata.bottom
            anchors.topMargin: 20
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            height: 26

            Rectangle {
                id: track

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: progress.engaged ? 10 : 6
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.22)

                Behavior on height {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, progress.shownPosition / progress.length))
                    height: parent.height
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, progress.engaged ? 0.95 : 0.78)
                }
            }

            HoverHandler {
                id: progressHover

                cursorShape: (Players.active?.canSeek ?? false) ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -8
                anchors.bottomMargin: -8
                enabled: Players.active?.canSeek ?? false
                onPressed: mouse => {
                    root.seeking = true;
                    root.seekPreview = Math.max(0, Math.min(1, mouse.x / width)) * progress.length;
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        root.seekPreview = Math.max(0, Math.min(1, mouse.x / width)) * progress.length;
                }
                onReleased: {
                    if (Players.active)
                        Players.active.position = root.seekPreview;
                    root.displayPosition = root.seekPreview;
                    root.seeking = false;
                }
            }
        }

        Item {
            id: times

            anchors.top: progress.bottom
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            height: elapsed.implicitHeight

            Text {
                id: elapsed

                text: root.formatTime(progress.shownPosition)
                color: Qt.rgba(1, 1, 1, 0.55)
                font.family: Tokens.font.label.small.family
                font.pixelSize: 13
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                renderType: Text.QtRendering
            }

            Text {
                anchors.right: parent.right
                text: `-${root.formatTime(progress.length - progress.shownPosition)}`
                color: Qt.rgba(1, 1, 1, 0.55)
                font: elapsed.font
                renderType: Text.QtRendering
            }
        }

        Row {
            anchors.top: times.bottom
            anchors.topMargin: Math.max(12, parent.height * 0.025)
            anchors.horizontalCenter: coverFrame.horizontalCenter
            spacing: coverFrame.width * 0.12

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                kind: "previous"
                disabled: !Players.active?.canGoPrevious
                onClicked: Players.active?.previous()
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                kind: Players.active?.isPlaying ? "pause" : "play"
                disabled: !Players.active?.canTogglePlaying
                onClicked: Players.active?.togglePlaying()
            }

            TransportButton {
                anchors.verticalCenter: parent.verticalCenter
                kind: "next"
                disabled: !Players.active?.canGoNext
                onClicked: Players.active?.next()
            }
        }
    }

    // ---- lyrics -----------------------------------------------------------------------

    Item {
        id: lyricsPane

        x: (root.landscape ? root.width * 0.5 : root.width * 0.07) + (root.active ? 0 : root.width * 0.03)
        y: root.landscape ? 0 : root.height * 0.5
        width: root.landscape ? root.width * 0.44 : root.width * 0.86
        height: root.landscape ? root.height : root.height * 0.5
        opacity: root.active ? 1 : 0

        ImmersiveLyricList {
            anchors.fill: parent
            active: root.active
        }

        Behavior on x {
            NumberAnimation {
                duration: 820
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1, 1]
            }
        }

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation {
                    duration: root.active ? 90 : 0
                }
                NumberAnimation {
                    duration: 460
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
