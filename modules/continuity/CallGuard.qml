pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// KDE Connect's pausemusic plugin performs synchronous MPRIS D-Bus calls.
// This guard pauses from inside the shell instead, without sending anything
// back to Android or attempting to control the phone call.
Scope {
    id: root

    property var handled: ({})

    function textFor(notif: var): string {
        return `${notif?.appName ?? ""} ${notif?.summary ?? ""} ${notif?.body ?? ""}`.toLowerCase();
    }

    function isIncomingCall(notif: var): bool {
        const text = textFor(notif);
        return (text.includes("kde connect") || text.includes("t2 5g"))
            && (text.includes("incoming call") || text.includes("is calling"));
    }

    function inspect(): void {
        for (const notif of Notifs.notClosed) {
            if (!notif || handled[String(notif.id)] || !isIncomingCall(notif))
                continue;
            handled[String(notif.id)] = true;
            const player = Players.active;
            if (player?.isPlaying && player.canPause) {
                player.pause();
                Toaster.toast(qsTr("Incoming call"), qsTr("Media paused safely; use the media control to resume after the call"), "phone_in_talk");
            }
        }
    }

    Component.onCompleted: {
        // Do not react to restored notification history from an earlier shell run.
        for (const notif of Notifs.notClosed)
            if (notif)
                handled[String(notif.id)] = true;
    }

    Connections {
        target: Notifs
        function onListChanged(): void { root.inspect(); }
    }
}
