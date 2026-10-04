pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// Apple Music style flowing backdrop built from the album artwork.
//
// The artwork is decoded at 72px, blurred once on the GPU and cached as a
// texture. A fragment shader then blends rotating, drifting copies of it into
// a texture a fraction of the screen size, re-rendered once per display
// frame. A full-resolution present
// pass adds vignette and dither. Per-frame CPU work is a single timer tick.
Item {
    id: root

    property url source
    property bool running: true
    property bool playing: true
    // How far below screen resolution the fluid is simulated. The image is a
    // soft gradient, so this is visually lossless.
    property real downscale: 6
    property real saturation: 1.55
    property real brightness: 1.02

    property int slot: 0
    property url sourceA
    property url sourceB
    property real time: Math.random() * 400
    property real speed: playing ? 1 : 0.35

    onSourceChanged: {
        if (!source.toString())
            return;
        if (slot === 0) {
            sourceB = source;
            slot = 1;
        } else {
            sourceA = source;
            slot = 0;
        }
    }

    Behavior on speed {
        NumberAnimation {
            duration: 1600
            easing.type: Easing.InOutSine
        }
    }

    // Driven by the display's frame clock for perfectly even motion.
    FrameAnimation {
        running: root.running && root.visible
        onTriggered: root.time += frameTime * root.speed
    }

    // Two artwork slots crossfade when the track changes.
    property real mixAmount: slot === 1 ? 1 : 0

    Behavior on mixAmount {
        NumberAnimation {
            duration: 1400
            easing.type: Easing.InOutSine
        }
    }

    component ArtTexture: Item {
        id: art

        property url source
        readonly property alias texture: texture
        readonly property bool ready: image.status === Image.Ready

        width: 72
        height: 72

        Image {
            id: image

            anchors.fill: parent
            source: art.source
            sourceSize: Qt.size(72, 72)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            visible: false
        }

        MultiEffect {
            id: blurred

            anchors.fill: parent
            source: image
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 0.85
            blurMax: 20
            visible: false
        }

        ShaderEffectSource {
            id: texture

            sourceItem: blurred
            hideSource: true
            smooth: true
            textureSize: Qt.size(72, 72)
        }
    }

    ArtTexture {
        id: artA

        source: root.sourceA
        visible: false
    }

    ArtTexture {
        id: artB

        source: root.sourceB
        visible: false
    }

    ShaderEffect {
        id: fluid

        readonly property var artA: artA.texture
        readonly property var artB: artB.texture
        readonly property real time: root.time
        readonly property real aspect: root.width / Math.max(1, root.height)
        readonly property real mixAmount: root.mixAmount
        readonly property real saturation: root.saturation
        readonly property real brightness: root.brightness

        width: Math.max(16, Math.ceil(root.width / root.downscale))
        height: Math.max(16, Math.ceil(root.height / root.downscale))
        fragmentShader: Qt.resolvedUrl("../../assets/shaders/fluid.frag.qsb")
    }

    ShaderEffectSource {
        id: fluidTexture

        sourceItem: fluid
        hideSource: true
        smooth: true
        format: ShaderEffectSource.RGBA16F
    }

    ShaderEffect {
        readonly property var source: fluidTexture
        readonly property real vignette: 0.32

        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("../../assets/shaders/present.frag.qsb")
    }
}
