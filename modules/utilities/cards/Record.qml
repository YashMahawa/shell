pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services

StyledRect {
    id: root

    required property var props
    required property DrawerVisibilities visibilities
    readonly property alias menuExpanded: recorderModeButton.expanded
    readonly property Item menuPanel: recorderModeButton.menu.panel
    readonly property real nonAnimHeight: btnLayout.implicitHeight + audioRow.implicitHeight + listOrControls.implicitHeight + layout.spacing * 2 + layout.anchors.margins * 2

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

    readonly property string audioMode: ["none", "system", "mic", "both"].includes(props.recordingAudio) ? props.recordingAudio : "none"

    function startRecording(region: bool): void {
        const args = region ? ["-r"] : [];
        if (audioMode !== "none")
            args.push("-a", audioMode);
        Recorder.start(args);
    }

    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    // Poll the recorder only while the drawer is actually showing it.
    LazyLoader {
        active: root.visibilities.utilities

        Ref {
            service: Recorder
        }
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            id: btnLayout

            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: {
                    const h = icon.implicitHeight + Tokens.padding.small * 2;
                    return h - (h % 2);
                }

                radius: Tokens.rounding.full
                color: Recorder.running ? Colours.palette.m3secondary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    text: "screen_record"
                    color: Recorder.running ? Colours.palette.m3onSecondary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Screen Recorder")
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Recorder.paused ? qsTr("Paused") : Recorder.running ? qsTr("Running...") : qsTr("Ready")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                    animate: true
                }
            }

            SplitButton {
                id: recorderModeButton

                disabled: Recorder.running
                menuOnTop: false
                onExpandedChanged: {
                    if (expanded)
                        root.visibilities.utilities = true;
                }

                active: menuItems.find(m => root.props.recordingMode === m.icon + m.text) ?? menuItems[0]
                menu.onItemSelected: item => root.props.recordingMode = item.icon + item.text

                menuItems: [
                    MenuItem {
                        icon: "fullscreen"
                        text: qsTr("Record fullscreen")
                        activeText: qsTr("Fullscreen")
                        onClicked: root.startRecording(false)
                    },
                    MenuItem {
                        icon: "screenshot_region"
                        text: qsTr("Record region")
                        activeText: qsTr("Region")
                        onClicked: root.startRecording(true)
                    }
                ]
            }
        }

        // Audio source for new recordings: off, system output, microphone or both.
        Row {
            id: audioRow

            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall
            opacity: Recorder.running ? 0.5 : 1
            enabled: !Recorder.running

            Repeater {
                model: [
                    { mode: "none", icon: "volume_off", label: qsTr("No audio") },
                    { mode: "system", icon: "speaker", label: qsTr("System") },
                    { mode: "mic", icon: "mic", label: qsTr("Mic") },
                    { mode: "both", icon: "graphic_eq", label: qsTr("Both") }
                ]

                StyledRect {
                    id: chip

                    required property var modelData
                    readonly property bool selected: root.audioMode === modelData.mode

                    width: (audioRow.width - audioRow.spacing * 3) / 4
                    implicitHeight: chipContent.implicitHeight + Tokens.padding.small * 2
                    radius: selected ? Tokens.rounding.full : Tokens.rounding.small
                    color: selected ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHigh

                    Behavior on radius {
                        Anim {}
                    }

                    StateLayer {
                        radius: chip.radius
                        color: chip.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        onClicked: root.props.recordingAudio = chip.modelData.mode
                    }

                    Row {
                        id: chipContent

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.icon
                            fill: chip.selected ? 1 : 0
                            color: chip.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: chip.width > 86
                            text: chip.modelData.label
                            color: chip.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                        }
                    }
                }
            }
        }

        Loader {
            id: listOrControls

            property bool running: Recorder.running

            asynchronous: false
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            sourceComponent: running ? recordingControls : recordingList
            clip: Layout.preferredHeight < implicitHeight

            Behavior on Layout.preferredHeight {
                id: locHeightAnim

                enabled: false

                Anim {}
            }

            Behavior on running {
                SequentialAnimation {
                    Anim {
                        target: listOrControls
                        property: "opacity"
                        to: 0
                        type: Anim.DefaultEffects
                    }
                    PropertyAction {
                        target: locHeightAnim
                        property: "enabled"
                        value: true
                    }
                    PropertyAction {}
                    ParallelAnimation {
                        SequentialAnimation {
                            PauseAnimation {
                                duration: 100
                            }
                            PropertyAction {
                                target: locHeightAnim
                                property: "enabled"
                                value: false
                            }
                        }
                        Anim {
                            target: listOrControls
                            property: "opacity"
                            to: 1
                            type: Anim.SlowEffects
                        }
                    }
                }
            }
        }
    }

    Component {
        id: recordingList

        RecordingList {
            props: root.props
            visibilities: root.visibilities
        }
    }

    Component {
        id: recordingControls

        RowLayout {
            spacing: Tokens.spacing.medium

            StyledRect {
                radius: Tokens.rounding.full
                color: Recorder.paused ? Colours.palette.m3tertiary : Colours.palette.m3error

                implicitWidth: recText.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: recText.implicitHeight + Tokens.padding.large

                StyledText {
                    id: recText

                    anchors.centerIn: parent
                    animate: true
                    text: Recorder.paused ? "PAUSED" : "REC"
                    color: Recorder.paused ? Colours.palette.m3onTertiary : Colours.palette.m3onError
                    font: Tokens.font.mono.small
                }

                Behavior on implicitWidth {
                    Anim {}
                }

                SequentialAnimation on opacity {
                    running: !Recorder.paused
                    alwaysRunToEnd: true
                    loops: Animation.Infinite

                    Anim {
                        from: 1
                        to: 0
                        duration: Tokens.anim.durations.large
                        easing: Tokens.anim.emphasizedAccel
                    }
                    Anim {
                        from: 0
                        to: 1
                        duration: Tokens.anim.durations.extraLarge
                        easing: Tokens.anim.emphasizedDecel
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const elapsed = Recorder.elapsed;

                    const hours = Math.floor(elapsed / 3600);
                    const mins = Math.floor((elapsed % 3600) / 60);
                    const secs = Math.floor(elapsed % 60).toString().padStart(2, "0");

                    let time;
                    if (hours > 0)
                        time = `${hours}:${mins.toString().padStart(2, "0")}:${secs}`;
                    else
                        time = `${mins}:${secs}`;

                    return qsTr("Recording for %1").arg(time);
                }
                font: Tokens.font.body.medium
                elide: Text.ElideMiddle
            }

            ButtonRow {
                spacing: Tokens.spacing.extraSmall

                IconButton {
                    shapeMorph: true
                    isRound: true
                    label.animate: true
                    icon: Recorder.paused ? "play_arrow" : "pause"
                    isToggle: true
                    checked: Recorder.paused
                    type: IconButton.Tonal
                    font: Tokens.font.icon.medium
                    onClicked: {
                        Recorder.togglePause();
                        internalChecked = Recorder.paused;
                    }

                    implicitWidth: {
                        // Ensure even size so icon is centered properly
                        const h = label.implicitHeight + Tokens.padding.large * 2;
                        if (h % 2 !== 0)
                            return h + 1;
                        return h;
                    }
                }

                IconButton {
                    shapeMorph: true
                    isRound: true
                    icon: "stop"
                    inactiveColour: Colours.palette.m3error
                    inactiveOnColour: Colours.palette.m3onError
                    font: Tokens.font.icon.medium
                    onClicked: Recorder.stop()

                    implicitWidth: {
                        // Ensure even size so icon is centered properly
                        const h = label.implicitHeight + Tokens.padding.large * 2;
                        if (h % 2 !== 0)
                            return h + 1;
                        return h;
                    }
                }
            }
        }
    }
}
