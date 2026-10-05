pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Filters browser logos out of MPRIS artwork.
//
// Chrome and Chromium publish their own logo as the track artwork whenever a
// page briefly has none, typically between songs, which flashes a Chrome icon
// in every cover. Local artwork files from browsers are checked once with
// caelestia-art-guard (a perceptual match against installed browser icons)
// and only shown once they are known to be real artwork.
Singleton {
    id: root

    property var verdicts: ({})
    property int revision: 0
    property var queue: []

    function needsCheck(url: string): bool {
        return /^file:\/\/\/tmp\/\.(com\.google\.Chrome|org\.chromium\.Chromium|com\.brave\.Browser|com\.microsoft\.Edge)\./.test(url || "");
    }

    // The URL if it is safe to show; "" while unchecked or if it is a logo.
    function filter(url: string): string {
        revision; // reactive: re-evaluate once a verdict arrives
        if (!needsCheck(url))
            return url || "";
        const verdict = verdicts[url];
        if (verdict === "ok")
            return url;
        if (verdict === undefined)
            Qt.callLater(() => root.request(url));
        return "";
    }

    function request(url: string): void {
        if (verdicts[url] !== undefined || queue.includes(url) || check.url === url)
            return;
        queue = queue.concat([url]);
        next();
    }

    function next(): void {
        if (check.running || !queue.length)
            return;
        const url = queue[0];
        queue = queue.slice(1);
        check.url = url;
        check.command = ["caelestia-art-guard", url];
        check.running = true;
    }

    Process {
        id: check

        property string url: ""

        stdout: StdioCollector {
            id: output
        }
        onExited: {
            const verdicts = Object.assign({}, root.verdicts);
            verdicts[url] = output.text.trim() === "placeholder" ? "placeholder" : "ok";
            // Chrome reuses a handful of temp names; keep the map small.
            const keys = Object.keys(verdicts);
            if (keys.length > 200)
                delete verdicts[keys[0]];
            root.verdicts = verdicts;
            root.revision++;
            url = "";
            root.next();
        }
    }
}
