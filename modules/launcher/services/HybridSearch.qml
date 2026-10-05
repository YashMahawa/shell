pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property string text: ""
    property var appResults: []
    property var fileResults: []
    property var results: []
    property bool pending

    function merge(): void {
        const appLimit = text.length < 2 ? 10 : 4;
        const apps = appResults.slice(0, appLimit);
        const files = fileResults.slice(0, Math.max(0, 10 - apps.length));
        const remaining = Math.max(0, 10 - apps.length - files.length);
        results = [...apps, ...files, ...appResults.slice(appLimit, appLimit + remaining)];
    }

    function query(value: string): void {
        text = value;
        appResults = Apps.search(value).slice(0, 10).map(app => ({
            kind: "app",
            name: app.name,
            subtitle: app.comment || app.genericName || app.name,
            icon: app.icon,
            app: app
        }));
        fileResults = [];
        merge();
        debounce.restart();
    }

    // Called when the launcher opens: starts the query server (a no-op when
    // it is already running) so the model is loaded before the user types.
    function warm(): void {
        if (!warmProcess.running)
            warmProcess.running = true;
    }

    function launchQuery(): void {
        if (text.trim().length < 2)
            return;
        // Talk to the query server directly; the per-query Python client is
        // only a fallback (it also handles the ultra power lexical mode).
        if (!socketFailed && !UltraPower.active) {
            querySocket.requested = text;
            querySocket.payload = JSON.stringify({ query: text, count: 10 }) + "\n";
            if (querySocket.connected)
                querySocket.connected = false; // abandon a superseded query
            querySocket.connected = true;
            return;
        }
        if (searchProcess.running) {
            pending = true;
            return;
        }
        pending = false;
        searchProcess.requested = text;
        searchProcess.command = [Quickshell.env("HOME") + "/.local/bin/caelestia-semantic-query", text, "-n", "10"];
        searchProcess.running = true;
    }

    function accept(requested: string, output: string): void {
        if (requested !== root.text)
            return;
        try {
            const parsed = JSON.parse(output);
            if (!Array.isArray(parsed))
                return;
            root.fileResults = parsed.map(item => ({
                kind: item.kind === "folder" ? "folder" : "file",
                name: item.name,
                subtitle: item.parent,
                path: item.path,
                mime: item.mime,
                score: item.score
            }));
            root.merge();
        } catch (error) {
            console.warn("HybridSearch: invalid semantic result", error);
        }
    }

    property bool socketFailed: false

    Timer {
        id: debounce
        interval: 160
        onTriggered: root.launchQuery()
    }

    Socket {
        id: querySocket

        property string requested: ""
        property string payload: ""

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/caelestia-semantic-search.sock`
        parser: SplitParser {
            onRead: data => {
                root.accept(querySocket.requested, data);
                querySocket.connected = false;
            }
        }
        onConnectionStateChanged: {
            if (connected && payload) {
                write(payload);
                flush();
                payload = "";
            }
        }
        onError: {
            // Server not running (or in lexical-only mode): start it and use
            // the Python client for this query and the next few seconds.
            root.socketFailed = true;
            root.warm();
            socketRetry.restart();
            Qt.callLater(root.launchQuery);
        }
    }

    Timer {
        id: socketRetry

        interval: 4000
        onTriggered: root.socketFailed = false
    }

    Process {
        id: warmProcess

        command: ["systemctl", "--user", "start", "caelestia-semantic-query.service"]
    }

    Process {
        id: searchProcess
        property string requested: ""

        stdout: StdioCollector {
            onStreamFinished: root.accept(searchProcess.requested, text)
        }

        onRunningChanged: {
            if (!running && root.pending)
                Qt.callLater(root.launchQuery);
        }
    }
}
