pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.lock

Item {
    id: root

    required property Pam pam

    readonly property string msg: {
        if (pam.lockMessage)
            return pam.lockMessage;

        if (pam.classifiedMessage && pam.classifiedMessage.text && (pam.state === "error" || pam.state === "fail" || pam.state === "max"))
            return pam.classifiedMessage.text;

        if (pam.fprintState === "error_max" || (pam.fprintState === "error" && pam.fprint.errorTries >= 2))
            return qsTr("Fingerprint reader error (2/2). Please use password.");
        if (pam.fprintState === "error")
            return qsTr("Fingerprint reader error (1/2). Please try again.");

        if (pam.state === "max" && (pam.fprintState === "max" || pam.fprintState === "error_max"))
            return qsTr("Maximum password and fingerprint attempts reached.");
        if (pam.state === "max") {
            if (pam.fprint.available && pam.fprintState !== "error_max" && pam.fprintState !== "max")
                return qsTr("Maximum password attempts reached. Please use fingerprint.");
            return qsTr("Maximum password attempts reached.");
        }
        if (pam.fprintState === "max")
            return qsTr("Maximum fingerprint attempts reached. Please use password.");

        if (pam.state === "fail" || pam.state === "error") {
            if (pam.fprint.available && pam.fprintState !== "error_max" && pam.fprintState !== "max")
                return qsTr("Incorrect password. Please try again or use fingerprint.");
            return qsTr("Incorrect password. Please try again.");
        }
        if (pam.fprintState === "fail")
            return qsTr("Fingerprint not recognized (%1/%2). Please try again or use password.").arg(pam.fprint.tries).arg(Config.lock.maxFprintTries);

        return "";
    }

    readonly property string stateMsg: {
        if (Hypr.kbLayout !== Hypr.defaultKbLayout) {
            if (Hypr.capsLock && Hypr.numLock)
                return qsTr("Caps lock and Num lock are ON.\nKeyboard layout: %1").arg(Hypr.kbLayoutFull);
            if (Hypr.capsLock)
                return qsTr("Caps lock is ON. Kb layout: %1").arg(Hypr.kbLayoutFull);
            if (Hypr.numLock)
                return qsTr("Num lock is ON. Kb layout: %1").arg(Hypr.kbLayoutFull);
            return qsTr("Keyboard layout: %1").arg(Hypr.kbLayoutFull);
        }

        if (Hypr.capsLock && Hypr.numLock)
            return qsTr("Caps lock and Num lock are ON.");
        if (Hypr.capsLock)
            return qsTr("Caps lock is ON.");
        if (Hypr.numLock)
            return qsTr("Num lock is ON.");

        return "";
    }

    property bool stateMsgShouldBeVisible

    onMsgChanged: {
        if (msg) {
            if (message.opacity > 0) {
                message.animate = true;
                message.text = msg;
                message.animate = false;

                exitAnim.stop();
                if (message.scale < 1)
                    appearAnim.restart();
                else {
                    flashAnim.restart();
                    shakeAnim.restart();
                }
            } else {
                message.text = msg;
                exitAnim.stop();
                appearAnim.restart();
                shakeAnim.restart();
            }
        } else {
            appearAnim.stop();
            flashAnim.stop();
            shakeAnim.stop();
            exitAnim.start();
        }
    }

    onStateMsgChanged: {
        if (stateMsg) {
            if (stateMessage.opacity > 0) {
                stateMessage.animate = true;
                stateMessage.text = stateMsg;
                stateMessage.animate = false;
            } else {
                stateMessage.text = stateMsg;
            }
            stateMsgShouldBeVisible = true;
        } else {
            stateMsgShouldBeVisible = false;
        }
    }

    implicitHeight: Math.max(message.implicitHeight, stateMessage.implicitHeight)

    Behavior on implicitHeight {
        Anim {}
    }

    StyledText {
        id: stateMessage

        anchors.left: parent.left
        anchors.right: parent.right

        scale: root.stateMsgShouldBeVisible && !root.msg ? 1 : 0.7
        opacity: root.stateMsgShouldBeVisible && !root.msg ? 1 : 0
        color: Colours.palette.m3onSurfaceVariant

        font: Tokens.font.body.small
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        lineHeight: 1.2

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledText {
        id: message

        anchors.left: parent.left
        anchors.right: parent.right

        scale: 0.7
        opacity: 0
        color: Colours.palette.m3error

        font: Tokens.font.body.small
        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere

        transform: Translate {
            id: textTranslate
            x: 0
        }

        Connections {
            function onFlashMsg(): void {
                exitAnim.stop();
                if (message.scale < 1)
                    appearAnim.restart();
                else
                    flashAnim.restart();
                shakeAnim.restart();
            }

            target: root.pam
        }

        Anim {
            id: appearAnim

            type: Anim.DefaultEffects
            target: message
            properties: "scale,opacity"
            to: 1
            onFinished: {
                flashAnim.restart();
                shakeAnim.restart();
            }
        }

        SequentialAnimation {
            id: shakeAnim

            NumberAnimation { target: textTranslate; property: "x"; to: -10; duration: 40; easing.type: Easing.OutQuad }
            NumberAnimation { target: textTranslate; property: "x"; to: 10; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: textTranslate; property: "x"; to: -6; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: textTranslate; property: "x"; to: 6; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: textTranslate; property: "x"; to: -2; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { target: textTranslate; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
        }

        SequentialAnimation {
            id: flashAnim

            loops: 2

            FlashAnim {
                to: 0.3
                duration: 75
            }
            FlashAnim {
                to: 1
                duration: 75
            }
        }

        ParallelAnimation {
            id: exitAnim

            Anim {
                target: message
                property: "scale"
                to: 0.7
                type: Anim.StandardLarge
            }
            Anim {
                target: message
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
        }
    }

    component FlashAnim: NumberAnimation {
        target: message
        property: "opacity"
        easing.type: Easing.Linear
    }
}
