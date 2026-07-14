pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import qs.utils

Singleton {
    id: root

    property string resolvedUrl: ""
    property string resolvedKey: ""
    property int requestId: 0
    property bool loading: false

    readonly property string fallbackUrl: Players.getArtUrl(Players.active)
    readonly property string source: resolvedUrl || fallbackUrl
    readonly property string trackKey: {
        const player = Players.active;
        return player ? `${player.trackArtist || ""}\n${player.trackTitle || ""}` : "";
    }

    onTrackKeyChanged: refreshDelay.restart()

    function _normalise(value: string): string {
        return String(value || "")
            .toLocaleLowerCase()
            .replace(/\s*[\[(].*?[\])]/g, "")
            .replace(/\b(feat|ft)\.?\s+.*$/g, "")
            .replace(/[^\p{L}\p{N}]+/gu, " ")
            .trim();
    }

    function _score(candidate: var, title: string, artist: string): int {
        const candidateTitle = _normalise(candidate?.trackName || "");
        const candidateArtist = _normalise(candidate?.artistName || "");
        let score = 0;
        if (candidateTitle === title)
            score += 8;
        else if (candidateTitle.includes(title) || title.includes(candidateTitle))
            score += 3;
        if (candidateArtist === artist)
            score += 6;
        else if (candidateArtist.includes(artist) || artist.includes(candidateArtist))
            score += 2;
        return score;
    }

    function _largeArtwork(url: string): string {
        if (!url)
            return "";
        return url.replace(/\/[0-9]+x[0-9]+bb\.(jpg|png)$/i, "/1600x1600bb.$1");
    }

    function refresh(): void {
        const player = Players.active;
        const title = _normalise(player?.trackTitle || "");
        const artist = _normalise(player?.trackArtist || "");
        const key = root.trackKey;
        const req = ++root.requestId;

        root.resolvedUrl = "";
        root.resolvedKey = "";
        root.loading = !!title && !!artist;
        if (!root.loading)
            return;

        const query = encodeURIComponent(`${player.trackArtist} ${player.trackTitle}`);
        const url = `https://itunes.apple.com/search?term=${query}&entity=song&limit=8`;
        Requests.get(url, text => {
            if (req !== root.requestId || key !== root.trackKey)
                return;
            try {
                const response = JSON.parse(text);
                let best = null;
                let bestScore = -1;
                for (const candidate of response.results || []) {
                    const score = root._score(candidate, title, artist);
                    if (score > bestScore) {
                        best = candidate;
                        bestScore = score;
                    }
                }
                if (best && bestScore >= 8) {
                    root.resolvedUrl = root._largeArtwork(best.artworkUrl100 || "");
                    root.resolvedKey = key;
                }
            } catch (error) {
                root.resolvedUrl = "";
            }
            root.loading = false;
        }, () => {
            if (req === root.requestId)
                root.loading = false;
        }, {}, 7000);
    }

    Timer {
        id: refreshDelay

        interval: 180
        repeat: false
        onTriggered: root.refresh()
    }

    Connections {
        target: Players
        function onActiveChanged(): void {
            refreshDelay.restart();
        }
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true

        function onPostTrackChanged(): void {
            refreshDelay.restart();
        }
        function onTrackTitleChanged(): void {
            refreshDelay.restart();
        }
        function onTrackArtistChanged(): void {
            refreshDelay.restart();
        }
    }

    Component.onCompleted: refreshDelay.start()
}
