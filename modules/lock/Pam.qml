import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Caelestia.Config

Scope {
    id: root

    required property WlSessionLock lock

    readonly property alias passwd: passwd
    readonly property alias fprint: fprint
    property string lockMessage
    property var classifiedMessage: null
    property string state
    property string fprintState
    property string buffer

    signal flashMsg

    function parsePamMessage(msg) {
        if (!msg) return null;

        // Strip pam module prefixes if present
        let clean = msg.replace(/^pam_\w+\([^)]+\):\s*/i, "").trim();

        // Check for lockout
        const lockoutMatch = clean.match(/(\d+)\s*(?:seconds|sec|sekunden|secondes|segundos|s)\s*(?:left|remaining|verbleibend|restantes)?\s*(?:to unlock)?/i)
            || clean.match(/(\d+)\s*(?:seconds|sec|sekunden|secondes|segundos|s)?\s*(?:left|remaining|verbleibend|restantes)\s*(?:to unlock)?/i)
            || clean.match(/(?:locked|gesperrt|verrouillé|bloqueado)\s*(?:for|für|pendant|por)?\s*(\d+)\s*(?:seconds|sec|sekunden|secondes|segundos|s)?/i);
        if (lockoutMatch && lockoutMatch[1]) {
            const secs = lockoutMatch[1];
            let text = qsTr("Account locked (%1s remaining)").arg(secs);
            return { type: "lockout", text: text, seconds: parseInt(secs, 10), raw: clean };
        }

        if (/account is locked|account locked|kontosperre|compte verrouillé|cuenta bloqueada/i.test(clean)) {
            let text = qsTr("Account locked due to failed attempts.");
            return { type: "lockout", text: text, seconds: null, raw: clean };
        }

        // Check for remaining attempt counts
        const attemptsMatch = clean.match(/(\d+)\s*(?:more\s+)?attempts?\s*(?:remaining|left)/i)
            || clean.match(/(\d+)\s*failed login attempts?/i)
            || clean.match(/(\d+)\s*(?:verbleibende|restant|restantes)\s*(?:versuche|essais|intentos)/i);
        if (attemptsMatch && attemptsMatch[1]) {
            const count = parseInt(attemptsMatch[1], 10);
            let text = qsTr("Incorrect password (%1 attempt%2 remaining)").arg(count).arg(count === 1 ? "" : "s");
            return { type: "attempts", text: text, count: count, raw: clean };
        }

        // Check for standard invalid password / auth failure
        if (/authentication (?:failure|failed)|invalid password|incorrect password|password incorrect|falsches passwort|mot de passe incorrect|contraseña incorrecta/i.test(clean)) {
            return { type: "invalid_creds", text: qsTr("Incorrect password. Please try again."), raw: clean };
        }

        // Fallback sanitized info string to prevent display layout overflow while preserving raw message
        let sanitized = clean.replace(/[\r\n]+/g, " ");
        if (sanitized.length > 80) {
            sanitized = sanitized.substring(0, 77) + "...";
        }
        return { type: "info", text: sanitized, raw: clean };
    }

    function finishUnlock(): void {
        fprint.abort();
        errorRetry.stop();
        stateReset.stop();
        fprintStateReset.stop();
        root.lockMessage = "";
        root.classifiedMessage = null;
        unlockStateProc.running = true;
        root.lock.unlock();
    }

    function handleKey(event: KeyEvent): void {
        if (passwd.active || state === "max")
            return;

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            root.lockMessage = "";
            root.classifiedMessage = null;
            root.state = "";
            passwd.start();
        } else if (event.key === Qt.Key_Backspace) {
            if (event.modifiers & Qt.ControlModifier) {
                buffer = "";
            } else {
                buffer = buffer.slice(0, -1);
            }
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            // Allow anything except control characters
            buffer += event.text;
        }
    }

    PamContext {
        id: passwd

        config: "passwd"
        configDirectory: Quickshell.shellDir + "/assets/pam.d"

        onMessageChanged: {
            if (message) {
                const parsed = root.parsePamMessage(message);
                if (parsed && parsed.type === "lockout") {
                    root.lockMessage = parsed.text;
                }
            }
        }

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;

            root.lockMessage = "";
            root.classifiedMessage = null;
            respond(root.buffer);
            root.buffer = "";
        }

        onCompleted: res => {
            if (res === PamResult.Success)
                return root.finishUnlock();

            const parsed = root.parsePamMessage(passwd.message);
            if (parsed) {
                root.classifiedMessage = parsed;
                if (parsed.type === "lockout") {
                    root.lockMessage = parsed.text;
                }
            }

            if (res === PamResult.Error)
                root.state = "error";
            else if (res === PamResult.MaxTries)
                root.state = "max";
            else if (res === PamResult.Failed)
                root.state = "fail";

            root.flashMsg();
            stateReset.restart();
        }
    }

    PamContext {
        id: fprint

        property bool available
        property int tries

        function checkAvail(): void {
            if (!available || !GlobalConfig.lock.enableFprint || !root.lock.secure) {
                abort();
                return;
            }

            tries = 0;
            start();
        }

        config: "fprint"
        configDirectory: Quickshell.shellDir + "/assets/pam.d"

        onCompleted: res => {
            if (!available)
                return;

            if (res === PamResult.Success)
                return root.finishUnlock();

            if (res === PamResult.Error) {
                root.fprintState = "error";
                abort();
                errorRetry.restart();
            } else if (res === PamResult.MaxTries || res === PamResult.Failed) {
                tries++;
                if (tries < GlobalConfig.lock.maxFprintTries) {
                    root.fprintState = "fail";
                    start();
                } else {
                    root.fprintState = "max";
                    abort();
                }
            }

            root.flashMsg();
            fprintStateReset.start();
        }
    }

    Process {
        id: unlockStateProc

        command: [Quickshell.env("HOME") + "/.local/bin/caelestia-lock-state", "unlocked"]
    }

    Process {
        id: availProc

        command: ["sh", "-c", "fprintd-list $USER"]
        onExited: code => { // qmllint disable signal-handler-parameters
            fprint.available = code === 0;
            fprint.checkAvail();
        }
    }

    Timer {
        id: errorRetry

        interval: 800
        onTriggered: fprint.start()
    }

    Timer {
        id: stateReset

        interval: 1200
        onTriggered: {
            if (root.state !== "max")
                root.state = "";
        }
    }

    Timer {
        id: fprintStateReset

        interval: 4000
        onTriggered: {
            if (fprint.tries < GlobalConfig.lock.maxFprintTries) {
                root.fprintState = "";
            }
        }
    }

    Connections {
        function onSecureChanged(): void {
            if (root.lock.secure) {
                availProc.running = true;
                root.buffer = "";
                root.state = "";
                root.fprintState = "";
                root.lockMessage = "";
                root.classifiedMessage = null;
                fprint.tries = 0;
            } else {
                fprint.abort();
                errorRetry.stop();
                stateReset.stop();
                fprintStateReset.stop();
            }
        }

        function onUnlock(): void {
            fprint.abort();
            errorRetry.stop();
            stateReset.stop();
            fprintStateReset.stop();
        }

        target: root.lock
    }

    Connections {
        function onEnableFprintChanged(): void {
            fprint.checkAvail();
        }

        target: GlobalConfig.lock
    }
}
