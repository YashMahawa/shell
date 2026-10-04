pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Apple Music motion artwork (animated album covers) for the active track.
//
// Resolution and download happen in `caelestia-motion-art`, which caches both
// the lookup and the remuxed clip, so a repeat play resolves in well under a
// tenth of a second. Lookups start as soon as a track changes, so the clip is
// usually on disk before the immersive view is opened.
Singleton {
    id: root

    property string videoPath: ""
    property string resolvedKey: ""
    property string pendingKey: ""

    readonly property string trackKey: {
        const player = Players.active;
        const artist = player?.trackArtist || "";
        const title = player?.trackTitle || "";
        return artist && title ? `${artist}\n${title}\n${player?.trackAlbum || ""}` : "";
    }
    readonly property string source: resolvedKey === trackKey && videoPath ? `file://${videoPath}` : ""

    function _title(): string {
        return String(Players.active?.trackTitle || "")
            .replace(/\s*[\[(](official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er|mv)[^\])]*[\])]/ig, "")
            .trim();
    }

    onTrackKeyChanged: lookupDelay.restart()

    Timer {
        id: lookupDelay

        // Browsers publish title and artist a moment apart on track changes.
        interval: 450
        repeat: false
        onTriggered: {
            const key = root.trackKey;
            if (!key || key === root.resolvedKey)
                return;
            if (lookup.running) {
                root.pendingKey = key;
                return;
            }
            root.pendingKey = "";
            lookup.key = key;
            lookup.command = ["nice", "-n", "15", "ionice", "-c", "3", "caelestia-motion-art",
                "--title", root._title(),
                "--artist", Players.active?.trackArtist || "",
                "--album", Players.active?.trackAlbum || ""];
            lookup.running = true;
        }
    }

    Process {
        id: lookup

        property string key: ""

        stdout: StdioCollector {
            id: output
        }
        onExited: {
            try {
                const result = JSON.parse(output.text || "{}");
                if (result.status === "ok" && result.path) {
                    root.videoPath = result.path;
                    root.resolvedKey = key;
                } else if (result.status === "none") {
                    root.videoPath = "";
                    root.resolvedKey = key;
                }
            } catch (e) {
                // Transient failure: leave the key unresolved so it retries.
            }
            if (root.pendingKey)
                lookupDelay.restart();
        }
    }
}
