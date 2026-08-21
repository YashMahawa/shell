pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Voice typing")

    readonly property var storedKeys: Voice.storedKeys
    property string statusMessage: ""
    property bool statusError: false

    function refresh(): void {
        Voice.refreshKeys();
    }

    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            text: qsTr("Gemini API keys")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.medium
            Layout.rightMargin: Tokens.padding.medium
            Layout.bottomMargin: Tokens.spacing.small
            text: qsTr("Up to three keys are encrypted by the desktop Secret Service. A different key is chosen randomly for each transcription; another key is tried automatically if it fails.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.Wrap
        }

        Repeater {
            model: 3

            ConnectedRect {
                id: keyRow
                required property int index
                Layout.fillWidth: true
                implicitHeight: keyLayout.implicitHeight + Tokens.padding.medium * 2
                first: index === 0
                last: index === 2

                RowLayout {
                    id: keyLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    ColumnLayout {
                        Layout.preferredWidth: 125
                        spacing: 0
                        StyledText {
                            text: qsTr("API key %1").arg(keyRow.index + 1)
                            font: Tokens.font.body.small
                        }
                        StyledText {
                            text: root.storedKeys[keyRow.index] ? qsTr("Stored securely") : qsTr("Not configured")
                            color: root.storedKeys[keyRow.index] ? Colours.palette.m3primary : Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Tokens.rounding.large
                        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                        StyledTextField {
                            id: keyField
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.medium
                            anchors.rightMargin: Tokens.padding.medium
                            echoMode: TextInput.Password
                            placeholderText: root.storedKeys[keyRow.index] ? qsTr("Enter a replacement key") : qsTr("Paste Gemini API key")
                            onAccepted: saveButton.clicked()
                        }
                    }

                    TextButton {
                        id: saveButton
                        text: qsTr("Save")
                        enabled: keyField.text.length >= 20
                        onClicked: {
                            Voice.storeKey(keyRow.index + 1, keyField.text);
                            keyField.text = "";
                            root.statusMessage = qsTr("Voice settings saved securely");
                            root.statusError = false;
                        }
                    }

                    TextButton {
                        text: qsTr("Remove")
                        enabled: root.storedKeys[keyRow.index]
                        onClicked: {
                            Voice.clearKey(keyRow.index + 1);
                            root.statusMessage = qsTr("Voice settings saved securely");
                            root.statusError = false;
                        }
                    }
                }
            }
        }

        SectionHeader {
            text: qsTr("Transcription prompt")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: promptColumn.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: promptColumn
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("This prompt controls cleanup, corrections and silence handling. It is not a secret.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.Wrap
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 170
                    radius: Tokens.rounding.large
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)

                    TextArea {
                        id: promptField
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        text: Voice.prompt
                        color: Colours.palette.m3onSurface
                        selectionColor: Colours.palette.m3primary
                        selectedTextColor: Colours.palette.m3onPrimary
                        font: Tokens.font.body.small
                        wrapMode: TextEdit.Wrap
                        background: null
                    }
                }

                TextButton {
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("Save prompt")
                    enabled: promptField.text.length >= 40
                    onClicked: {
                        Voice.savePrompt(promptField.text);
                        root.statusMessage = qsTr("Voice settings saved securely");
                        root.statusError = false;
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.medium
            visible: root.statusMessage.length > 0
            text: root.statusMessage
            color: root.statusError ? Colours.palette.m3error : Colours.palette.m3primary
            font: Tokens.font.body.small
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
