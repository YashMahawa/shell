pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running
    readonly property ShellScreen captureScreen: Quickshell.screens.find(
        candidate => candidate === root.screen
    ) ?? null

    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name
    contentItem.implicitWidth: root.screen?.width ?? 1920
    contentItem.implicitHeight: root.screen?.height ?? 1080
    contentItem.width: root.screen?.width ?? 1920
    contentItem.height: root.screen?.height ?? 1080

    color: "transparent"

    function prepareContent(): void {
        background.opacity = 0;
        lockContent.opacity = 1;
        lockContent.scale = 0;
        lockContent.rotation = 180;
        lockContent.implicitWidth = lockContent.size;
        lockContent.implicitHeight = lockContent.size;
        lockBg.radius = lockContent.radius;
        lockIcon.opacity = 1;
        lockIcon.rotation = 180;
        content.opacity = 0;
        content.scale = 0;
    }

    function revealContent(): void {
        background.opacity = 1;
        lockContent.opacity = 1;
        lockContent.scale = 1;
        lockContent.rotation = 360;
        lockContent.implicitWidth = lockContent.expandedWidth;
        lockContent.implicitHeight = lockContent.expandedHeight;
        lockBg.radius = lockContent.Tokens.rounding.extraLarge * 1.5;
        lockIcon.opacity = 0;
        content.opacity = 1;
        content.scale = 1;
    }

    Connections {
        function onLockedChanged(): void {
            if (!root.lock.locked)
                return;

            root.prepareContent();
            initAnim.restart();
            revealFallback.restart();
        }

        function onUnlock(): void {
            unlockAnim.start();
        }

        target: root.lock
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            Anim {
                target: lockContent
                properties: "implicitWidth,implicitHeight"
                to: lockContent.size
            }
            Anim {
                target: lockBg
                property: "radius"
                to: lockContent.radius
            }
            Anim {
                target: content
                property: "scale"
                to: 0
            }
            Anim {
                target: content
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
            Anim {
                target: lockIcon
                property: "opacity"
                to: 1
                type: Anim.StandardLarge
            }
            Anim {
                target: background
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Tokens.anim.durations.small
                }
                Anim {
                    type: Anim.Standard
                    target: lockContent
                    property: "opacity"
                    to: 0
                }
            }
        }
        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    ParallelAnimation {
        id: initAnim

        running: true
        onStopped: root.revealContent()

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: lockContent
                    property: "scale"
                    to: 1
                    type: Anim.FastSpatial
                }
                Anim {
                    target: lockContent
                    property: "rotation"
                    to: 360
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing: Tokens.anim.standardAccel
                }
            }
            ParallelAnimation {
                Anim {
                    target: lockIcon
                    property: "rotation"
                    to: 360
                    easing: Tokens.anim.standardDecel
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: lockIcon
                    property: "opacity"
                    to: 0
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: content
                    property: "opacity"
                    to: 1
                }
                Anim {
                    target: content
                    property: "scale"
                    to: 1
                }
                Anim {
                    target: lockBg
                    property: "radius"
                    to: lockContent.Tokens.rounding.extraLarge * 1.5
                }
                Anim {
                    target: lockContent
                    property: "implicitWidth"
                    to: lockContent.expandedWidth
                }
                Anim {
                    target: lockContent
                    property: "implicitHeight"
                    to: lockContent.expandedHeight
                }
            }
        }
    }

    Timer {
        id: revealFallback

        interval: 1800
        running: true
        repeat: false
        onTriggered: root.revealContent()
    }

    ScreencopyView {
        id: background

        anchors.fill: parent
        // An unlocked shell does not need a continuous screen capture. More
        // importantly, clearing this before an output disappears prevents the
        // ext-image-copy object from retaining a destroyed Wayland output.
        captureSource: root.lock.locked ? root.captureScreen : null
        opacity: 0
        z: -1

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
        }
    }

    Item {
        id: lockContent

        readonly property int size: lockIcon.implicitHeight + Tokens.padding.large * 4
        readonly property int radius: size / 4 * Tokens.rounding.scale
        readonly property real screenHeight: root.screen?.height ?? (root.height || 1080)
        readonly property real expandedRatio: Number.isFinite(Tokens.sizes.lock.ratio) ? Tokens.sizes.lock.ratio : 16 / 9
        readonly property real expandedWidth: screenHeight * Tokens.sizes.lock.heightMult * expandedRatio
        readonly property real expandedHeight: screenHeight * Tokens.sizes.lock.heightMult

        anchors.centerIn: parent
        implicitWidth: size
        implicitHeight: size
        z: 1

        rotation: 180
        scale: 0

        StyledRect {
            id: lockBg

            anchors.fill: parent
            color: Colours.palette.m3surface
            radius: parent.radius
            // The captured desktop behind this card is already strongly
            // blurred. Keep the card translucent even when ordinary shell
            // transparency is disabled so the lock UI remains a calm glass
            // surface instead of a harsh opaque slab.
            opacity: Colours.transparency.enabled
                ? Math.min(0.84, Math.max(0.72, Colours.transparency.base))
                : 0.82

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 15
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.7)
            }
        }

        MaterialIcon {
            id: lockIcon

            anchors.centerIn: parent
            text: "lock"
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(4).weight(Font.Bold).build()
            rotation: 180
        }

        Content {
            id: content

            anchors.centerIn: parent
            width: Math.max(0, lockContent.expandedWidth - Tokens.padding.extraLargeIncreased)
            height: Math.max(0, lockContent.expandedHeight - Tokens.padding.extraLargeIncreased)

            lock: root
            opacity: 0
            scale: 0
        }
    }
}
