pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var deviceStatus: null
    property var wirelessInterfaces: []
    property var ethernetInterfaces: []
    property bool isConnected: false
    readonly property bool wifiConnected: wirelessInterfaces.some(i => isConnectedState(i.state))
    readonly property bool connecting: wirelessInterfaces.some(i => isConnectingState(i.state))
    property string activeInterface: ""
    property string activeConnection: ""
    property bool wifiEnabled: true
    readonly property bool scanning: rescanProc.running
    readonly property list<AccessPoint> networks: []
    readonly property AccessPoint active: wifiConnected ? (networks.find(n => n.active) ?? null) : null
    property list<var> vpnConnections: []
    readonly property var activeVpnConnection: vpnConnections.find(v => v.active) ?? null
    property list<string> savedConnections: []
    property list<string> savedConnectionSsids: []
    property list<var> savedWifiProfiles: []

    property var wifiConnectionQueue: []
    property int currentSsidQueryIndex: 0
    property var pendingConnection: null
    property var wirelessDeviceDetails: null
    property var ethernetDeviceDetails: null
    property list<var> ethernetDevices: []
    readonly property var activeEthernet: ethernetDevices.find(d => d.connected) ?? null
    property list<var> activeProcesses: []
    property bool liveRefreshInFlight: false
    property bool radioChangeInFlight: false
    property string wifiConnectionChangeKey: ""

    readonly property alias connectionCheckTimer: connectionCheckTimer
    readonly property alias immediateCheckTimer: immediateCheckTimer

    // Constants
    readonly property string deviceTypeWifi: "wifi"
    readonly property string deviceTypeEthernet: "ethernet"
    readonly property string connectionTypeWireless: "802-11-wireless"
    readonly property string nmcliCommandDevice: "device"
    readonly property string nmcliCommandConnection: "connection"
    readonly property string nmcliCommandWifi: "wifi"
    readonly property string nmcliCommandRadio: "radio"
    readonly property string deviceStatusFields: "DEVICE,TYPE,STATE,CONNECTION"
    readonly property string connectionListFields: "NAME,TYPE,ACTIVE"
    readonly property string wirelessSsidField: "802-11-wireless.ssid"
    readonly property string networkListFields: "SSID,SIGNAL,SECURITY"
    readonly property string networkDetailFields: "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY"
    readonly property string securityKeyMgmt: "802-11-wireless-security.key-mgmt"
    readonly property string securityPsk: "802-11-wireless-security.psk"
    readonly property string keyMgmtWpaPsk: "wpa-psk"
    readonly property string connectionParamType: "type"
    readonly property string connectionParamConName: "con-name"
    readonly property string connectionParamIfname: "ifname"
    readonly property string connectionParamSsid: "ssid"
    readonly property string connectionParamPassword: "password"
    readonly property string connectionParamBssid: "802-11-wireless.bssid"
    readonly property string wifiConnectParamBssid: "bssid"
    readonly property list<string> hiddenWifiSsids: ["IITJ_Guest", "eduroam"]

    signal connectionFailed(string ssid)

    function detectPasswordRequired(error: string): bool {
        if (!error || error.length === 0) {
            return false;
        }

        return (error.includes("Secrets were required") || error.includes("Secrets were required, but not provided") || error.includes("No secrets provided") || error.includes("802-11-wireless-security.psk") || error.includes("password for") || (error.includes("password") && !error.includes("Connection activated") && !error.includes("successfully")) || (error.includes("Secrets") && !error.includes("Connection activated") && !error.includes("successfully")) || (error.includes("802.11") && !error.includes("Connection activated") && !error.includes("successfully"))) && !error.includes("Connection activated") && !error.includes("successfully");
    }

    // nmcli's terse output escapes field separators (for example BSSID
    // colons) with a backslash. A plain split(":") corrupts those fields and
    // can make the UI report the wrong profile, AP, or connection state.
    function splitTerseLine(line: string): list<string> {
        const fields = [];
        let field = "";
        let escaped = false;

        for (let i = 0; i < line.length; i++) {
            const character = line[i];
            if (escaped) {
                field += character;
                escaped = false;
            } else if (character === "\\") {
                escaped = true;
            } else if (character === ":") {
                fields.push(field);
                field = "";
            } else {
                field += character;
            }
        }

        if (escaped)
            field += "\\";
        fields.push(field);
        return fields;
    }

    function parseNetworkOutput(output: string): list<var> {
        if (!output || output.length === 0) {
            return [];
        }

        const allNetworks = output.trim().split("\n").filter(line => line && line.length > 0).map(n => {
            const net = splitTerseLine(n);
            return {
                active: net[0] === "yes",
                strength: parseInt(net[1] || "0", 10) || 0,
                frequency: parseInt(net[2] || "0", 10) || 0,
                ssid: (net[3] ?? "").trim(),
                bssid: (net[4] ?? "").trim(),
                security: (net[5] ?? "").trim()
            };
        }).filter(n => n.ssid && n.ssid.length > 0);

        return allNetworks;
    }

    function deduplicateNetworks(networks: list<var>): list<var> {
        if (!networks || networks.length === 0) {
            return [];
        }

        const networkMap = new Map();
        for (const network of networks) {
            const band = network.frequency >= 5925 ? "6" : network.frequency >= 4900 ? "5" : "2.4";
            const key = `${network.ssid}|${band}`;
            const existing = networkMap.get(key);
            if (!existing) {
                networkMap.set(key, network);
            } else {
                if (network.active && !existing.active) {
                    networkMap.set(key, network);
                } else if (!network.active && !existing.active) {
                    if (network.strength > existing.strength) {
                        networkMap.set(key, network);
                    }
                }
            }
        }

        return Array.from(networkMap.values());
    }

    function isHiddenWifiSsid(ssid: string): bool {
        const candidate = (ssid || "").toLowerCase().trim();
        return root.hiddenWifiSsids.some(hidden => hidden.toLowerCase() === candidate);
    }

    function networkBand(frequency: int): string {
        return frequency >= 5925 ? "6" : frequency >= 4900 ? "5" : "2.4";
    }

    function networkKey(ssid: string, frequency: int): string {
        return `${ssid}|${networkBand(frequency)}`;
    }

    function addMissingSavedBands(networks: list<var>): list<var> {
        const combined = networks.slice();
        const present = new Set(combined.map(n => networkKey(n.ssid, n.frequency)));

        for (const profile of root.savedWifiProfiles) {
            if (!profile.ssid || isHiddenWifiSsid(profile.ssid) || (profile.band !== "a" && profile.band !== "bg"))
                continue;

            const frequency = profile.band === "a" ? 5180 : 2412;
            const key = networkKey(profile.ssid, frequency);
            if (present.has(key))
                continue;

            combined.push({
                active: false,
                strength: 0,
                frequency: frequency,
                ssid: profile.ssid,
                bssid: profile.bssid || "",
                security: "802.1X",
                savedOnly: true
            });
            present.add(key);
        }

        return combined;
    }

    function isConnectionCommand(command: list<string>): bool {
        if (!command || command.length === 0) {
            return false;
        }

        return command.includes(root.nmcliCommandWifi) || command.includes(root.nmcliCommandConnection);
    }

    function isWifiActivationCommand(command: list<string>): bool {
        if (!command || command.length === 0)
            return false;
        const connectionUp = command.includes(root.nmcliCommandConnection) && command.includes("up");
        const wifiConnect = command.includes(root.nmcliCommandDevice) && command.includes(root.nmcliCommandWifi) && command.includes("connect");
        return connectionUp || wifiConnect;
    }

    function cancelPendingWifiOperation(): void {
        connectionCheckTimer.stop();
        immediateCheckTimer.stop();
        immediateCheckTimer.checkCount = 0;
        root.pendingConnection = null;
        root.wifiConnectionChangeKey = "";

        for (const proc of root.activeProcesses) {
            if (proc && proc.running && isWifiActivationCommand(proc.cmdArgs)) {
                // Suppress callbacks/retries from the superseded request.
                proc.callbackCalled = true;
                proc.running = false;
            }
        }
    }

    function pendingConnectionMatchesActive(): bool {
        if (!root.pendingConnection || !root.active)
            return false;
        if (root.active.ssid !== root.pendingConnection.ssid)
            return false;
        const wantedBssid = (root.pendingConnection.bssid || "").toUpperCase();
        return wantedBssid.length === 0 || root.active.bssid.toUpperCase() === wantedBssid;
    }

    function isWifiOperationPending(ssid: string, bssid: string): bool {
        if (!root.wifiConnectionChangeKey || root.wifiConnectionChangeKey === "disconnect")
            return false;
        return root.wifiConnectionChangeKey === `${ssid}|${(bssid || "").toUpperCase()}`;
    }

    function parseDeviceStatusOutput(output: string, filterType: string): list<var> {
        if (!output || output.length === 0) {
            return [];
        }

        const interfaces = [];
        const lines = output.trim().split("\n");

        for (const line of lines) {
            const parts = splitTerseLine(line);
            if (parts.length >= 2) {
                const deviceType = parts[1];
                let shouldInclude = false;

                if (filterType === root.deviceTypeWifi && deviceType === root.deviceTypeWifi) {
                    shouldInclude = true;
                } else if (filterType === root.deviceTypeEthernet && deviceType === root.deviceTypeEthernet) {
                    shouldInclude = true;
                } else if (filterType === "both" && (deviceType === root.deviceTypeWifi || deviceType === root.deviceTypeEthernet)) {
                    shouldInclude = true;
                }

                if (shouldInclude) {
                    interfaces.push({
                        device: parts[0] || "",
                        type: parts[1] || "",
                        state: parts[2] || "",
                        connection: parts[3] || ""
                    });
                }
            }
        }

        return interfaces;
    }

    function isConnectedState(state: string): bool {
        if (!state || state.length === 0) {
            return false;
        }

        return state === "100 (connected)" || state === "connected" || state.startsWith("connected");
    }

    function isConnectingState(state: string): bool {
        return !!state && state.startsWith("connecting");
    }

    function connectingSsid(): string {
        const iface = root.wirelessInterfaces.find(i => isConnectingState(i.state));
        return iface ? iface.connection : "";
    }

    function executeCommand(args: list<string>, callback: var): void {
        const proc = commandProc.createObject(root);
        proc.cmdArgs = ["nmcli", ...args];
        proc.callback = callback;

        activeProcesses.push(proc);

        proc.processFinished.connect(() => {
            const index = activeProcesses.indexOf(proc);
            if (index >= 0) {
                activeProcesses.splice(index, 1);
            }
        });

        Qt.callLater(() => {
            proc.exec(proc.cmdArgs);
        });
    }

    function getDeviceStatus(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            if (callback)
                callback(result.output);
        });
    }

    function getWirelessInterfaces(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            const interfaces = parseDeviceStatusOutput(result.output, root.deviceTypeWifi);
            root.wirelessInterfaces = interfaces;
            if (!root.wifiConnected)
                root.wirelessDeviceDetails = null;
            if (callback)
                callback(interfaces);
        });
    }

    function getEthernetInterfaces(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            const interfaces = parseDeviceStatusOutput(result.output, root.deviceTypeEthernet);
            const devices = [];

            for (const iface of interfaces) {
                const connected = isConnectedState(iface.state);

                devices.push({
                    interface: iface.device,
                    type: iface.type,
                    state: iface.state,
                    connection: iface.connection,
                    connected: connected,
                    ipAddress: "",
                    gateway: "",
                    dns: [],
                    subnet: "",
                    macAddress: "",
                    speed: ""
                });
            }

            root.ethernetInterfaces = interfaces;
            root.ethernetDevices = devices;
            if (callback)
                callback(interfaces);
        });
    }

    function connectEthernet(connectionName: string, interfaceName: string, callback: var): void {
        if (connectionName && connectionName.length > 0) {
            executeCommand([root.nmcliCommandConnection, "up", connectionName], result => {
                if (result.success) {
                    Qt.callLater(() => {
                        getEthernetInterfaces(() => {});
                        if (interfaceName && interfaceName.length > 0) {
                            Qt.callLater(() => {
                                getEthernetDeviceDetails(interfaceName, () => {});
                            }, 1000);
                        }
                    }, 500);
                }
                if (callback)
                    callback(result);
            });
        } else if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "connect", interfaceName], result => {
                if (result.success) {
                    Qt.callLater(() => {
                        getEthernetInterfaces(() => {});
                        Qt.callLater(() => {
                            getEthernetDeviceDetails(interfaceName, () => {});
                        }, 1000);
                    }, 500);
                }
                if (callback)
                    callback(result);
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection name or interface specified",
                    exitCode: -1
                });
        }
    }

    function disconnectEthernet(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No connection name specified",
                    exitCode: -1
                });
            return;
        }

        executeCommand([root.nmcliCommandConnection, "down", connectionName], result => {
            if (result.success) {
                root.ethernetDeviceDetails = null;
                Qt.callLater(() => {
                    getEthernetInterfaces(() => {});
                }, 500);
            }
            if (callback)
                callback(result);
        });
    }

    function connectVpn(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) return;
        executeCommand([root.nmcliCommandConnection, "up", connectionName], result => {
            Qt.callLater(() => { loadSavedConnections(() => {}); }, 500);
            if (callback) callback(result.success);
        });
    }

    function disconnectVpn(connectionName: string, callback: var): void {
        if (!connectionName || connectionName.length === 0) return;
        executeCommand([root.nmcliCommandConnection, "down", connectionName], result => {
            Qt.callLater(() => { loadSavedConnections(() => {}); }, 500);
            if (callback) callback(result.success);
        });
    }

    function getAllInterfaces(callback: var): void {
        executeCommand(["-t", "-f", root.deviceStatusFields, root.nmcliCommandDevice, "status"], result => {
            const interfaces = parseDeviceStatusOutput(result.output, "both");
            if (callback)
                callback(interfaces);
        });
    }

    function isInterfaceConnected(interfaceName: string, callback: var): void {
        executeCommand([root.nmcliCommandDevice, "status"], result => {
            const lines = result.output.trim().split("\n");
            for (const line of lines) {
                const parts = line.split(/\s+/);
                if (parts.length >= 3 && parts[0] === interfaceName) {
                    const connected = isConnectedState(parts[2]);
                    if (callback)
                        callback(connected);
                    return;
                }
            }
            if (callback)
                callback(false);
        });
    }

    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        if (isSecure) {
            const hasBssid = bssid !== undefined && bssid !== null && bssid.length > 0;
            connectWireless(ssid, "", bssid, result => {
                if (result.success) {
                    if (callback)
                        callback({
                            success: true,
                            usedSavedPassword: true,
                            output: result.output,
                            error: "",
                            exitCode: 0
                        });
                } else if (result.needsPassword) {
                    if (callback)
                        callback({
                            success: false,
                            needsPassword: true,
                            output: result.output,
                            error: result.error,
                            exitCode: result.exitCode
                        });
                } else {
                    if (callback)
                        callback(result);
                }
            });
        } else {
            connectWireless(ssid, "", bssid, callback);
        }
    }

    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        connectWireless(ssid, password, bssid, callback);
    }

    function connectHiddenNetwork(ssid: string, password: string, security: string, hidden: bool, callback: var): void {
        if (!ssid || ssid.length === 0) {
            if (callback)
                callback({ success: false, error: "SSID is required" });
            return;
        }

        if (security !== "wpa-psk" && security !== "none") {
            if (callback)
                callback({ success: false, error: "Unsupported security type. Only Personal (WPA) and Open networks are supported." });
            return;
        }

        const isSecure = security !== "none";
        const requestKey = `${ssid}|hidden`;

        cancelPendingWifiOperation();
        root.wifiConnectionChangeKey = requestKey;

        if (callback) {
            root.pendingConnection = {
                ssid: ssid,
                bssid: "",
                callback: callback,
                retryCount: 0
            };
            connectionCheckTimer.start();
            immediateCheckTimer.checkCount = 0;
            immediateCheckTimer.start();
        }

        // Create a uniquely named temporary profile so an existing working
        // profile for `ssid` is not destroyed before replacement activation succeeds.
        const tempConName = "temp_hidden_" + ssid.replace(/[^a-zA-Z0-9_-]/g, "_") + "_" + Date.now();

        const cmd = [
            root.nmcliCommandConnection, "add",
            root.connectionParamType, root.deviceTypeWifi,
            root.connectionParamConName, tempConName,
            root.connectionParamIfname, "*",
            root.connectionParamSsid, ssid
        ];

        if (hidden) {
            cmd.push("802-11-wireless.hidden", "yes");
        }

        if (isSecure && password && password.length > 0) {
            cmd.push(root.securityKeyMgmt, root.keyMgmtWpaPsk, root.securityPsk, password);
        }

        executeCommand(cmd, addResult => {
            if (root.wifiConnectionChangeKey !== requestKey) {
                // Superseded or cancelled. Clean up temporary profile if created.
                if (addResult.success) {
                    executeCommand([root.nmcliCommandConnection, "delete", tempConName], null);
                }
                return;
            }

            if (addResult.success) {
                activateConnection(tempConName, upResult => {
                    if (root.wifiConnectionChangeKey !== requestKey) {
                        // Superseded or cancelled.
                        executeCommand([root.nmcliCommandConnection, "delete", tempConName], null);
                        return;
                    }

                    if (upResult.success) {
                        // Activation succeeded. Replace/rename old profile if one exists.
                        executeCommand([root.nmcliCommandConnection, "show", ssid], showResult => {
                            const finalizeRename = () => {
                                executeCommand([root.nmcliCommandConnection, "modify", tempConName, "connection.id", ssid], modifyResult => {
                                    root.wifiConnectionChangeKey = "";
                                    loadSavedConnections(() => {});
                                    refreshLiveWifiState();
                                    if (callback)
                                        callback({ success: true, output: upResult.output, error: "", exitCode: 0 });
                                });
                            };

                            if (showResult.success) {
                                executeCommand([root.nmcliCommandConnection, "delete", ssid], deleteResult => {
                                    finalizeRename();
                                });
                            } else {
                                finalizeRename();
                            }
                        });
                    } else {
                        // Activation failed. Clean up ONLY the temporary profile.
                        executeCommand([root.nmcliCommandConnection, "delete", tempConName], deleteResult => {
                            root.wifiConnectionChangeKey = "";
                            loadSavedConnections(() => {});
                            if (callback)
                                callback(upResult);
                        });
                    }
                });
            } else {
                // Creation of temporary profile failed. Try fallback direct device connect.
                let fallbackCmd = [root.nmcliCommandDevice, root.nmcliCommandWifi, "connect", ssid];
                if (isSecure && password && password.length > 0) {
                    fallbackCmd.push(root.connectionParamPassword, password);
                }
                if (hidden) {
                    fallbackCmd.push("hidden", "yes");
                }
                executeCommand(fallbackCmd, fallbackResult => {
                    if (root.wifiConnectionChangeKey !== requestKey)
                        return;
                    root.wifiConnectionChangeKey = "";
                    if (fallbackResult.success) {
                        refreshLiveWifiState();
                    }
                    if (callback)
                        callback(fallbackResult);
                });
            }
        });
    }

    function connectWireless(ssid: string, password: string, bssid: string, callback: var, retryCount: int): void {
        const hasBssid = bssid !== undefined && bssid !== null && bssid.length > 0;
        const retries = retryCount !== undefined ? retryCount : 0;
        // Do not hammer enterprise APs after a failed activation. A new user
        // selection supersedes this request and starts one fresh attempt.
        const maxRetries = 0;
        const requestKey = `${ssid}|${hasBssid ? bssid.toUpperCase() : ""}`;

        if (retries === 0) {
            // The latest explicit selection wins. NetworkManager will cancel
            // the older activation when the new one is submitted.
            cancelPendingWifiOperation();
            root.wifiConnectionChangeKey = requestKey;
        }

        if (callback) {
            root.pendingConnection = {
                ssid: ssid,
                bssid: hasBssid ? bssid : "",
                callback: callback,
                retryCount: retries
            };
            connectionCheckTimer.start();
            immediateCheckTimer.checkCount = 0;
            immediateCheckTimer.start();
        }

        if (password && password.length > 0 && hasBssid) {
            const bssidUpper = bssid.toUpperCase();
            createConnectionWithPassword(ssid, bssidUpper, password, result => {
                if (root.wifiConnectionChangeKey === requestKey)
                    root.wifiConnectionChangeKey = "";
                if (callback)
                    callback(result);
            });
            return;
        }

        const selectedAp = hasBssid ? root.networks.find(n => n.bssid.toUpperCase() === bssid.toUpperCase()) : null;
        const savedProfile = !password ? root.profileForNetwork(ssid, hasBssid ? bssid : "", selectedAp?.frequency || 0) : "";
        let cmd = savedProfile
            ? [root.nmcliCommandConnection, "up", savedProfile]
            : [root.nmcliCommandDevice, root.nmcliCommandWifi, "connect", ssid];
        if (password && password.length > 0) {
            cmd.push(root.connectionParamPassword, password);
        }
        if (hasBssid && !savedProfile) {
            // Preserve the AP selected in the UI. Without this, duplicate
            // SSIDs such as IITJ_WLAN silently fall back from 5 GHz to 2.4 GHz.
            cmd.push(root.wifiConnectParamBssid, bssid.toUpperCase());
        }
        executeCommand(cmd, result => {
            if (root.wifiConnectionChangeKey !== requestKey) {
                return;
            }

            if (result.needsPassword && callback) {
                root.wifiConnectionChangeKey = "";
                if (callback)
                    callback(result);
                return;
            }

            if (!result.success && root.pendingConnection && retries < maxRetries) {
                console.warn(lc, "Connection failed, retrying... (attempt " + (retries + 1) + "/" + maxRetries + ")");
                Qt.callLater(() => {
                    if (root.wifiConnectionChangeKey === requestKey)
                        connectWireless(ssid, password, bssid, callback, retries + 1);
                }, 1000);
            } else if (!result.success && root.pendingConnection) {
                root.wifiConnectionChangeKey = "";
            } else if (result.success && callback) {
                root.wifiConnectionChangeKey = "";
            } else if (result.success) {
                root.wifiConnectionChangeKey = "";
            } else if (!result.success && !root.pendingConnection) {
                root.wifiConnectionChangeKey = "";
                if (callback)
                    callback(result);
            }
        });
    }

    function createConnectionWithPassword(ssid: string, bssidUpper: string, password: string, callback: var): void {
        const requestKey = root.wifiConnectionChangeKey;
        checkAndDeleteConnection(ssid, () => {
            if (requestKey && root.wifiConnectionChangeKey !== requestKey) {
                return;
            }
            const cmd = [root.nmcliCommandConnection, "add", root.connectionParamType, root.deviceTypeWifi, root.connectionParamConName, ssid, root.connectionParamIfname, "*", root.connectionParamSsid, ssid, root.connectionParamBssid, bssidUpper, root.securityKeyMgmt, root.keyMgmtWpaPsk, root.securityPsk, password];

            executeCommand(cmd, result => {
                if (requestKey && root.wifiConnectionChangeKey !== requestKey) {
                    return;
                }
                if (result.success) {
                    loadSavedConnections(() => {});
                    activateConnection(ssid, res => {
                        if (requestKey && root.wifiConnectionChangeKey !== requestKey) return;
                        root.wifiConnectionChangeKey = "";
                        if (callback) callback(res);
                    });
                } else {
                    const hasDuplicateWarning = result.error && (result.error.includes("another connection with the name") || result.error.includes("Reference the connection by its uuid"));

                    if (hasDuplicateWarning || (result.exitCode > 0 && result.exitCode < 10)) {
                        loadSavedConnections(() => {});
                        activateConnection(ssid, callback);
                    } else {
                        console.warn(lc, "Connection profile creation failed, trying fallback...");
                        let fallbackCmd = [root.nmcliCommandDevice, root.nmcliCommandWifi, "connect", ssid, root.connectionParamPassword, password];
                        executeCommand(fallbackCmd, fallbackResult => {
                            if (callback)
                                callback(fallbackResult);
                        });
                    }
                }
            });
        });
    }

    function checkAndDeleteConnection(ssid: string, callback: var): void {
        executeCommand([root.nmcliCommandConnection, "show", ssid], result => {
            if (result.success) {
                executeCommand([root.nmcliCommandConnection, "delete", ssid], deleteResult => {
                    Qt.callLater(() => {
                        if (callback)
                            callback();
                    }, 300);
                });
            } else {
                if (callback)
                    callback();
            }
        });
    }

    function activateConnection(connectionName: string, callback: var): void {
        executeCommand([root.nmcliCommandConnection, "up", connectionName], result => {
            if (callback)
                callback(result);
        });
    }

    function loadSavedConnections(callback: var): void {
        executeCommand(["-t", "-f", root.connectionListFields, root.nmcliCommandConnection, "show"], result => {
            if (!result.success) {
                root.savedConnections = [];
                root.savedConnectionSsids = [];
                if (callback)
                    callback([]);
                return;
            }

            parseConnectionList(result.output, callback);
        });
    }

    function parseConnectionList(output: string, callback: var): void {
        const lines = output.trim().split("\n").filter(line => line.length > 0);
        const wifiConnections = [];
        const connections = [];
        const vpns = [];

        for (const line of lines) {
            const parts = splitTerseLine(line);
            if (parts.length >= 2) {
                let name = parts[0];
                let type = parts[1];
                let active = parts[2] === "yes";

                if (parts.length > 3) {
                    active = parts[parts.length - 1] === "yes";
                    type = parts[parts.length - 2];
                    name = parts.slice(0, parts.length - 2).join(":");
                }

                connections.push(name);

                if (type === root.connectionTypeWireless) {
                    wifiConnections.push(name);
                } else if (type === "vpn" || type === "wireguard" || type === "tun") {
                    vpns.push({ name: name, active: active, type: type });
                }
            }
        }

        root.savedConnections = connections;
        root.vpnConnections = vpns;

        if (wifiConnections.length > 0) {
            root.wifiConnectionQueue = wifiConnections;
            root.currentSsidQueryIndex = 0;
            root.savedConnectionSsids = [];
            root.savedWifiProfiles = [];
            queryNextSsid(callback);
        } else {
            root.savedConnectionSsids = [];
            root.wifiConnectionQueue = [];
            if (callback)
                callback(root.savedConnectionSsids);
        }
    }

    function queryNextSsid(callback: var): void {
        if (root.currentSsidQueryIndex < root.wifiConnectionQueue.length) {
            const connectionName = root.wifiConnectionQueue[root.currentSsidQueryIndex];
            root.currentSsidQueryIndex++;

            executeCommand(["-t", "-f", `${root.wirelessSsidField},802-11-wireless.bssid,802-11-wireless.band`, root.nmcliCommandConnection, "show", connectionName], result => {
                if (result.success) {
                    processSsidOutput(connectionName, result.output);
                }
                queryNextSsid(callback);
            });
        } else {
            root.wifiConnectionQueue = [];
            root.currentSsidQueryIndex = 0;
            if (callback)
                callback(root.savedConnectionSsids);
        }
    }

    function processSsidOutput(connectionName: string, output: string): void {
        const lines = output.trim().split("\n");
        let profileSsid = "";
        let profileBssid = "";
        let profileBand = "";
        for (const line of lines) {
            if (line.startsWith("802-11-wireless.ssid:")) {
                const ssid = line.substring("802-11-wireless.ssid:".length).trim();
                profileSsid = ssid;
                if (ssid && ssid.length > 0) {
                    const ssidLower = ssid.toLowerCase();
                    const exists = root.savedConnectionSsids.some(s => s && s.toLowerCase() === ssidLower);
                    if (!exists) {
                        const newList = root.savedConnectionSsids.slice();
                        newList.push(ssid);
                        root.savedConnectionSsids = newList;
                    }
                }
            } else if (line.startsWith("802-11-wireless.bssid:")) {
                profileBssid = line.substring("802-11-wireless.bssid:".length).trim().toUpperCase();
            } else if (line.startsWith("802-11-wireless.band:")) {
                profileBand = line.substring("802-11-wireless.band:".length).trim();
            }
        }

        if (profileSsid) {
            const profiles = root.savedWifiProfiles.slice();
            profiles.push({ name: connectionName, ssid: profileSsid, bssid: profileBssid, band: profileBand });
            root.savedWifiProfiles = profiles;
        }
    }

    function profileForNetwork(ssid: string, bssid: string, frequency: int): string {
        const ssidLower = (ssid || "").toLowerCase().trim();
        const bssidUpper = (bssid || "").toUpperCase();
        const wantedBand = frequency >= 4900 ? "a" : frequency > 0 ? "bg" : "";
        const exact = root.savedWifiProfiles.find(p => p.ssid.toLowerCase().trim() === ssidLower && p.bssid && p.bssid === bssidUpper);
        if (exact)
            return exact.name;
        const bandMatch = root.savedWifiProfiles.find(p => p.ssid.toLowerCase().trim() === ssidLower && wantedBand && p.band === wantedBand);
        if (bandMatch)
            return bandMatch.name;
        const any = root.savedWifiProfiles.find(p => p.ssid.toLowerCase().trim() === ssidLower);
        return any ? any.name : "";
    }

    function hasSavedProfile(ssid: string, bssid: string, frequency: int): bool {
        if (!ssid || ssid.length === 0) {
            return false;
        }
        if (bssid || frequency)
            return profileForNetwork(ssid, bssid || "", frequency || 0).length > 0;
        const ssidLower = ssid.toLowerCase().trim();

        if (root.active && root.active.ssid) {
            const activeSsidLower = root.active.ssid.toLowerCase().trim();
            if (activeSsidLower === ssidLower) {
                return true;
            }
        }

        const hasSsid = root.savedConnectionSsids.some(savedSsid => savedSsid && savedSsid.toLowerCase().trim() === ssidLower);

        if (hasSsid) {
            return true;
        }

        const hasConnectionName = root.savedConnections.some(connName => connName && connName.toLowerCase().trim() === ssidLower);

        return hasConnectionName;
    }

    function forgetNetwork(ssid: string, callback: var, bssid: string, frequency: int): void {
        if (!ssid || ssid.length === 0) {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No SSID specified",
                    exitCode: -1
                });
            return;
        }

        const mappedProfile = root.profileForNetwork(ssid, bssid || "", frequency || 0);
        const connectionName = mappedProfile || root.savedConnections.find(conn => conn && conn.toLowerCase().trim() === ssid.toLowerCase().trim()) || ssid;

        executeCommand([root.nmcliCommandConnection, "delete", connectionName], result => {
            if (result.success) {
                Qt.callLater(() => {
                    loadSavedConnections(() => {});
                }, 500);
            }
            if (callback)
                callback(result);
        });
    }

    function disconnect(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "disconnect", interfaceName], result => {
                if (callback)
                    callback(result.success ? result.output : "");
            });
        } else {
            executeCommand([root.nmcliCommandDevice, "disconnect", root.deviceTypeWifi], result => {
                if (callback)
                    callback(result.success ? result.output : "");
            });
        }
    }

    function disconnectFromNetwork(callback: var): void {
        cancelPendingWifiOperation();
        root.wifiConnectionChangeKey = "disconnect";
        const connectedInterface = root.wirelessInterfaces.find(i => isConnectedState(i.state));
        if (connectedInterface && connectedInterface.connection) {
            executeCommand([root.nmcliCommandConnection, "down", connectedInterface.connection], result => {
                root.wifiConnectionChangeKey = "";
                if (result.success) {
                    refreshLiveWifiState();
                }
                if (callback)
                    callback(result);
            });
        } else {
            const interfaceName = root.wirelessInterfaces.length > 0 ? root.wirelessInterfaces[0].device : "";
            executeCommand([root.nmcliCommandDevice, "disconnect", interfaceName], result => {
                root.wifiConnectionChangeKey = "";
                if (result.success) {
                    refreshLiveWifiState();
                }
                if (callback)
                    callback(result);
            });
        }
    }

    function updateSavedNetworkPassword(ssid: string, password: string, callback: var, bssid: string, frequency: int): void {
        if (!ssid || !password) {
            if (callback)
                callback({ success: false, error: "SSID and password are required" });
            return;
        }

        const activeWifi = root.wirelessInterfaces.find(i => isConnectedState(i.state));
        const mappedProfile = root.profileForNetwork(ssid, bssid || "", frequency || 0);
        const connectionName = mappedProfile || (activeWifi && root.active && root.active.ssid === ssid
            ? activeWifi.connection
            : (root.savedConnections.find(name => name.toLowerCase().trim() === ssid.toLowerCase().trim()) || ssid));

        executeCommand(["-g", "802-11-wireless-security.key-mgmt,802-1x.eap", root.nmcliCommandConnection, "show", connectionName], info => {
            const enterprise = info.success && (info.output.includes("wpa-eap") || info.output.includes("802.1x") || info.output.includes("peap") || info.output.includes("ttls"));
            const setting = enterprise ? "802-1x.password" : root.securityPsk;
            executeCommand([root.nmcliCommandConnection, "modify", connectionName, setting, password], result => {
                if (result.success) {
                    executeCommand([root.nmcliCommandConnection, "up", connectionName], upResult => {
                        refreshLiveWifiState();
                        if (callback)
                            callback(upResult);
                    });
                } else if (callback) {
                    callback(result);
                }
            });
        });
    }

    function getDeviceDetails(interfaceName: string, callback: var): void {
        executeCommand([root.nmcliCommandDevice, "show", interfaceName], result => {
            if (callback)
                callback(result.output);
        });
    }

    function refreshStatus(callback: var): void {
        getDeviceStatus(output => {
            const lines = output.trim().split("\n");
            let connected = false;
            let activeIf = "";
            let activeConn = "";

            for (const line of lines) {
                const parts = splitTerseLine(line);
                if (parts.length >= 4) {
                    const state = parts[2] || "";
                    if (isConnectedState(state)) {
                        connected = true;
                        activeIf = parts[0] || "";
                        activeConn = parts[3] || "";
                        break;
                    }
                }
            }

            root.isConnected = connected;
            root.activeInterface = activeIf;
            root.activeConnection = activeConn;

            if (callback)
                callback({
                    connected,
                    interface: activeIf,
                    connection: activeConn
                });
        });
    }

    function bringInterfaceUp(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "connect", interfaceName], result => {
                if (callback) {
                    callback(result);
                }
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No interface specified",
                    exitCode: -1
                });
        }
    }

    function bringInterfaceDown(interfaceName: string, callback: var): void {
        if (interfaceName && interfaceName.length > 0) {
            executeCommand([root.nmcliCommandDevice, "disconnect", interfaceName], result => {
                if (callback) {
                    callback(result);
                }
            });
        } else {
            if (callback)
                callback({
                    success: false,
                    output: "",
                    error: "No interface specified",
                    exitCode: -1
                });
        }
    }

    function scanWirelessNetworks(interfaceName: string, callback: var): void {
        let cmd = [root.nmcliCommandDevice, root.nmcliCommandWifi, "rescan"];
        if (interfaceName && interfaceName.length > 0) {
            cmd.push(root.connectionParamIfname, interfaceName);
        }
        executeCommand(cmd, result => {
            if (callback) {
                callback(result);
            }
        });
    }

    function rescanWifi(): void {
        rescanProc.running = true;
    }

    function enableWifi(enabled: bool, callback: var): void {
        if (root.radioChangeInFlight) {
            if (callback)
                callback({ success: false, output: "", error: "A Wi-Fi radio change is already in progress", exitCode: -1 });
            return;
        }

        root.radioChangeInFlight = true;
        const cmd = enabled ? "on" : "off";
        executeCommand([root.nmcliCommandRadio, root.nmcliCommandWifi], statusResult => {
            const current = statusResult.success ? statusResult.output.trim() === "enabled" : root.wifiEnabled;
            root.wifiEnabled = current;

            if (statusResult.success && current === enabled) {
                root.radioChangeInFlight = false;
                if (callback)
                    callback({ success: true, output: "Wi-Fi radio already in requested state", error: "", exitCode: 0 });
                return;
            }

            executeCommand([root.nmcliCommandRadio, root.nmcliCommandWifi, cmd], result => {
                getWifiStatus(status => {
                    root.wifiEnabled = status;
                    root.radioChangeInFlight = false;
                    if (callback)
                        callback(result);
                });
            });
        });
    }

    function toggleWifi(callback: var): void {
        if (root.radioChangeInFlight)
            return;
        getWifiStatus(status => enableWifi(!status, callback));
    }

    function getWifiStatus(callback: var): void {
        executeCommand([root.nmcliCommandRadio, root.nmcliCommandWifi], result => {
            if (result.success) {
                const enabled = result.output.trim() === "enabled";
                root.wifiEnabled = enabled;
                if (callback)
                    callback(enabled);
            } else {
                if (callback)
                    callback(root.wifiEnabled);
            }
        });
    }

    function getNetworks(callback: var): void {
        // Reading the list must not implicitly trigger an off-channel scan.
        // MT79xx adapters can pause traffic for the duration of that scan,
        // causing periodic latency spikes and misleading signal jumps.
        executeCommand(["-g", root.networkDetailFields, root.nmcliCommandDevice, root.nmcliCommandWifi, "list", "--rescan", "no"], result => {
            if (!result.success) {
                if (callback)
                    callback([]);
                return;
            }

            const allNetworks = parseNetworkOutput(result.output).filter(n => !isHiddenWifiSsid(n.ssid));
            const networks = addMissingSavedBands(deduplicateNetworks(allNetworks));
            const rNetworks = root.networks;

            const newMap = new Map();
            for (const n of networks)
                // Keep 2.4/5/6 GHz variants independent and stable while the
                // selected access point roams between BSSIDs on one band.
                newMap.set(networkKey(n.ssid, n.frequency), n);

            for (let i = rNetworks.length - 1; i >= 0; i--) {
                const rn = rNetworks[i];
                const key = networkKey(rn.ssid, rn.frequency);
                if (!newMap.has(key)) {
                    rNetworks.splice(i, 1);
                    // Repeater observes list changes asynchronously.
                    rn.destroy(250);
                }
            }

            const existingMap = new Map();
            for (const rn of rNetworks)
                existingMap.set(networkKey(rn.ssid, rn.frequency), rn);

            for (const [key, network] of newMap) {
                const match = existingMap.get(key);
                if (match) {
                    match.lastIpcObject = network;
                } else {
                    rNetworks.push(apComp.createObject(root, {
                        lastIpcObject: network
                    }));
                }
            }

            if (callback)
                callback(root.networks);
            checkPendingConnection();
        });
    }

    function getWirelessSSIDs(interfaceName: string, callback: var): void {
        let cmd = ["-t", "-f", root.networkListFields, root.nmcliCommandDevice, root.nmcliCommandWifi, "list"];
        if (interfaceName && interfaceName.length > 0) {
            cmd.push(root.connectionParamIfname, interfaceName);
        }
        executeCommand(cmd, result => {
            if (!result.success) {
                if (callback)
                    callback([]);
                return;
            }

            const ssids = [];
            const lines = result.output.trim().split("\n");
            const seenSSIDs = new Set();

            for (const line of lines) {
                if (!line || line.length === 0)
                    continue;

                const parts = splitTerseLine(line);
                if (parts.length >= 1) {
                    const ssid = parts[0].trim();
                    if (ssid && ssid.length > 0 && !seenSSIDs.has(ssid)) {
                        seenSSIDs.add(ssid);
                        const signalStr = parts.length >= 2 ? parts[1].trim() : "";
                        const signal = signalStr ? parseInt(signalStr, 10) : 0;
                        const security = parts.length >= 3 ? parts[2].trim() : "";
                        ssids.push({
                            ssid: ssid,
                            signal: signalStr,
                            signalValue: isNaN(signal) ? 0 : signal,
                            security: security
                        });
                    }
                }
            }

            ssids.sort((a, b) => {
                return b.signalValue - a.signalValue;
            });

            if (callback)
                callback(ssids);
        });
    }

    function handlePasswordRequired(proc: var, error: string, output: string, exitCode: int): bool {
        if (!proc || !error || error.length === 0) {
            return false;
        }

        if (!isConnectionCommand(proc.cmdArgs) || !root.pendingConnection || !root.pendingConnection.callback) {
            return false;
        }

        const needsPassword = detectPasswordRequired(error);

        if (needsPassword && !proc.callbackCalled && root.pendingConnection) {
            connectionCheckTimer.stop();
            immediateCheckTimer.stop();
            immediateCheckTimer.checkCount = 0;
            const pending = root.pendingConnection;
            root.pendingConnection = null;
            proc.callbackCalled = true;
            const result = {
                success: false,
                output: output || "",
                error: error,
                exitCode: exitCode,
                needsPassword: true
            };
            if (pending.callback) {
                pending.callback(result);
            }
            if (proc.callback && proc.callback !== pending.callback) {
                proc.callback(result);
            }
            return true;
        }

        return false;
    }

    function checkPendingConnection(): void {
        if (root.pendingConnection) {
            Qt.callLater(() => {
                const connected = root.pendingConnectionMatchesActive();
                if (connected) {
                    connectionCheckTimer.stop();
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    if (root.pendingConnection.callback) {
                        root.pendingConnection.callback({
                            success: true,
                            output: "Connected",
                            error: "",
                            exitCode: 0
                        });
                    }
                    root.pendingConnection = null;
                } else {
                    if (!immediateCheckTimer.running) {
                        immediateCheckTimer.start();
                    }
                }
            });
        }
    }

    function cidrToSubnetMask(cidr: string): string {
        const cidrNum = parseInt(cidr, 10);
        if (isNaN(cidrNum) || cidrNum < 0 || cidrNum > 32) {
            return "";
        }

        const mask = (0xffffffff << (32 - cidrNum)) >>> 0;
        const octet1 = (mask >>> 24) & 0xff;
        const octet2 = (mask >>> 16) & 0xff;
        const octet3 = (mask >>> 8) & 0xff;
        const octet4 = mask & 0xff;

        return `${octet1}.${octet2}.${octet3}.${octet4}`;
    }

    function getWirelessDeviceDetails(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            const activeInterface = root.wirelessInterfaces.find(iface => {
                return isConnectedState(iface.state);
            });
            if (activeInterface && activeInterface.device) {
                interfaceName = activeInterface.device;
            } else {
                if (callback)
                    callback(null);
                return;
            }
        }

        executeCommand(["device", "show", interfaceName], result => {
            if (!result.success || !result.output) {
                root.wirelessDeviceDetails = null;
                if (callback)
                    callback(null);
                return;
            }

            const details = parseDeviceDetails(result.output, false);
            root.wirelessDeviceDetails = details;
            if (callback)
                callback(details);
        });
    }

    function getEthernetDeviceDetails(interfaceName: string, callback: var): void {
        if (!interfaceName || interfaceName.length === 0) {
            const activeInterface = root.ethernetInterfaces.find(iface => {
                return isConnectedState(iface.state);
            });
            if (activeInterface && activeInterface.device) {
                interfaceName = activeInterface.device;
            } else {
                if (callback)
                    callback(null);
                return;
            }
        }

        executeCommand(["device", "show", interfaceName], result => {
            if (!result.success || !result.output) {
                root.ethernetDeviceDetails = null;
                if (callback)
                    callback(null);
                return;
            }

            const details = parseDeviceDetails(result.output, true);
            root.ethernetDeviceDetails = details;
            if (callback)
                callback(details);
        });
    }

    function parseDeviceDetails(output: string, isEthernet: bool): var {
        const details = {
            ipAddress: "",
            gateway: "",
            dns: [],
            subnet: "",
            macAddress: "",
            speed: ""
        };

        if (!output || output.length === 0) {
            return details;
        }

        const lines = output.trim().split("\n");

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const parts = line.split(":");
            if (parts.length >= 2) {
                const key = parts[0].trim();
                const value = parts.slice(1).join(":").trim();

                if (key.startsWith("IP4.ADDRESS")) {
                    const ipParts = value.split("/");
                    details.ipAddress = ipParts[0] || "";
                    if (ipParts[1]) {
                        details.subnet = cidrToSubnetMask(ipParts[1]);
                    } else {
                        details.subnet = "";
                    }
                } else if (key === "IP4.GATEWAY") {
                    if (value !== "--") {
                        details.gateway = value;
                    }
                } else if (key.startsWith("IP4.DNS")) {
                    if (value !== "--" && value.length > 0) {
                        details.dns.push(value);
                    }
                } else if (isEthernet && key === "WIRED-PROPERTIES.MAC") {
                    details.macAddress = value;
                } else if (isEthernet && key === "WIRED-PROPERTIES.SPEED") {
                    details.speed = value;
                } else if (!isEthernet && key === "GENERAL.HWADDR") {
                    details.macAddress = value;
                }
            }
        }

        return details;
    }

    function refreshOnConnectionChange(): void {
        refreshLiveWifiState();
    }

    function refreshLiveWifiState(callback: var): void {
        if (root.liveRefreshInFlight)
            return;
        root.liveRefreshInFlight = true;

        getWirelessInterfaces(() => {
            getWifiStatus(() => {
                getNetworks(networks => {
                    root.liveRefreshInFlight = false;
                    refreshStatus(() => {});
                    if (callback)
                        callback();
                });
            });
        });
    }

    function refreshConnectionDetails(): void {
        getNetworks(networks => {
            const newActive = root.active;

            if (newActive && newActive.active) {
                Qt.callLater(() => {
                    if (root.wirelessInterfaces.length > 0) {
                        const activeWireless = root.wirelessInterfaces.find(iface => {
                            return isConnectedState(iface.state);
                        });
                        if (activeWireless && activeWireless.device) {
                            getWirelessDeviceDetails(activeWireless.device, () => {});
                        }
                    }

                    if (root.ethernetInterfaces.length > 0) {
                        const activeEthernet = root.ethernetInterfaces.find(iface => {
                            return isConnectedState(iface.state);
                        });
                        if (activeEthernet && activeEthernet.device) {
                            getEthernetDeviceDetails(activeEthernet.device, () => {});
                        }
                    }
                }, 500);
            } else {
                root.wirelessDeviceDetails = null;
                root.ethernetDeviceDetails = null;
            }

            getEthernetInterfaces(() => {
                if (root.activeEthernet && root.activeEthernet.connected) {
                    Qt.callLater(() => {
                        getEthernetDeviceDetails(root.activeEthernet.interface, () => {});
                    }, 500);
                }
            });
        });
    }

    Component.onCompleted: {
        getWifiStatus(() => {});
        refreshLiveWifiState();
        loadSavedConnections(() => {});
        getEthernetInterfaces(() => {});

        Qt.callLater(() => {
            if (root.wirelessInterfaces.length > 0) {
                const activeWireless = root.wirelessInterfaces.find(iface => {
                    return isConnectedState(iface.state);
                });
                if (activeWireless && activeWireless.device) {
                    getWirelessDeviceDetails(activeWireless.device, () => {});
                }
            }

            if (root.ethernetInterfaces.length > 0) {
                const activeEthernet = root.ethernetInterfaces.find(iface => {
                    return isConnectedState(iface.state);
                });
                if (activeEthernet && activeEthernet.device) {
                    getEthernetDeviceDetails(activeEthernet.device, () => {});
                }
            }
        }, 2000);
    }

    Component {
        id: commandProc

        CommandProcess {}
    }

    Component {
        id: apComp

        AccessPoint {}
    }

    Timer {
        id: connectionCheckTimer

        interval: 4000
        onTriggered: {
            if (root.pendingConnection) {
                const connected = root.pendingConnectionMatchesActive();

                if (!connected && root.pendingConnection.callback) {
                    let foundPasswordError = false;
                    for (let i = 0; i < root.activeProcesses.length; i++) {
                        const proc = root.activeProcesses[i];
                        if (proc && proc.stderr && proc.stderr.text) {
                            const error = proc.stderr.text.trim();
                            if (error && error.length > 0) {
                                if (root.isConnectionCommand(proc.cmdArgs)) {
                                    const needsPassword = root.detectPasswordRequired(error);

                                    if (needsPassword && !proc.callbackCalled && root.pendingConnection) {
                                        const pending = root.pendingConnection;
                                        root.pendingConnection = null;
                                        immediateCheckTimer.stop();
                                        immediateCheckTimer.checkCount = 0;
                                        proc.callbackCalled = true;
                                        const result = {
                                            success: false,
                                            output: (proc.stdout && proc.stdout.text) ? proc.stdout.text : "",
                                            error: error,
                                            exitCode: -1,
                                            needsPassword: true
                                        };
                                        if (pending.callback) {
                                            pending.callback(result);
                                        }
                                        if (proc.callback && proc.callback !== pending.callback) {
                                            proc.callback(result);
                                        }
                                        foundPasswordError = true;
                                        break;
                                    }
                                }
                            }
                        }
                    }

                    if (!foundPasswordError) {
                        const pending = root.pendingConnection;
                        const failedSsid = pending.ssid;
                        root.pendingConnection = null;
                        immediateCheckTimer.stop();
                        immediateCheckTimer.checkCount = 0;
                        root.connectionFailed(failedSsid);
                        pending.callback({
                            success: false,
                            output: "",
                            error: "Connection timeout",
                            exitCode: -1,
                            needsPassword: false
                        });
                    }
                } else if (connected) {
                    root.pendingConnection = null;
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                }
            }
        }
    }

    Timer {
        id: immediateCheckTimer

        property int checkCount: 0

        interval: 500
        repeat: true
        triggeredOnStart: false

        onTriggered: {
            if (root.pendingConnection) {
                checkCount++;
                const connected = root.pendingConnectionMatchesActive();

                if (connected) {
                    connectionCheckTimer.stop();
                    immediateCheckTimer.stop();
                    immediateCheckTimer.checkCount = 0;
                    if (root.pendingConnection.callback) {
                        root.pendingConnection.callback({
                            success: true,
                            output: "Connected",
                            error: "",
                            exitCode: 0
                        });
                    }
                    root.pendingConnection = null;
                } else {
                    for (let i = 0; i < root.activeProcesses.length; i++) {
                        const proc = root.activeProcesses[i];
                        if (proc && proc.stderr && proc.stderr.text) {
                            const error = proc.stderr.text.trim();
                            if (error && error.length > 0) {
                                if (root.isConnectionCommand(proc.cmdArgs)) {
                                    const needsPassword = root.detectPasswordRequired(error);

                                    if (needsPassword && !proc.callbackCalled && root.pendingConnection && root.pendingConnection.callback) {
                                        connectionCheckTimer.stop();
                                        immediateCheckTimer.stop();
                                        immediateCheckTimer.checkCount = 0;
                                        const pending = root.pendingConnection;
                                        root.pendingConnection = null;
                                        proc.callbackCalled = true;
                                        const result = {
                                            success: false,
                                            output: (proc.stdout && proc.stdout.text) ? proc.stdout.text : "",
                                            error: error,
                                            exitCode: -1,
                                            needsPassword: true
                                        };
                                        if (pending.callback) {
                                            pending.callback(result);
                                        }
                                        if (proc.callback && proc.callback !== pending.callback) {
                                            proc.callback(result);
                                        }
                                        return;
                                    }
                                }
                            }
                        }
                    }

                    if (checkCount >= 6) {
                        immediateCheckTimer.stop();
                        immediateCheckTimer.checkCount = 0;
                    }
                }
            } else {
                immediateCheckTimer.stop();
                immediateCheckTimer.checkCount = 0;
            }
        }
    }

    Process {
        id: rescanProc

        command: ["nmcli", "dev", root.nmcliCommandWifi, "list", "--rescan", "yes"]
        onExited: root.getNetworks() // qmllint disable signal-handler-parameters
    }

    Process {
        id: monitorProc

        running: true
        command: ["nmcli", "monitor"]
        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })
        stdout: SplitParser {
            onRead: connectionEventDebounce.restart()
        }
        onExited: monitorRestartTimer.start() // qmllint disable signal-handler-parameters
    }

    Timer {
        id: monitorRestartTimer

        interval: 2000
        onTriggered: {
            monitorProc.running = true;
        }
    }

    Timer {
        id: connectionEventDebounce

        interval: 120
        onTriggered: root.refreshOnConnectionChange()
    }

    Timer {
        id: liveWifiStateTimer

        running: true
        repeat: true
        interval: 2000
        onTriggered: root.refreshLiveWifiState()
    }

    LoggingCategory {
        id: lc

        name: "caelestia.qml.services.nmcli"
        defaultLogLevel: LoggingCategory.Info
    }

    component CommandProcess: Process {
        id: proc

        property var callback: null
        property list<string> cmdArgs: []
        property bool callbackCalled: false
        property int exitCode: 0

        signal processFinished

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        stdout: StdioCollector {
            id: stdoutCollector
        }

        stderr: StdioCollector {
            id: stderrCollector

            onStreamFinished: {
                const error = text.trim();
                if (error && error.length > 0) {
                    const output = (stdoutCollector && stdoutCollector.text) ? stdoutCollector.text : "";
                    root.handlePasswordRequired(proc, error, output, -1);
                }
            }
        }

        onExited: code => { // qmllint disable signal-handler-parameters
            exitCode = code;

            Qt.callLater(() => {
                if (callbackCalled) {
                    processFinished();
                    return;
                }

                if (proc.callback) {
                    const output = (stdoutCollector && stdoutCollector.text) ? stdoutCollector.text : "";
                    const error = (stderrCollector && stderrCollector.text) ? stderrCollector.text : "";
                    const success = exitCode === 0;
                    const cmdIsConnection = isConnectionCommand(proc.cmdArgs);

                    if (root.handlePasswordRequired(proc, error, output, exitCode)) {
                        processFinished();
                        return;
                    }

                    const needsPassword = cmdIsConnection && root.detectPasswordRequired(error);

                    if (!success && cmdIsConnection && root.pendingConnection) {
                        const failedSsid = root.pendingConnection.ssid;
                        root.connectionFailed(failedSsid);
                    }

                    callbackCalled = true;
                    callback({
                        success: success,
                        output: output,
                        error: error,
                        exitCode: proc.exitCode,
                        needsPassword: needsPassword || false
                    });
                    processFinished();
                } else {
                    processFinished();
                }
            });
        }
    }

    component AccessPoint: QtObject {
        required property var lastIpcObject
        readonly property string ssid: lastIpcObject.ssid
        readonly property string bssid: lastIpcObject.bssid
        readonly property int strength: lastIpcObject.strength
        readonly property int frequency: lastIpcObject.frequency
        readonly property string bandLabel: frequency >= 5925 ? "6 GHz" : frequency >= 4900 ? "5 GHz" : "2.4 GHz"
        readonly property string displayName: `${ssid} (${bandLabel})`
        readonly property bool active: lastIpcObject.active
        readonly property string security: lastIpcObject.security
        readonly property bool isSecure: security.length > 0
    }
}
