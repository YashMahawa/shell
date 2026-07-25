pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia
import Caelestia.Config
import Caelestia.Services

Singleton {
    id: root

    property string previousSinkName: ""
    property string previousSourceName: ""

    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    property list<PwNode> streams: []
    property var profileSinks: []
    property string pendingProfileSink: ""

    property alias safeBluetoothVolumeEnabled: audioPreferences.safeBluetoothVolumeEnabled
    property alias safeBluetoothVolume: audioPreferences.safeBluetoothVolume

    property var bluetoothSinksSeen: ({})
    property var bluetoothSinksPending: ({})
    property int bluetoothSafetyRetries: 0

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0

    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0

    readonly property alias cava: cava
    readonly property alias beatTracker: beatTracker

    function isBluetoothSink(node: PwNode): bool {
        if (!node)
            return false;

        const properties = node.properties ?? {};
        const nodeName = node.name ?? properties["node.name"] ?? "";
        return node.isSink && (nodeName.startsWith("bluez_output.") || properties["device.api"] === "bluez5" || properties["device.bus"] === "bluetooth");
    }

    function bluetoothSinkKey(node: PwNode): string {
        return node?.name ?? node?.properties?.["node.name"] ?? String(node?.id ?? "");
    }

    function setSafeBluetoothVolumeEnabled(enabled: bool): void {
        audioPreferences.safeBluetoothVolumeEnabled = enabled;

        if (!enabled) {
            bluetoothSafetyTimer.stop();
            root.bluetoothSinksPending = ({});

            const seen = ({});
            for (const node of root.sinks) {
                if (root.isBluetoothSink(node))
                    seen[root.bluetoothSinkKey(node)] = true;
            }
            root.bluetoothSinksSeen = seen;
        }
    }

    function syncBluetoothSafety(sinkNodes): void {
        const present = ({});
        let queued = false;

        for (const node of sinkNodes) {
            if (!root.isBluetoothSink(node))
                continue;

            const key = root.bluetoothSinkKey(node);
            present[key] = true;
            if (root.bluetoothSinksSeen[key] || root.bluetoothSinksPending[key])
                continue;

            if (audioPreferences.safeBluetoothVolumeEnabled) {
                root.bluetoothSinksPending[key] = true;
                queued = true;
            } else {
                root.bluetoothSinksSeen[key] = true;
            }
        }

        for (const key of Object.keys(root.bluetoothSinksSeen)) {
            if (!present[key])
                delete root.bluetoothSinksSeen[key];
        }
        for (const key of Object.keys(root.bluetoothSinksPending)) {
            if (!present[key])
                delete root.bluetoothSinksPending[key];
        }

        if (queued) {
            root.bluetoothSafetyRetries = 0;
            bluetoothSafetyTimer.restart();
        }
    }

    function applyPendingBluetoothSafety(): void {
        let retry = false;

        for (const node of root.sinks) {
            if (!root.isBluetoothSink(node))
                continue;

            const key = root.bluetoothSinkKey(node);
            if (!root.bluetoothSinksPending[key])
                continue;

            if (node.ready && node.audio) {
                node.audio.volume = Math.max(0, Math.min(1, audioPreferences.safeBluetoothVolume));
                root.bluetoothSinksSeen[key] = true;
                delete root.bluetoothSinksPending[key];
            } else {
                retry = true;
            }
        }

        root.bluetoothSafetyRetries++;
        if (retry && root.bluetoothSafetyRetries < 40)
            bluetoothSafetyTimer.restart();
    }

    function setVolume(newVolume: real): void {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementVolume(amount: real): void {
        setVolume(volume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementVolume(amount: real): void {
        setVolume(volume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setSourceVolume(newVolume: real): void {
        if (source?.ready && source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setAudioSink(newSink: PwNode): void {
        Pipewire.preferredDefaultAudioSink = newSink;
    }

    function setAudioSource(newSource: PwNode): void {
        Pipewire.preferredDefaultAudioSource = newSource;
    }

    function setOutputProfile(profile): void {
        if (!profile?.cardName || !profile?.profileName || profileSwitchProc.running)
            return;

        root.pendingProfileSink = profile.matchName ?? profile.description ?? "";
        profileSwitchProc.command = [
            "pactl", "set-card-profile", profile.cardName, profile.profileName
        ];
        profileSwitchProc.running = true;
    }

    function refreshCardProfiles(): void {
        if (!cardProfilesProc.running)
            cardProfilesProc.running = true;
    }

    function cycleNextAudioOutput(): void {
        if (sinks.length === 0)
            return;

        const currentIndex = sinks.findIndex(s => s === sink);
        const nextIndex = (currentIndex + 1) % sinks.length;
        setAudioSink(sinks[nextIndex]);
    }

    function setStreamVolume(stream: PwNode, newVolume: real): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = false;
            stream.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function setStreamMuted(stream: PwNode, muted: bool): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = muted;
        }
    }

    function getStreamVolume(stream: PwNode): real {
        return stream?.audio?.volume ?? 0;
    }

    function getStreamMuted(stream: PwNode): bool {
        return !!stream?.audio?.muted;
    }

    function getStreamName(stream: PwNode): string {
        if (!stream)
            return qsTr("Unknown");
        // Try application name first, then description, then name
        return stream.properties["application.name"] || stream.description || stream.name || qsTr("Unknown Application");
    }

    function refreshNodes(): void {
        const newSinks = [];
        const newSources = [];
        const newStreams = [];

        for (const node of Pipewire.nodes.values) {
            if (!node.isStream) {
                if (node.isSink)
                    newSinks.push(node);
                else if (node.audio)
                    newSources.push(node);
            } else if (node.audio) {
                newStreams.push(node);
            }
        }

        root.sinks = newSinks;
        root.sources = newSources;
        root.streams = newStreams;
        root.syncBluetoothSafety(newSinks);

        if (root.pendingProfileSink) {
            const wanted = root.pendingProfileSink.toLowerCase();
            const activated = newSinks.find(node => {
                const description = (node.description || node.name || "").toLowerCase();
                return description.includes(wanted);
            });
            if (activated) {
                root.setAudioSink(activated);
                root.pendingProfileSink = "";
            }
        }
    }

    onSinkChanged: {
        if (!sink?.ready)
            return;

        const newSinkName = sink.description || sink.name || qsTr("Unknown Device");

        if (previousSinkName && previousSinkName !== newSinkName && GlobalConfig.utilities.toasts.audioOutputChanged)
            Toaster.toast(qsTr("Audio output changed"), qsTr("Now using: %1").arg(newSinkName), "volume_up");

        previousSinkName = newSinkName;
    }

    onSourceChanged: {
        if (!source?.ready)
            return;

        const newSourceName = source.description || source.name || qsTr("Unknown Device");

        if (previousSourceName && previousSourceName !== newSourceName && GlobalConfig.utilities.toasts.audioInputChanged)
            Toaster.toast(qsTr("Audio input changed"), qsTr("Now using: %1").arg(newSourceName), "mic");

        previousSourceName = newSourceName;
    }

    // Populate immediately: Pipewire.nodes may already be filled by the time this
    // lazily-loaded singleton is created, so onValuesChanged would never fire.
    Component.onCompleted: {
        refreshNodes();
        refreshCardProfiles();
        previousSinkName = sink?.description || sink?.name || qsTr("Unknown Device");
        previousSourceName = source?.description || source?.name || qsTr("Unknown Device");
    }

    Connections {
        function onValuesChanged(): void {
            root.refreshNodes();
        }

        target: Pipewire.nodes
    }

    PersistentProperties {
        id: audioPreferences

        property bool safeBluetoothVolumeEnabled: true
        property real safeBluetoothVolume: 0.2

        reloadableId: "audioSafety"
    }

    Timer {
        id: bluetoothSafetyTimer

        interval: 250
        repeat: false
        onTriggered: root.applyPendingBluetoothSafety()
    }

    Timer {
        id: cardRefreshDebounce

        interval: 200
        onTriggered: root.refreshCardProfiles()
    }

    Process {
        id: cardEventProc

        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: cardRefreshDebounce.restart()
        }
    }

    Process {
        id: cardProfilesProc

        command: ["pactl", "--format=json", "list", "cards"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const cards = JSON.parse(text);
                    const choices = [];
                    for (const card of cards) {
                        if (!card.name?.startsWith("alsa_card."))
                            continue;

                        const profiles = card.profiles ?? {};
                        const active = card.active_profile ?? "";
                        const available = name => {
                            const value = profiles[name];
                            return value && value.available !== false && value.available !== "no";
                        };

                        const analog = available("output:analog-stereo+input:analog-stereo")
                            ? "output:analog-stereo+input:analog-stereo"
                            : available("output:analog-stereo") ? "output:analog-stereo" : "";
                        if (analog && active !== analog && !active.startsWith("output:analog-stereo")) {
                            choices.push({
                                isProfile: true,
                                id: `profile:${card.name}:${analog}`,
                                cardName: card.name,
                                profileName: analog,
                                description: qsTr("Built-in Audio Analog Stereo"),
                                matchName: "Built-in Audio Analog Stereo"
                            });
                        }

                        for (const [portName, port] of Object.entries(card.ports ?? {})) {
                            if (!portName.startsWith("hdmi-output-") || port.availability !== "available")
                                continue;
                            const product = port.properties?.["device.product.name"] || port.description || qsTr("HDMI display");
                            const duplex = (port.profiles ?? []).find(name =>
                                name.startsWith("output:hdmi-stereo") && name.includes("+input:") && available(name));
                            const outputOnly = (port.profiles ?? []).find(name =>
                                name.startsWith("output:hdmi-stereo") && !name.includes("+input:") && available(name));
                            const profileName = duplex || outputOnly || "";
                            if (!profileName || active === profileName || active.startsWith(profileName.split("+")[0]))
                                continue;
                            choices.push({
                                isProfile: true,
                                id: `profile:${card.name}:${profileName}`,
                                cardName: card.name,
                                profileName,
                                description: `${product} · HDMI`,
                                matchName: product
                            });
                        }
                    }
                    root.profileSinks = choices;
                } catch (error) {
                    root.profileSinks = [];
                }
            }
        }
    }

    Process {
        id: profileSwitchProc

        onExited: {
            cardRefreshDebounce.restart();
            profileSinkWait.restart();
        }
    }

    Timer {
        id: profileSinkWait

        interval: 350
        onTriggered: {
            root.refreshNodes();
            root.refreshCardProfiles();
        }
    }

    // Always track the current defaults so volume/mute bind even if the lists
    // momentarily lag behind the default node.
    PwObjectTracker {
        objects: [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams].filter(n => n)
    }

    CavaProvider {
        id: cava

        bars: GlobalConfig.services.visualiserBars
    }

    BeatTracker {
        id: beatTracker
    }

    IpcHandler {
        function cycleOutput(): void {
            root.cycleNextAudioOutput();
        }

        target: "audio"
    }
}
