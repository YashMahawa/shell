pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Internal
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Scope {
    id: root

    FileView {
        path: "/var/tmp/caelestia-greeter-theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            Colours.load(text(), false);
        }
    }

    QsWindow {
        id: greeterWindow

        property date now: new Date()

        width: 1920
        height: 1080
        color: Colours.palette.m3background
        anchor.edges: AnchorEdge.All
        exclusiveZone: -1 // fullscreen

        Item {
            anchors.fill: parent

            Image {
                id: background

                anchors.fill: parent
                source: Wallpapers.current ? `file://${Wallpapers.current}` : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                    blurMultiplier: 1
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colours.palette.m3background, background.status === Image.Ready ? 0.35 : 1)
            }

            Column {
                id: mainColumn
                anchors.centerIn: parent
                width: Math.min(parent.width - Tokens.padding.large * 2, 460)
                spacing: Tokens.spacing.medium

                property var sessions: [
                    { name: "Caelestia", cmd: ["caelestia-shell"] },
                    { name: "Hyprland", cmd: ["Hyprland"] }
                ]
                property int selectedSession: 0

                StyledRect {
                    width: parent.width
                    color: Colours.tPalette.m3surfaceContainer
                    radius: Tokens.rounding.extraLarge
                    implicitHeight: panelColumn.implicitHeight + Tokens.padding.extraLarge * 2

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        blurMax: 18
                        shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.65)
                    }

                    Column {
                        id: panelColumn

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.extraLarge
                        spacing: Tokens.spacing.medium

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatTime(greeterWindow.now, GlobalConfig.services.useTwelveHourClock ? "h:mm AP" : "hh:mm")
                            font: Tokens.font.display.large
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(greeterWindow.now, "dddd, d MMMM")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3outline
                        }

                        StyledRect {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 84
                            height: 84
                            radius: width / 2
                            color: Colours.palette.m3primaryContainer

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "person"
                                color: Colours.palette.m3onPrimaryContainer
                                fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.35).build()
                            }
                        }

                        StyledTextField {
                            id: userField

                            anchors.left: parent.left
                            anchors.right: parent.right
                            placeholderText: "Username"
                            onAccepted: passwordField.forceActiveFocus()
                        }

                        StyledTextField {
                            id: passwordField

                            anchors.left: parent.left
                            anchors.right: parent.right
                            placeholderText: "Password"
                            echoMode: TextInput.Password
                            onAccepted: {
                                statusMsg.text = "Authenticating...";
                                greetd.authenticate(userField.text, passwordField.text);
                                passwordField.text = "";
                            }
                        }

                        Row {
                            spacing: Tokens.spacing.medium
                            anchors.horizontalCenter: parent.horizontalCenter

                            Repeater {
                                model: mainColumn.sessions

                                StyledRadioButton {
                                    text: modelData.name
                                    checked: mainColumn.selectedSession === index
                                    onClicked: mainColumn.selectedSession = index
                                }
                            }
                        }

                        StyledText {
                            id: statusMsg

                            anchors.left: parent.left
                            anchors.right: parent.right
                            horizontalAlignment: Text.AlignHCenter
                            color: Colours.palette.m3error
                            text: ""
                            wrapMode: Text.WordWrap
                        }

                        ButtonBase {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Login"
                            onClicked: {
                                statusMsg.text = "Authenticating...";
                                greetd.authenticate(userField.text, passwordField.text);
                                passwordField.text = "";
                            }
                        }
                    }
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Tokens.spacing.large
                spacing: Tokens.spacing.medium

                StyledRect {
                    width: rebootButton.implicitWidth + Tokens.padding.medium * 2
                    height: rebootButton.implicitHeight + Tokens.padding.small * 2
                    radius: height / 2
                    color: Colours.tPalette.m3surfaceContainer

                    ButtonBase {
                        id: rebootButton

                        anchors.centerIn: parent
                        text: "Reboot"
                        onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                    }
                }
                StyledRect {
                    width: shutdownButton.implicitWidth + Tokens.padding.medium * 2
                    height: shutdownButton.implicitHeight + Tokens.padding.small * 2
                    radius: height / 2
                    color: Colours.tPalette.m3surfaceContainer

                    ButtonBase {
                        id: shutdownButton

                        anchors.centerIn: parent
                        text: "Shutdown"
                        onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                    }
                }
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: greeterWindow.now = new Date()
        }
    }

    GreetdManager {
        id: greetd
        onAuthSuccess: {
            statusMsg.text = "Success!";
            // Start the default session
            greetd.startSession(mainColumn.sessions[mainColumn.selectedSession].cmd);
        }
        onAuthFailed: reason => {
            statusMsg.text = "Login Failed: " + reason;
            passwordField.text = "";
        }
        onStatus: message => {
            statusMsg.text = message;
        }
    }
}
