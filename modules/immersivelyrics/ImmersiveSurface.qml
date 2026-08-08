pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.images
import qs.services

FocusScope {
    id: root

    required property bool active
    property bool renderBackdrop: true
    property bool renderContent: true
    signal exitRequested

    readonly property bool landscape: width >= height * 1.12
    readonly property color primaryText: "#d8dee7"
    readonly property color secondaryText: "#abb3bd"
    property real displayPosition: Players.active?.position ?? 0
    property string displayedTitle: Players.active?.trackTitle || qsTr("Nothing playing")
    property string displayedArtist: Players.active?.trackArtist || qsTr("Choose a song to begin")
    property url ambientCacheSource: ""
    property string ambientCacheRequest: ""
    property string ambientCachePath: ""
    property string ambientCacheFinalPath: ""
    property url coverCacheSource: ""
    property bool nativeBackdropReady: false

    function formatTime(value: real): string {
        const seconds = Math.max(0, Math.floor(value || 0));
        return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
    }

    function scheduleMetadataSwap(): void {
        if (root.active && root.renderContent)
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

    function requestAmbientCache(): void {
        if (!root.active || !root.renderBackdrop || (!HighResArtwork.source && !HighResArtwork.trackKey) || root.width < 320 || root.height < 240)
            return;
        const identity = HighResArtwork.source || `track:${HighResArtwork.trackKey}`;
        const request = `${identity}\n${Math.round(root.width)}x${Math.round(root.height)}`;
        if (request === root.ambientCacheRequest && (ambientCache.running || root.ambientCacheSource !== ""))
            return;
        root.ambientCacheRequest = request;
        root.ambientCacheSource = "";
        root.ambientCachePath = "";
        root.ambientCacheFinalPath = "";
        root.coverCacheSource = "";
        root.nativeBackdropReady = false;
        if (nativeBackdrop.running)
            nativeBackdrop.running = false;
        if (ambientCache.running)
            ambientCache.running = false;
        ambientCache.request = request;
        ambientCache.command = ["nice", "-n", "15", "ionice", "-c", "3", "caelestia-immersive-art-cache", String(HighResArtwork.source), String(Math.round(root.width)), String(Math.round(root.height)), String(HighResArtwork.trackKey)];
        ambientCache.running = true;
    }

    focus: renderContent
    opacity: active ? 1 : 0
    Keys.onEscapePressed: root.exitRequested()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_I && (event.modifiers & Qt.AltModifier)) {
            root.exitRequested();
            event.accepted = true;
        }
    }

    onActiveChanged: {
        if (active && renderContent) {
            root.displayPosition = Players.active?.position ?? 0;
            forceActiveFocus();
            ambientCacheDelay.restart();
        } else if (!active) {
            nativeHandoffDelay.stop();
            root.nativeBackdropReady = false;
            if (nativeBackdrop.running)
                nativeStopDelay.restart();
        }
    }
    onWidthChanged: ambientCacheDelay.restart()
    onHeightChanged: ambientCacheDelay.restart()

    Behavior on opacity {
        NumberAnimation {
            duration: 420
            easing.type: Easing.InOutCubic
        }
    }

    Timer {
        interval: 100
        running: root.active && root.renderContent && (Players.active?.isPlaying ?? false)
        repeat: true
        onTriggered: root.displayPosition = Players.active?.position ?? root.displayPosition
    }

    Timer {
        id: metadataDelay

        interval: 300
        repeat: false
        onTriggered: metadataSwap.restart()
    }

    Timer {
        id: ambientCacheDelay

        interval: 120
        repeat: false
        onTriggered: root.requestAmbientCache()
    }

    Process {
        id: ambientCache

        property string request: ""

        stdout: StdioCollector {
            id: ambientCacheOutput
        }
        onExited: code => {
            if (code !== 0 || request !== root.ambientCacheRequest)
                return;
            const fields = ambientCacheOutput.text.trim().split("\t");
            if (fields.length < 4)
                return;
            root.ambientCacheFinalPath = fields[1];
            root.ambientCachePath = fields[3];
            root.coverCacheSource = `file://${fields[2]}`;
            if (fields[0] === "hit")
                root.ambientCacheSource = `file://${fields[1]}`;
            else
                ambientCaptureDelay.restart();
            if (fields[0] === "hit")
                nativeBackdropDelay.restart();
        }
    }

    Timer {
        id: ambientCaptureDelay

        interval: 760
        repeat: false
        onTriggered: {
            if (!root.active || !root.ambientCachePath || !ambientLive.item)
                return;
            if ((ambientLive.item.imageStatus ?? Image.Null) !== Image.Ready) {
                restart();
                return;
            }
            const request = root.ambientCacheRequest;
            ambientLive.item.grabToImage(result => {
                if (!root.active || request !== root.ambientCacheRequest)
                    return;
                if (result.saveToFile(root.ambientCachePath)) {
                    ambientFinalize.request = request;
                    ambientFinalize.command = ["nice", "-n", "15", "ionice", "-c", "3", "caelestia-immersive-art-cache", "--finalize", root.ambientCachePath, root.ambientCacheFinalPath];
                    ambientFinalize.running = true;
                } else {
                    ambientCaptureDelay.restart();
                }
            });
        }
    }

    Process {
        id: ambientFinalize

        property string request: ""

        stdout: StdioCollector {
            id: ambientFinalizeOutput
        }
        onExited: code => {
            if (code !== 0 || request !== root.ambientCacheRequest)
                return;
            const path = ambientFinalizeOutput.text.trim();
            if (path)
                root.ambientCacheSource = `file://${path}`;
            if (path)
                nativeBackdropDelay.restart();
        }
    }

    Timer {
        id: nativeBackdropDelay

        interval: 80
        repeat: false
        onTriggered: {
            const screenName = (QsWindow.window as QsWindow)?.screen?.name ?? "";
            if (!root.active || !root.ambientCacheFinalPath || !screenName)
                return;
            root.nativeBackdropReady = false;
            nativeBackdrop.command = ["caelestia-immersive-static-layer-launch",
                root.ambientCacheFinalPath, screenName];
            nativeBackdrop.running = true;
        }
    }

    Process {
        id: nativeBackdrop

        stdout: SplitParser {
            onRead: data => {
                if (String(data).trim() === "ready")
                    nativeHandoffDelay.restart();
            }
        }
        onExited: {
            root.nativeBackdropReady = false;
            if (root.active && root.ambientCacheFinalPath)
                nativeBackdropDelay.restart();
        }
    }

    Timer {
        id: nativeHandoffDelay

        // Keep process creation and layer mapping outside the original entry
        // animations. The cached frame is pixel-identical, so the later swap
        // is invisible but avoids disturbing their frame pacing.
        interval: 620
        repeat: false
        onTriggered: {
            if (root.active && nativeBackdrop.running)
                root.nativeBackdropReady = true;
        }
    }

    Timer {
        id: nativeStopDelay

        // Give the Qt backdrop one frame to reappear before removing the
        // native layer, then let the existing opacity animation fade it out.
        interval: 34
        repeat: false
        onTriggered: {
            if (nativeBackdrop.running)
                nativeBackdrop.running = false;
        }
    }

    Connections {
        target: HighResArtwork

        function onSourceChanged(): void {
            ambientCacheDelay.restart();
        }
        function onTrackKeyChanged(): void {
            ambientCacheDelay.restart();
        }
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
            if (root.renderContent)
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
        visible: root.renderBackdrop && !root.nativeBackdropReady
    }

    Item {
        id: ambientLayer

        anchors.fill: parent
        visible: root.renderBackdrop && !root.nativeBackdropReady
        scale: root.active ? 1.045 : 1.14

        Behavior on scale {
            NumberAnimation {
                duration: 520
                easing.type: Easing.InOutCubic
            }
        }

        Loader {
            id: ambientLive

            anchors.fill: parent
            active: root.renderBackdrop && ambientFrozen.status !== Image.Ready
            sourceComponent: Item {
                property alias imageStatus: ambientArt.status

                FadeImage {
                    id: ambientArt

                    anchors.fill: parent
                    source: root.coverCacheSource || HighResArtwork.source
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blur: 1
                        blurMax: 96
                        saturation: 0.82
                    }
                    onStatusChanged: {
                        if (status === Image.Ready && root.ambientCachePath && root.ambientCacheSource === "")
                            ambientCaptureDelay.restart();
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: HighResArtwork.source ? Qt.rgba(0.018, 0.022, 0.03, 0.64) : "#11151b"
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { color: Qt.rgba(0.015, 0.02, 0.028, 0.13); position: 0 }
                        GradientStop { color: Qt.rgba(0.015, 0.02, 0.028, root.landscape ? 0.34 : 0.2); position: 0.5 }
                        GradientStop { color: Qt.rgba(0.015, 0.02, 0.028, 0.62); position: 1 }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { color: Qt.rgba(0.01, 0.014, 0.02, 0.18); position: 0 }
                        GradientStop { color: "transparent"; position: 0.52 }
                        GradientStop { color: Qt.rgba(0.01, 0.014, 0.02, 0.48); position: 1 }
                    }
                }
            }
        }

        Image {
            id: ambientFrozen

            anchors.fill: parent
            visible: root.renderBackdrop
            source: root.ambientCacheSource
            fillMode: Image.Stretch
            asynchronous: true
            cache: false
        }
    }

    Item {
        id: artPane

        x: (root.landscape ? root.width * 0.055 : root.width * 0.08) + (root.active ? 0 : -48)
        y: root.landscape ? root.height * 0.07 : root.height * 0.045
        width: root.landscape ? root.width * 0.41 : root.width * 0.84
        height: root.landscape ? root.height * 0.86 : root.height * 0.4
        opacity: root.active && root.renderContent ? 1 : 0
        visible: root.renderContent
        scale: root.active ? 1 : 0.94

        Behavior on x {
            NumberAnimation {
                duration: 420
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 420
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 420
                easing.type: Easing.InOutCubic
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
                    source: root.coverCacheSource || HighResArtwork.source
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
        opacity: root.active && root.renderContent && !HighResArtwork.transitioning ? 1 : 0
        visible: root.renderContent

        ImmersiveLyricList {
            anchors.fill: parent
            active: root.active && root.renderContent
        }

        Behavior on x {
            NumberAnimation {
                duration: 420
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 420
                easing.type: Easing.InOutCubic
            }
        }
    }
}
