pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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

    function launchQuery(): void {
        if (text.trim().length < 2)
            return;
        if (searchProcess.running) {
            pending = true;
            return;
        }
        pending = false;
        searchProcess.requested = text;
        searchProcess.command = ["/home/yash/.local/bin/caelestia-semantic-query", text, "-n", "10"];
        searchProcess.running = true;
    }

    Timer {
        id: debounce
        interval: 320
        onTriggered: root.launchQuery()
    }

    Process {
        id: searchProcess
        property string requested: ""

        stdout: StdioCollector {
            onStreamFinished: {
                if (searchProcess.requested !== root.text)
                    return;
                try {
                    const parsed = JSON.parse(text);
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
        }

        onRunningChanged: {
            if (!running && root.pending)
                Qt.callLater(root.launchQuery);
        }
    }
}
