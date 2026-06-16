import QtQuick
import qs.components
import Caelestia.Services
import qs.services

Flickable {
    id: root

    property bool doneFakeFlick

    maximumFlickVelocity: 3000

    rebound: Transition {
        onRunningChanged: {
            if (!running && !root.doneFakeFlick) {
                root.doneFakeFlick = true;
                root.flick(1, 1);
                root.flick(-1, -1);
                Qt.callLater(() => root.cancelFlick());
            }
        }

        Anim {
            properties: "x,y"
        }
    }


    Connections {
        target: UiScheduler
        function onTick() {
            if (root.doneFakeFlick)
                root.doneFakeFlick = false;
        }
    }

}
