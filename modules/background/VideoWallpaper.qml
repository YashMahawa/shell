import QtQuick
import QtMultimedia

Item {
    id: root

    property url videoSource
    property bool autoStart: true
    readonly property bool ready: player.mediaStatus === MediaPlayer.LoadedMedia
        || player.mediaStatus === MediaPlayer.BufferedMedia
        || player.mediaStatus === MediaPlayer.BufferingMedia
    property int lastPosition: -1
    property int stalledTicks: 0

    function play(): void {
        if (videoSource.toString())
            player.play();
    }

    function pause(): void {
        player.pause();
    }

    function restartPlayback(): void {
        const source = videoSource;
        if (!autoStart || !source.toString())
            return;

        lastPosition = -1;
        stalledTicks = 0;
        player.stop();
        player.source = "";
        player.source = source;
        player.play();
    }

    function loadSource(): void {
        lastPosition = -1;
        stalledTicks = 0;
        player.stop();
        player.source = videoSource;
        if (autoStart && videoSource.toString())
            player.play();
    }

    anchors.fill: parent

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    AudioOutput {
        id: muted
        muted: true
        volume: 0
    }

    MediaPlayer {
        id: player
        videoOutput: output
        audioOutput: muted
        loops: MediaPlayer.Infinite

        onMediaStatusChanged: {
            if (root.autoStart
                    && (mediaStatus === MediaPlayer.LoadedMedia
                        || mediaStatus === MediaPlayer.BufferedMedia)
                    && playbackState !== MediaPlayer.PlayingState)
                play();
        }

        onErrorOccurred: (error, message) => {
            if (error !== MediaPlayer.NoError)
                console.warn("Video wallpaper:", message);
        }
    }

    Timer {
        running: root.autoStart && root.videoSource.toString() !== ""
        repeat: true
        interval: 1000

        onTriggered: {
            if (!root.ready) {
                root.lastPosition = -1;
                root.stalledTicks = 0;
                return;
            }

            const position = player.position;
            if (player.playbackState !== MediaPlayer.PlayingState
                    || (root.lastPosition >= 0 && position <= root.lastPosition))
                root.stalledTicks++;
            else
                root.stalledTicks = 0;

            root.lastPosition = position;
            if (root.stalledTicks >= 3)
                root.restartPlayback();
        }
    }

    onAutoStartChanged: {
        lastPosition = -1;
        stalledTicks = 0;
        if (autoStart)
            restartPlayback();
        else
            pause();
    }

    onVideoSourceChanged: loadSource()
}
