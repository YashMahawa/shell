import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property var modelData
    required property DrawerVisibilities visibilities

    implicitHeight: Tokens.sizes.launcher.itemHeight
    anchors.left: parent?.left
    anchors.right: parent?.right

    function activate(): void {
        if (modelData.kind === "app")
            Apps.launch(modelData.app);
        else
            // Keep viewers outside the shell service's crash/restart cgroup.
            Quickshell.execDetached(["app2unit", "--", "xdg-open", modelData.path]);
        visibilities.launcher = false;
    }

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: root.activate()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        Loader {
            id: visual
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height * 0.8
            height: width
            sourceComponent: root.modelData.kind === "app" ? appIcon : fileIcon
        }

        Component {
            id: appIcon
            IconImage {
                asynchronous: true
                source: Quickshell.iconPath(root.modelData.icon, "image-missing")
                implicitSize: visual.width
            }
        }

        Component {
            id: fileIcon
            MaterialIcon {
                text: root.modelData.kind === "folder" ? "folder" : root.modelData.mime?.startsWith("image/") ? "image" : root.modelData.mime === "application/pdf" ? "picture_as_pdf" : "draft"
                color: root.modelData.kind === "folder" ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
                anchors.centerIn: parent
            }
        }

        Item {
            anchors.left: visual.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: typeLabel.left
            anchors.rightMargin: Tokens.spacing.medium
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: title.implicitHeight + subtitle.implicitHeight

            StyledText {
                id: title
                width: parent.width
                text: root.modelData.name ?? ""
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }
            StyledText {
                id: subtitle
                anchors.top: title.bottom
                width: parent.width
                text: root.modelData.subtitle ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                elide: Text.ElideMiddle
            }
        }

        StyledText {
            id: typeLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.modelData.kind === "app" ? qsTr("App") : root.modelData.kind === "folder" ? qsTr("Folder") : qsTr("File")
            font: Tokens.font.label.small
            color: Colours.palette.m3primary
        }
    }
}
