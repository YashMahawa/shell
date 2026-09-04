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
    property var bluetoothCards: ({})
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

    function outputDisplayName(node: PwNode): string {
        if (!node)
            return "";

        const props = node.properties ?? {};
        const name = node.name ?? props["node.name"] ?? "";
        const nick = props["node.nick"] || props["alsa.name"] || "";
        const description = node.description || props["device.description"] || name;
        const path = String(props["api.alsa.path"] || "").toLowerCase();
        const bus = String(props["device.bus"] || "").toLowerCase();

        if (path.startsWith("hdmi:") || name.includes(".hdmi-") || description.toLowerCase().includes("hdmi"))
            return `${nick || description} · HDMI`;
        if (bus === "usb" || name.includes(".usb-"))
            return `${nick || description} · USB`;
        if (isBluetoothSink(node))
            return description;
        return description;
    }

    function isBluetoothSink(node: PwNode): bool {
        if (!node)
            return false;

        const properties = node.properties ?? {};
        const nodeName = node.name ?? properties["node.name"] ?? "";
        return node.isSink && (nodeName.startsWith("bluez_output.") || properties["device.api"] === "bluez5" || properties["device.bus"] === "bluetooth");
    }

    function isBluetoothCard(card): bool {
        if (!card)
            return false;

        const name = card.name ?? "";
        const driver = card.driver ?? "";
        const props = card.properties ?? {};
        return name.startsWith("bluez_card.") || driver.includes("bluez") || props["device.api"] === "bluez5" || props["device.bus"] === "bluetooth";
    }

    function formatBtAddress(rawAddress: string): string {
        if (!rawAddress)
            return "";

        let addr = String(rawAddress).toUpperCase();
        if (addr.startsWith("BLUEZ_CARD."))
            addr = addr.substring(11);
        if (addr.includes("_"))
            addr = addr.replaceAll("_", ":");
        return addr;
    }

    function parseProfileAndCodec(key: string, desc: string, profVal: var): var {
        let group = "";
        let groupName = "";
        let groupIcon = "tune";
        let codecKey = "";
        let codecName = "";

        const lowerKey = (key || "").toLowerCase();

        // Stable profile group classification using PipeWire metadata/keys rather than display strings
        if (lowerKey === "off") {
            group = "off";
            groupName = qsTr("Off");
            groupIcon = "power_off";
        } else if (lowerKey.startsWith("a2dp-sink") || lowerKey.startsWith("a2dp_sink")) {
            group = "a2dp-sink";
            groupName = qsTr("A2DP (High Fidelity)");
            groupIcon = "music_note";
        } else if (lowerKey.startsWith("a2dp-source") || lowerKey.startsWith("a2dp_source")) {
            group = "a2dp-source";
            groupName = qsTr("A2DP Source");
            groupIcon = "graphic_eq";
        } else if (lowerKey.startsWith("headset-head-unit") || lowerKey.startsWith("headset_head_unit") || lowerKey.startsWith("hsp") || lowerKey.startsWith("hfp")) {
            group = "headset-head-unit";
            groupName = qsTr("HSP/HFP (Headset)");
            groupIcon = "call";
        } else if (lowerKey.startsWith("bap-sink") || lowerKey.startsWith("bap_sink")) {
            group = "bap-sink";
            groupName = qsTr("LE Audio (BAP)");
            groupIcon = "hearing";
        } else {
            const parts = lowerKey.split(/[-_]/);
            if (parts.length > 1) {
                group = parts[0];
                groupName = desc || group;
            } else {
                group = lowerKey || "default";
                groupName = desc || key || qsTr("Default");
            }
            groupIcon = "tune";
        }

        // Codec identification based on profile key or PipeWire bluez5.codec metadata
        const metaCodec = profVal?.properties?.["bluez5.codec"] || profVal?.codec || "";
        const codecSource = metaCodec ? String(metaCodec).toLowerCase() : lowerKey;

        if (codecSource.includes("ldac")) {
            codecKey = "ldac";
            codecName = "LDAC";
        } else if (codecSource.includes("aptx_hd") || codecSource.includes("aptx-hd")) {
            codecKey = "aptx_hd";
            codecName = "aptX HD";
        } else if (codecSource.includes("aptx_ll") || codecSource.includes("aptx-ll")) {
            codecKey = "aptx_ll";
            codecName = "aptX LL";
        } else if (codecSource.includes("aptx")) {
            codecKey = "aptx";
            codecName = "aptX";
        } else if (codecSource.includes("aac")) {
            codecKey = "aac";
            codecName = "AAC";
        } else if (codecSource.includes("msbc")) {
            codecKey = "msbc";
            codecName = "mSBC";
        } else if (codecSource.includes("sbc_xq") || codecSource.includes("sbc-xq")) {
            codecKey = "sbc_xq";
            codecName = "SBC-XQ";
        } else if (codecSource.includes("sbc")) {
            codecKey = "sbc";
            codecName = "SBC";
        } else if (codecSource.includes("cvsd")) {
            codecKey = "cvsd";
            codecName = "CVSD";
        } else if (codecSource.includes("lc3_swb") || codecSource.includes("lc3-swb")) {
            codecKey = "lc3_swb";
            codecName = "LC3-SWB";
        } else if (codecSource.includes("lc3")) {
            codecKey = "lc3";
            codecName = "LC3";
        } else if (codecSource.includes("faststream")) {
            codecKey = "faststream";
            codecName = "FastStream";
        } else {
            if (group === "off") {
                codecKey = "off";
                codecName = qsTr("Off");
            } else {
                const parts = lowerKey.split(/[-_]/);
                if (parts.length > 2) {
                    codecKey = parts[parts.length - 1];
                    codecName = codecKey.toUpperCase();
                } else {
                    codecKey = "default";
                    codecName = qsTr("Default");
                }
            }
        }

        return {
            group: group,
            groupName: groupName,
            groupIcon: groupIcon,
            codecKey: codecKey,
            codecName: codecName
        };
    }

    function bluetoothSinkKey(node: PwNode): string {
        return node?.name ?? node?.properties?.["node.name"] ?? String(node?.id ?? "");
    }

    function getBluetoothCardForNode(node: PwNode): var {
        if (!node || !root.isBluetoothSink(node))
            return null;

        const props = node.properties ?? {};
        const devName = props["device.name"] ?? "";
        const cardName = props["card.name"] ?? "";
        const rawAddr = props["bluez5.address"] ?? props["device.string"] ?? node.name ?? "";
        const address = root.formatBtAddress(rawAddr);

        return root.bluetoothCards[devName] ||
               root.bluetoothCards[cardName] ||
               root.bluetoothCards[address] ||
               root.bluetoothCards[node.name] || null;
    }

    function getBluetoothCardForDevice(device: var): var {
        if (!device)
            return null;

        const address = root.formatBtAddress(device.address);
        const cardName = "bluez_card." + (device.address || "").replaceAll(":", "_");

        return root.bluetoothCards[address] ||
               root.bluetoothCards[cardName] ||
               root.bluetoothCards[device.address] || null;
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
        if (!profile?.cardName || !profile?.profileName)
            return;

        root.pendingProfileSink = profile.matchName ?? profile.description ?? "";
        root.setCardProfile(profile.cardName, profile.profileName);
    }

    function setCardProfile(cardName: string, profileKey: string): void {
        if (!cardName || !profileKey || profileSwitchProc.running)
            return;

        profileSwitchProc.command = [
            "pactl", "set-card-profile", cardName, profileKey
        ];
        profileSwitchProc.running = true;

        if (audioPreferences.safeBluetoothVolumeEnabled) {
            for (const node of root.sinks) {
                if (root.isBluetoothSink(node)) {
                    const key = root.bluetoothSinkKey(node);
                    root.bluetoothSinksPending[key] = true;
                }
            }
            bluetoothSafetyTimer.restart();
        }
    }

    function setProfileGroup(cardName: string, groupId: string): void {
        const cardInfo = root.bluetoothCards[cardName];
        if (!cardInfo || !cardInfo.profileGroups)
            return;

        const groupObj = cardInfo.profileGroups.find(g => g.id === groupId);
        if (!groupObj || !groupObj.codecs || groupObj.codecs.length === 0)
            return;

        const matchingCodec = groupObj.codecs.find(c => c.codecKey === cardInfo.activeCodecKey);
        const targetKey = matchingCodec ? matchingCodec.key : groupObj.codecs[0].key;
        root.setCardProfile(cardName, targetKey);
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
                    const newBtCards = ({});

                    for (const card of cards) {
                        if (!card.name)
                            continue;

                        if (root.isBluetoothCard(card)) {
                            const props = card.properties ?? {};
                            const rawAddr = props["bluez5.address"] || props["device.string"] || card.name;
                            const address = root.formatBtAddress(rawAddr);
                            const activeProfileKey = card.active_profile ?? "";

                            const availableProfiles = card.profiles ?? {};
                            const groupMap = ({});

                            for (const [profKey, profVal] of Object.entries(availableProfiles)) {
                                if (profVal && (profVal.available === false || profVal.available === "no"))
                                    continue;

                                const parsed = root.parseProfileAndCodec(profKey, profVal ? profVal.description : "", profVal);
                                if (!groupMap[parsed.group]) {
                                    groupMap[parsed.group] = {
                                        id: parsed.group,
                                        name: parsed.groupName,
                                        icon: parsed.groupIcon,
                                        codecs: []
                                    };
                                }

                                if (!groupMap[parsed.group].codecs.some(c => c.key === profKey)) {
                                    groupMap[parsed.group].codecs.push({
                                        key: profKey,
                                        codecKey: parsed.codecKey,
                                        name: parsed.codecName,
                                        description: profVal.description || profKey
                                    });
                                }
                            }

                            const profileGroups = Object.values(groupMap);

                            let activeGroup = "";
                            let activeGroupName = "";
                            let activeCodecKey = "";
                            let activeCodecName = "";

                            if (activeProfileKey) {
                                const activeVal = availableProfiles[activeProfileKey];
                                const activeParsed = root.parseProfileAndCodec(activeProfileKey, activeVal?.description, activeVal);
                                activeGroup = activeParsed.group;
                                activeGroupName = activeParsed.groupName;
                                activeCodecKey = activeParsed.codecKey;
                                activeCodecName = activeParsed.codecName;
                            }

                            if (!activeGroup && profileGroups.length > 0) {
                                activeGroup = profileGroups[0].id;
                                activeGroupName = profileGroups[0].name;
                            }

                            const currentGroupObj = profileGroups.find(g => g.id === activeGroup);
                            let activeGroupCodecs = currentGroupObj ? currentGroupObj.codecs : [];
                            if (!activeCodecKey && activeGroupCodecs.length > 0) {
                                activeCodecKey = activeGroupCodecs[0].codecKey;
                                activeCodecName = activeGroupCodecs[0].name;
                            }

                            const cardInfo = {
                                cardName: card.name,
                                address: address,
                                description: props["device.description"] || card.description || card.name,
                                activeProfileKey: activeProfileKey,
                                activeGroup: activeGroup,
                                activeGroupName: activeGroupName,
                                activeCodecKey: activeCodecKey,
                                activeCodecName: activeCodecName,
                                activeGroupCodecs: activeGroupCodecs,
                                profileGroups: profileGroups
                            };

                            newBtCards[card.name] = cardInfo;
                            if (address)
                                newBtCards[address] = cardInfo;

                            continue;
                        }

                        if (!card.name?.startsWith("alsa_card."))
                            continue;

                        const profiles = card.profiles ?? {};
                        const active = String(card.active_profile ?? "");
                        const activeOutput = active.split("+").find(part => part.startsWith("output:")) || "";
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
                            const profileOutput = profileName.split("+").find(part => part.startsWith("output:")) || "";
                            if (!profileName || (profileOutput && profileOutput === activeOutput))
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
                    root.bluetoothCards = newBtCards;
                } catch (error) {
                    root.profileSinks = [];
                    root.bluetoothCards = ({});
                }
            }
        }
    }

    Process {
        id: profileSwitchProc

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.pendingProfileSink = "";
                if (GlobalConfig.utilities.toasts.audioOutputChanged)
                    Toaster.toast(qsTr("Audio Profile Error"), qsTr("Failed to switch audio profile or codec"), "error");
            }
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
