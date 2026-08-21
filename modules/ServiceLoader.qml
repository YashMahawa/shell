import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Services
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        BluetoothAgent;
        IdleInhibitor;
        GameMode;
        Notifs;
        Players;
        Brightness;
        NightLight;
        Weather.reload();
        CalendarEvents.reload();
        Timetable;
        CalendarCentre;
        Voice;

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
