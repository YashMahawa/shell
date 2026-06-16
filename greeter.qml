pragma ComponentBehavior: Bound

import QtQuick
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
        width: 1920
        height: 1080
        color: Colours.palette.m3background
        anchor.edges: AnchorEdge.All
        exclusiveZone: -1 // fullscreen

        Rectangle {
            anchors.fill: parent
            color: Colours.palette.m3background

            Column {
                anchors.centerIn: parent
                spacing: Tokens.spacing.large

                StyledTextField {
                    id: userField
                    placeholderText: "Username"
                    onAccepted: {
                        passwordField.forceActiveFocus();
                    }
                }

                StyledTextField {
                    id: passwordField
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    onAccepted: {
                        statusMsg.text = "Authenticating...";
                        greetd.authenticate(userField.text, passwordField.text);
                        passwordField.text = "";
                    }
                }

                StyledTextField {
                    id: sessionCommandField
                    placeholderText: "Session Command"
                    text: "caelestia-shell"
                }

                StyledText {
                    id: statusMsg
                    color: Colours.palette.m3error
                    text: ""
                }

                Row {
                    spacing: Tokens.spacing.medium
                    anchors.horizontalCenter: parent.horizontalCenter

                    ButtonBase {
                        text: "Login"
                        onClicked: {
                            statusMsg.text = "Authenticating...";
                            greetd.authenticate(userField.text, passwordField.text);
                            passwordField.text = "";
                        }
                    }
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Tokens.spacing.large
                spacing: Tokens.spacing.medium

                ButtonBase {
                    text: "Reboot"
                    onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                }
                ButtonBase {
                    text: "Shutdown"
                    onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                }
            }
        }
    }

    GreetdManager {
        id: greetd
        onAuthSuccess: {
            statusMsg.text = "Success!";
            // Start the default session
            greetd.startSession(sessionCommandField.text.split(" ")); // Example
        }
        onAuthFailed: reason => {
            statusMsg.text = "Login Failed: " + reason;
            passwordField.text = "";
        }
    }
}
