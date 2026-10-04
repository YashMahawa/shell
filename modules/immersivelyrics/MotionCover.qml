import QtQuick
import QtMultimedia

// Plays an Apple Music motion artwork clip over the still cover. The clip is a
// cached local MP4 decoded by Qt Multimedia (VA-API on Intel), looped silently,
// and only faded in once frames are actually arriving.
Item {
    id: root

    property url source
    property bool playing: true
    readonly property bool showing: shown

    property bool shown: false

    function sync(): void {
        if (root.playing && root.source.toString())
            player.play();
        else
            player.pause();
    }

    onPlayingChanged: sync()
    onSourceChanged: {
        shown = false;
        player.stop();
        player.source = source;
        sync();
    }

    MediaPlayer {
        id: player

        loops: MediaPlayer.Infinite
        videoOutput: output
        onPositionChanged: {
            if (position > 80 && !root.shown)
                root.shown = true;
        }
        onErrorOccurred: (error, message) => {
            if (error !== MediaPlayer.NoError)
                root.shown = false;
        }
    }

    VideoOutput {
        id: output

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 700
                easing.type: Easing.InOutSine
            }
        }
    }
}
