pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.services

Singleton {
    id: root

    readonly property string status: VoiceService.status
    readonly property string message: VoiceService.message
    readonly property string detail: VoiceService.detail
    readonly property bool active: VoiceService.active
    readonly property var storedKeys: VoiceService.storedKeys
    readonly property string prompt: VoiceService.prompt
    readonly property string model: VoiceService.model

    function toggle(): void {
        VoiceService.toggle();
    }

    function start(): void {
        VoiceService.startCapture();
    }

    function stop(): void {
        VoiceService.stopCapture();
    }

    function cancel(): void {
        VoiceService.cancel();
    }

    function storeKey(slot: int, key: string): void {
        VoiceService.storeKey(slot, key);
    }

    function clearKey(slot: int): void {
        VoiceService.clearKey(slot);
    }

    function savePrompt(promptText: string): void {
        VoiceService.savePrompt(promptText);
    }

    function refreshKeys(): void {
        VoiceService.refreshKeys();
    }

    function statusInfo(): var {
        return VoiceService.statusInfo();
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function start(): void {
            root.start();
        }

        function stop(): void {
            root.stop();
        }

        function cancel(): void {
            root.cancel();
        }

        function status(): string {
            return JSON.stringify(root.statusInfo());
        }

        target: "voice"
    }
}
