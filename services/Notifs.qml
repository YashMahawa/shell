pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.utils

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => n && !n.closed)
    readonly property list<NotifData> popups: list.filter(n => n && n.popup && !n.closed)
    property alias dnd: props.dnd

    property bool loaded
    readonly property int maxPersisted: 80
    readonly property int maxPersistedBodyChars: 1200

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (monitor?.activeWorkspace?.lastIpcObject?.hasfullscreen)
                return true;
        }
        return false;
    }

    function shouldShowPopup(): bool {
        if (props.dnd || [...Visibilities.screens.values()].some(v => v.sidebar))
            return false;
        if (GlobalConfig.notifs.fullscreen === "off" && hasFullscreen())
            return false;
        return true;
    }

    onDndChanged: {
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(qsTr("Do not disturb enabled"), qsTr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(qsTr("Do not disturb disabled"), qsTr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    function serialiseNotif(n: NotifData): var {
        return {
            time: n.time,
            id: n.id,
            summary: n.summary,
            body: n.body.length > maxPersistedBodyChars ? n.body.slice(0, maxPersistedBodyChars) + "..." : n.body,
            appIcon: n.appIcon,
            appName: n.appName,
            image: n.image,
            expireTimeout: n.expireTimeout,
            urgency: n.urgency,
            resident: n.resident,
            hasActionIcons: n.hasActionIcons,
            actions: n.actions.map(a => ({
                identifier: a.identifier ?? "",
                text: a.text ?? ""
            }))
        };
    }

    function sanitisePersisted(n: var): var {
        return {
            time: n.time,
            id: n.id ?? "",
            summary: n.summary ?? "",
            body: (n.body ?? "").length > maxPersistedBodyChars ? (n.body ?? "").slice(0, maxPersistedBodyChars) + "..." : (n.body ?? ""),
            appIcon: n.appIcon ?? "",
            appName: n.appName ?? "",
            image: n.image ?? "",
            expireTimeout: n.expireTimeout ?? GlobalConfig.notifs.defaultExpireTimeout,
            urgency: n.urgency ?? 1,
            resident: n.resident ?? false,
            hasActionIcons: n.hasActionIcons ?? false,
            actions: []
        };
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.slice(0, root.maxPersisted).filter(n => n).map(n => root.serialiseNotif(n))))
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            const comp = notifComp.createObject(root, {
                popup: root.shouldShowPopup(),
                notification: notif
            });
            root.list = [comp, ...root.list];
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text()).slice(0, root.maxPersisted);
            const loadedNotifs = [];
            for (const notif of data) {
                const comp = notifComp.createObject(root, root.sanitisePersisted(notif));
                if (comp)
                    loadedNotifs.push(comp);
            }
            loadedNotifs.sort((a, b) => b.time - a.time);
            root.list = loadedNotifs;
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    IpcHandler {
        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }

        function isDndEnabled(): bool {
            return props.dnd;
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
