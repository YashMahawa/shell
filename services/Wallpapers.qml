pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import Caelestia.Services
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear
    property list<QtObject> daemonWalls: []

    function syncDaemonWalls(): void {
        const previous = daemonWalls;
        daemonWalls = [];
        for (const object of previous)
            object.destroy();

        const next = [];
        for (const wall of BackgroundDaemon.wallpapers) {
            if (!wall?.path)
                continue;
            const object = wallpaperObject.createObject(root, {
                path: String(wall.path),
                parentDir: String(wall.parentDir),
                relativePath: String(wall.relativePath),
                name: String(wall.name),
                baseName: String(wall.baseName),
                suffix: String(wall.suffix),
                size: Number(wall.size),
                isImage: true
            });
            if (object)
                next.push(object);
        }
        daemonWalls = next;
    }

    function getCategoryFor(w: var): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        const clean = cleanPath(path);
        actualCurrent = clean;
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", clean, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = cleanPath(path);
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    Component.onCompleted: {
        BackgroundDaemon.startDaemon(Paths.wallsdir);
        syncDaemonWalls();
    }

    list: daemonWalls
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    Connections {
        target: BackgroundDaemon
        function onWallpapersChanged(): void {
            root.syncDaemonWalls();
        }
    }

    Component {
        id: wallpaperObject

        QtObject {
            property string path
            property string parentDir
            property string relativePath
            property string name
            property string baseName
            property string suffix
            property real size
            property bool isImage
        }
    }

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.wallpaperMode = root.isVideo(wall) ? "animated" : "static";
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }

    Process {
        id: thumbnailProc

        command: ["caelestia", "wallpaper", "--extract-thumbs"]
        onExited: {
            root._refreshing = false;
            root.thumbnailVersion = Date.now().toString();
        }
    }
}
