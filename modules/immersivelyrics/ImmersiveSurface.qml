pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
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

    // Cover state for the current track: "loading", then "motion" or "static".
    // A still cover, once shown, stays for that track.
    property string coverKey: ""
    property string coverMode: "loading"
    property real coverSince: 0
    property real motionSince: 0
    property bool coverShown: false
    readonly property bool coverReady: coverShown || (coverMode === "motion" ? motionCover.showing
        : coverMode === "static" ? stillCover.status === Image.Ready : false)

    onCoverReadyChanged: {
        if (coverReady)
            coverShown = true;
    }

    function decideCover(): void {
        const key = MotionArtwork.trackKey;
        const now = Date.now();
        if (key !== coverKey) {
            coverKey = key;
            coverMode = "loading";
            coverShown = false;
            coverSince = now;
        }
        if (coverMode === "static")
            return;
        const waited = now - coverSince;
        if (coverMode === "motion") {
            // A clip that never produces frames falls back to the still cover.
            if (!motionCover.showing && now - motionSince > 3500)
                coverMode = "static";
            return;
        }
        const phase = MotionArtwork.phase;
        if (phase === "ready" && MotionArtwork.source) {
            coverMode = "motion";
            motionSince = now;
        } else if (phase === "none" && (HighResArtwork.settled || waited > 3000)) {
            coverMode = "static";
        } else if (phase === "looking" && waited > (HighResArtwork.settled ? 3000 : 5000)) {
            coverMode = "static";
        } else if (phase === "downloading" && waited > 10000) {
            coverMode = "static";
        }
    }

    Timer {
        interval: 250
        running: root.active && !root.coverReady
        repeat: true
        triggeredOnStart: true
        onTriggered: root.decideCover()
    }

    Connections {
        target: MotionArtwork

        function onPhaseChanged(): void {
            root.decideCover();
        }
        function onTrackKeyChanged(): void {
            root.decideCover();
        }
    }

    Connections {
        target: HighResArtwork

        function onSettledChanged(): void {
            root.decideCover();
        }
    }

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
        // Keep the previous colours until the final artwork is known.
        source: HighResArtwork.settled ? root.artSource : ""
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
            width: Math.min(parent.width * (root.landscape ? 0.86 : 0.6), parent.height * (root.landscape ? 0.6 : 0.66))
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

                // Loading shimmer: shown until this track's final cover (motion
                // clip or settled still artwork) is ready, so interim thumbnails
                // never flash.
                Item {
                    anchors.fill: parent
                    opacity: root.coverReady ? 0 : 1
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 420
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        id: shimmer

                        property real phase: 0

                        width: parent.width * 0.6
                        height: parent.height * 2
                        y: -parent.height / 2
                        x: -width + (parent.width + width) * phase
                        rotation: 18
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
                            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                        }

                        NumberAnimation on phase {
                            running: !root.coverReady && root.active
                            from: 0
                            to: 1
                            duration: 1500
                            loops: Animation.Infinite
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                FadeImage {
                    id: stillCover

                    anchors.fill: parent
                    source: root.coverMode === "static" ? root.artSource : ""
                }

                MotionCover {
                    id: motionCover

                    anchors.fill: parent
                    source: root.coverMode === "motion" ? MotionArtwork.source : ""
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

            anchors.top: metadata.bottom
            anchors.topMargin: Math.max(18, parent.height * 0.03)
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            height: slider.implicitHeight + times.implicitHeight

            GlassSlider {
                id: slider

                anchors.left: parent.left
                anchors.right: parent.right
                interactive: Players.active?.canSeek ?? false
                value: Math.max(0, Math.min(1, root.displayPosition / progress.length))
                onMoved: v => {
                    root.seeking = true;
                    root.seekPreview = v * progress.length;
                }
                onReleased: v => {
                    if (Players.active)
                        Players.active.position = v * progress.length;
                    root.displayPosition = v * progress.length;
                    root.seeking = false;
                }
            }

            Item {
                id: times

                anchors.top: slider.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                implicitHeight: elapsed.implicitHeight

                Text {
                    id: elapsed

                    text: root.formatTime(progress.shownPosition)
                    color: Qt.rgba(1, 1, 1, slider.engaged ? 0.85 : 0.6)
                    font.family: Tokens.font.label.small.family
                    font.pixelSize: Math.round(Math.max(13, Math.min(16, root.width * 0.0068)))
                    font.variableAxes: { "wght": 560, "ROND": 30 }
                    font.features: { "tnum": 1 }
                    renderType: Text.QtRendering

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    text: Players.activeLength > 0 ? `-${root.formatTime(progress.length - progress.shownPosition)}` : "--:--"
                    color: elapsed.color
                    font: elapsed.font
                    renderType: Text.QtRendering
                }
            }
        }

        Row {
            id: transport

            anchors.top: progress.bottom
            anchors.topMargin: Math.max(14, parent.height * 0.028)
            anchors.horizontalCenter: coverFrame.horizontalCenter
            spacing: Math.max(28, coverFrame.width * 0.13)

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

        RowLayout {
            anchors.top: transport.bottom
            anchors.topMargin: Math.max(12, parent.height * 0.022)
            anchors.left: coverFrame.left
            anchors.right: coverFrame.right
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "volume_mute"
                color: Qt.rgba(1, 1, 1, 0.6)
                fill: 1
                fontStyle: Tokens.font.icon.medium

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.setVolume(Math.max(0, Audio.volume - 0.1))
                }
            }

            GlassSlider {
                Layout.fillWidth: true
                thickness: 5
                hoverThickness: 9
                wheelEnabled: true
                value: Audio.muted ? 0 : Math.min(1, Audio.volume)
                onMoved: v => Audio.setVolume(v)
            }

            MaterialIcon {
                text: "volume_up"
                color: Qt.rgba(1, 1, 1, 0.6)
                fill: 1
                fontStyle: Tokens.font.icon.medium

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Audio.setVolume(Math.min(1, Audio.volume + 0.1))
                }
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
