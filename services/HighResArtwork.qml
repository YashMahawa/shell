pragma Singleton

import QtQuick
import Quickshell
import Caelestia
import qs.utils

Singleton {
    id: root

    property string resolvedUrl: ""
    property string resolvedKey: ""
    property string artworkBaseUrl: ""
    property int requestId: 0
    property int requestedSize: 1200
    property bool loading: false
    property bool transitioning: false
    property int revision: 0

    readonly property string fallbackUrl: Players.getArtUrl(Players.active)
    readonly property string source: resolvedUrl || (_usableArtwork(fallbackUrl) ? fallbackUrl : "")
    readonly property string trackKey: {
        const player = Players.active;
        const artist = player?.trackArtist || "";
        const title = player?.trackTitle || "";
        return artist || title ? `${artist}\n${title}` : "";
    }

    onTrackKeyChanged: beginTransition()

    function requestSize(pixels: real): void {
        const wanted = Math.max(1000, Math.min(2400, Math.ceil(Number(pixels || root.requestedSize) / 200) * 200));
        if (wanted === root.requestedSize)
            return;
        root.requestedSize = wanted;
        if (root.artworkBaseUrl && root.resolvedKey === root.trackKey)
            root.resolvedUrl = root._sizedArtwork(root.artworkBaseUrl, wanted);
    }

    function beginTransition(): void {
        root.transitioning = !!root.trackKey;
        refreshDelay.restart();
        fallbackDelay.restart();
        transitionTimeout.restart();
    }

    function _usableArtwork(url: string): bool {
        const value = String(url || "").toLocaleLowerCase();
        if (!value)
            return false;
        return !/(^|[\/_-])(chrome|chromium|firefox|browser)([\/_\-.]|$)/.test(value)
            && !/(application-x-executable|application-default-icon|web-browser)/.test(value);
    }

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

    function _sizedArtwork(url: string, size: int): string {
        if (!url)
            return "";
        return url.replace(/\/[0-9]+x[0-9]+bb\.(jpg|png)$/i, `/${size}x${size}bb.$1`);
    }

    function _acceptArtwork(url: string, key: string): void {
        if (!root._usableArtwork(url) || key !== root.trackKey)
            return;
        root.resolvedUrl = url;
        root.resolvedKey = key;
        root.transitioning = false;
        root.revision++;
        transitionTimeout.stop();
    }

    function _acceptFallback(): void {
        if (!root.transitioning || !root.trackKey)
            return;
        if (root._usableArtwork(root.fallbackUrl) && root.fallbackUrl !== root.resolvedUrl)
            root._acceptArtwork(root.fallbackUrl, root.trackKey);
    }

    function refresh(): void {
        const player = Players.active;
        const title = _normalise(player?.trackTitle || "");
        const artist = _normalise(player?.trackArtist || "");
        const key = root.trackKey;
        const req = ++root.requestId;

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
                    root.artworkBaseUrl = best.artworkUrl100 || "";
                    root._acceptArtwork(root._sizedArtwork(root.artworkBaseUrl, root.requestedSize), key);
                } else {
                    root._acceptFallback();
                }
            } catch (error) {
                root._acceptFallback();
            }
            root.loading = false;
        }, () => {
            if (req !== root.requestId)
                return;
            root.loading = false;
            root._acceptFallback();
        }, {}, 7000);
    }

    Timer {
        id: refreshDelay

        interval: 260
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: fallbackDelay

        interval: 1300
        repeat: false
        onTriggered: root._acceptFallback()
    }

    Timer {
        id: transitionTimeout

        interval: 2800
        repeat: false
        onTriggered: root.transitioning = false
    }

    Connections {
        target: Players
        function onActiveChanged(): void {
            root.beginTransition();
        }
    }

    Connections {
        target: Players.active
        ignoreUnknownSignals: true

        function onPostTrackChanged(): void {
            root.beginTransition();
        }
        function onTrackTitleChanged(): void {
            root.beginTransition();
        }
        function onTrackArtistChanged(): void {
            root.beginTransition();
        }
        function onTrackArtUrlChanged(): void {
            if (root.transitioning)
                fallbackDelay.restart();
        }
    }

    Component.onCompleted: beginTransition()
}
