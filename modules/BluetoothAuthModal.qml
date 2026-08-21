pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Scope {
    id: root

    readonly property bool active: BluetoothAgent.requestActive || (BluetoothAgent.pairingError !== "")

    property string pinInputBuffer: ""

    Component.onCompleted: {
        if (Bluetooth.defaultAdapter?.enabled) {
            BluetoothAgent.registerAgent();
        }
    }

    Connections {
        function onEnabledChanged(): void {
            if (Bluetooth.defaultAdapter?.enabled) {
                BluetoothAgent.registerAgent();
            } else {
                BluetoothAgent.unregisterAgent();
            }
        }

        target: Bluetooth.defaultAdapter
    }

    Connections {
        function onRequestActiveChanged(): void {
            if (BluetoothAgent.requestActive) {
                pinInputBuffer = "";
            }
        }

        target: BluetoothAgent
    }

    Variants {
        model: Screens.screens

        StyledWindow {
            id: win

            required property ShellScreen modelData

            screen: modelData
            name: "bluetooth-auth"
            visible: root.active && (Hypr.focusedMonitor?.name ?? modelData.name) === modelData.name
            color: "transparent"

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors.fill: parent

            MouseArea {
                anchors.fill: parent

                StyledRect {
                    anchors.fill: parent
                    color: Colours.palette.m3scrim
                    opacity: root.active ? 0.6 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            StyledRect {
                id: card

                anchors.centerIn: parent
                width: Math.min(win.width - Tokens.padding.extraLargeIncreased * 2, 440)
                implicitHeight: cardLayout.implicitHeight + Tokens.padding.extraLarge * 2
                radius: Tokens.rounding.extraLarge
                color: Colours.palette.m3surfaceContainerHigh
                scale: root.active ? 1 : 0.8
                opacity: root.active ? 1 : 0

                Component.onCompleted: {
                    if (root.active) {
                        focusTimer.start();
                    }
                }

                Keys.onEscapePressed: {
                    if (BluetoothAgent.pairingError !== "") {
                        BluetoothAgent.clearError();
                    } else {
                        BluetoothAgent.cancelPairing();
                    }
                }

                Connections {
                    function onRequestActiveChanged(): void {
                        if (BluetoothAgent.requestActive) {
                            focusTimer.start();
                        }
                    }

                    target: BluetoothAgent
                }

                Timer {
                    id: focusTimer

                    interval: 50
                    onTriggered: {
                        if (pinInputField.visible) {
                            pinInputField.forceActiveFocus();
                        } else {
                            card.forceActiveFocus();
                        }
                    }
                }

                Elevation {
                    anchors.fill: parent
                    radius: parent.radius
                    z: -1
                    level: 4
                }

                ColumnLayout {
                    id: cardLayout

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.large * 1.5
                    spacing: Tokens.spacing.medium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.medium

                        Item {
                            implicitWidth: 44
                            implicitHeight: 44

                            StyledRect {
                                anchors.fill: parent
                                radius: width / 2
                                color: BluetoothAgent.pairingError !== "" ? Colours.palette.m3errorContainer : Colours.palette.m3primaryContainer
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: {
                                    if (BluetoothAgent.pairingError !== "") {
                                        return "error";
                                    }
                                    if (BluetoothAgent.requestType === "pincode" || BluetoothAgent.requestType === "passkey") {
                                        return "pin";
                                    }
                                    if (BluetoothAgent.requestType === "confirmation") {
                                        return "phonelink_lock";
                                    }
                                    return "bluetooth";
                                }
                                color: BluetoothAgent.pairingError !== "" ? Colours.palette.m3onErrorContainer : Colours.palette.m3onPrimaryContainer
                                fontStyle: Tokens.font.icon.medium
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (BluetoothAgent.pairingError !== "") {
                                        return qsTr("Pairing Failed");
                                    }
                                    if (BluetoothAgent.requestType === "pincode") {
                                        return qsTr("PIN Required");
                                    }
                                    if (BluetoothAgent.requestType === "passkey") {
                                        return qsTr("Passkey Required");
                                    }
                                    if (BluetoothAgent.requestType === "confirmation") {
                                        return qsTr("Confirm Passkey");
                                    }
                                    if (BluetoothAgent.requestType === "displaypin" || BluetoothAgent.requestType === "displaypasskey") {
                                        return qsTr("Pairing Code");
                                    }
                                    if (BluetoothAgent.requestType === "authorization") {
                                        return qsTr("Authorize Connection");
                                    }
                                    return qsTr("Bluetooth Pairing");
                                }
                                font: Tokens.font.title.medium
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (BluetoothAgent.deviceName) {
                                        return BluetoothAgent.deviceAddress ? `${BluetoothAgent.deviceName} (${BluetoothAgent.deviceAddress})` : BluetoothAgent.deviceName;
                                    }
                                    return qsTr("Bluetooth Device");
                                }
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        visible: text.length > 0
                        text: {
                            if (BluetoothAgent.pairingError !== "") {
                                return BluetoothAgent.pairingError;
                            }
                            if (BluetoothAgent.requestType === "pincode") {
                                return qsTr("Enter the PIN required to pair with %1.").arg(BluetoothAgent.deviceName);
                            }
                            if (BluetoothAgent.requestType === "passkey") {
                                return qsTr("Enter the 6-digit numeric passkey for %1.").arg(BluetoothAgent.deviceName);
                            }
                            if (BluetoothAgent.requestType === "confirmation") {
                                return qsTr("Confirm that the passkey shown on %1 matches this code:").arg(BluetoothAgent.deviceName);
                            }
                            if (BluetoothAgent.requestType === "displaypin" || BluetoothAgent.requestType === "displaypasskey") {
                                return qsTr("Enter this passkey on %1 to complete pairing:").arg(BluetoothAgent.deviceName);
                            }
                            if (BluetoothAgent.requestType === "authorization") {
                                return qsTr("Allow %1 to connect to this computer?").arg(BluetoothAgent.deviceName);
                            }
                            return "";
                        }
                        color: BluetoothAgent.pairingError !== "" ? Colours.palette.m3error : Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                        wrapMode: Text.Wrap
                    }

                    StyledInputField {
                        id: pinInputField

                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        visible: BluetoothAgent.pairingError === "" && (BluetoothAgent.requestType === "pincode" || BluetoothAgent.requestType === "passkey")
                        text: root.pinInputBuffer
                        validator: BluetoothAgent.requestType === "passkey" ? IntValidator {
                            bottom: 0
                            top: 999999
                        } : null

                        onTextEdited: txt => root.pinInputBuffer = txt
                        onEditingFinished: {
                            if (root.pinInputBuffer.length > 0) {
                                if (BluetoothAgent.requestType === "passkey") {
                                    BluetoothAgent.respondPasskey(parseInt(root.pinInputBuffer, 10));
                                } else {
                                    BluetoothAgent.respondPinCode(root.pinInputBuffer);
                                }
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.small
                        implicitHeight: codeColumn.implicitHeight + Tokens.padding.medium * 2
                        radius: Tokens.rounding.medium
                        color: Colours.tPalette.m3surfaceContainer
                        visible: BluetoothAgent.pairingError === "" && (BluetoothAgent.requestType === "confirmation" || BluetoothAgent.requestType === "displaypin" || BluetoothAgent.requestType === "displaypasskey")

                        ColumnLayout {
                            id: codeColumn

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.extraSmall

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: {
                                    if (BluetoothAgent.requestType === "displaypin") {
                                        return BluetoothAgent.pinCode;
                                    }
                                    return String(BluetoothAgent.passkey).padStart(6, '0');
                                }
                                font: Tokens.font.mono.large
                                color: Colours.palette.m3primary
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: BluetoothAgent.requestType === "displaypasskey" && BluetoothAgent.passkeyEntered > 0
                                text: qsTr("%1 of 6 digits entered").arg(BluetoothAgent.passkeyEntered)
                                font: Tokens.font.label.small
                                color: Colours.palette.m3outline
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacing.medium
                        spacing: Tokens.spacing.medium

                        TextButton {
                            Layout.fillWidth: true
                            text: BluetoothAgent.pairingError !== "" ? qsTr("Close") : qsTr("Cancel")

                            onClicked: {
                                if (BluetoothAgent.pairingError !== "") {
                                    BluetoothAgent.clearError();
                                } else {
                                    BluetoothAgent.cancelPairing();
                                }
                            }
                        }

                        TextButton {
                            Layout.fillWidth: true
                            visible: BluetoothAgent.pairingError === "" && BluetoothAgent.requestType !== "displaypin" && BluetoothAgent.requestType !== "displaypasskey"
                            enabled: (BluetoothAgent.requestType !== "pincode" && BluetoothAgent.requestType !== "passkey") || root.pinInputBuffer.length > 0
                            type: TextButton.Filled
                            text: {
                                if (BluetoothAgent.requestType === "confirmation") {
                                    return qsTr("Confirm");
                                }
                                if (BluetoothAgent.requestType === "authorization") {
                                    return qsTr("Allow");
                                }
                                return qsTr("Connect");
                            }

                            onClicked: {
                                if (BluetoothAgent.requestType === "passkey") {
                                    BluetoothAgent.respondPasskey(parseInt(root.pinInputBuffer, 10));
                                } else if (BluetoothAgent.requestType === "pincode") {
                                    BluetoothAgent.respondPinCode(root.pinInputBuffer);
                                } else if (BluetoothAgent.requestType === "confirmation") {
                                    BluetoothAgent.respondConfirmation(true);
                                } else if (BluetoothAgent.requestType === "authorization") {
                                    BluetoothAgent.respondAuthorization(true);
                                }
                            }
                        }
                    }
                }

                Behavior on scale {
                    Anim {}
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}
