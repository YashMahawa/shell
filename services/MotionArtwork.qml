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
//
// `phase` describes the current track: "looking" while the catalogue is
// searched, "downloading" once a clip is known to exist, then "ready" or
// "none". Consumers use it to wait for the clip instead of flashing the still
// cover first.
Singleton {
    id: root

    property string videoPath: ""
    property string resolvedKey: ""
    property string phaseKey: ""
    property string phaseValue: "looking"
    property string pendingKey: ""
    // Apple Music's own high-resolution still artwork for the matched release.
    property string artPath: ""
    property string artKey: ""
    property bool lookupSlow: false

    readonly property string trackKey: {
        const player = Players.active;
        const artist = player?.trackArtist || "";
        const title = player?.trackTitle || "";
        return artist && title ? `${artist}\n${title}\n${player?.trackAlbum || ""}` : "";
    }
    readonly property string source: resolvedKey === trackKey && videoPath ? `file://${videoPath}` : ""
    readonly property string phase: !trackKey ? "none" : phaseKey === trackKey ? phaseValue : "looking"
    readonly property string artSource: artKey === trackKey && artPath ? `file://${artPath}` : ""
    // True once the Apple lookup for this track has answered (or is too slow
    // to wait for), so covers can commit without a later swap.
    readonly property bool artDecided: !trackKey || artSource !== "" || phase !== "looking" || lookupSlow

    function _title(): string {
        return String(Players.active?.trackTitle || "")
            .replace(/\s*[\[(](official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er|mv)[^\])]*[\])]/ig, "")
            .trim();
    }

    function _setPhase(key: string, value: string): void {
        phaseKey = key;
        phaseValue = value;
    }

    onTrackKeyChanged: {
        lookupSlow = false;
        slowTimer.restart();
        lookupDelay.restart();
    }

    Timer {
        id: slowTimer

        interval: 4500
        onTriggered: root.lookupSlow = true
    }

    Timer {
        id: lookupDelay

        // Browsers publish title and artist a moment apart on track changes.
        interval: 350
        repeat: false
        onTriggered: {
            const key = root.trackKey;
            if (!key)
                return;
            if (key === root.resolvedKey && root.artKey === key) {
                root._setPhase(key, root.videoPath ? "ready" : "none");
                return;
            }
            if (lookup.running) {
                root.pendingKey = key;
                return;
            }
            root.pendingKey = "";
            root._setPhase(key, "looking");
            lookup.key = key;
            lookup.command = ["nice", "-n", "10", "caelestia-motion-art",
                "--title", root._title(),
                "--artist", Players.active?.trackArtist || "",
                "--album", Players.active?.trackAlbum || ""];
            lookup.running = true;
        }
    }

    Process {
        id: lookup

        property string key: ""

        stdout: SplitParser {
            onRead: line => {
                let result = null;
                try {
                    result = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (result.art) {
                    root.artPath = result.art;
                    root.artKey = lookup.key;
                }
                if (result.status === "art") {
                    return;
                } else if (result.status === "found") {
                    root._setPhase(lookup.key, "downloading");
                } else if (result.status === "ok" && result.path) {
                    root.videoPath = result.path;
                    root.resolvedKey = lookup.key;
                    root._setPhase(lookup.key, "ready");
                } else if (result.status === "none") {
                    root.videoPath = "";
                    root.resolvedKey = lookup.key;
                    root._setPhase(lookup.key, "none");
                } else {
                    // Transient failure: show the still cover, retry next play.
                    root._setPhase(lookup.key, "none");
                }
            }
        }
        onExited: {
            if (root.phaseKey === key && (root.phaseValue === "looking" || root.phaseValue === "downloading"))
                root._setPhase(key, "none");
            if (root.pendingKey)
                lookupDelay.restart();
        }
    }
}
