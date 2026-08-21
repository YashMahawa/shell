import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string selectedScope: "system"
    property string searchText: ""
    property string stateFilter: "all"
    property list<var> systemServices: []
    property list<var> userServices: []
    property var busyUnits: ({})
    property var pendingCriticalAction: null
    property string currentActionUnit: ""

    title: qsTr("Systemd Unit Manager")
    isSubPage: true

    readonly property list<string> criticalUnits: [
        "systemd-logind.service",
        "logind.service",
        "dbus.service",
        "polkit.service",
        "systemd-journald.service",
        "display-manager.service",
        "hyprland.service",
        "caelestia.service"
    ]

    readonly property list<var> currentRawServices: selectedScope === "user" ? userServices : systemServices

    readonly property list<var> filteredServices: {
        const list = currentRawServices || [];
        const q = (searchText || "").trim().toLowerCase();
        const sf = stateFilter;

        return list.filter(s => {
            const active = (s.active || "").toLowerCase();
            const sub = (s.sub || "").toLowerCase();

            if (sf === "active" && active !== "active")
                return false;
            if (sf === "inactive" && (active !== "inactive" || sub === "failed"))
                return false;
            if (sf === "failed" && active !== "failed" && sub !== "failed")
                return false;

            if (q.length > 0) {
                const nameMatch = (s.name || "").toLowerCase().includes(q) || (s.unit || "").toLowerCase().includes(q);
                const descMatch = (s.description || "").toLowerCase().includes(q);
                if (!nameMatch && !descMatch)
                    return false;
            }

            return true;
        });
    }

    readonly property int activeCount: {
        return (currentRawServices || []).filter(s => (s.active || "").toLowerCase() === "active").length;
    }

    readonly property int inactiveCount: {
        return (currentRawServices || []).filter(s => (s.active || "").toLowerCase() === "inactive" && (s.sub || "").toLowerCase() !== "failed").length;
    }

    readonly property int failedCount: {
        return (currentRawServices || []).filter(s => (s.active || "").toLowerCase() === "failed" || (s.sub || "").toLowerCase() === "failed").length;
    }

    function fetchServices(): void {
        if (!sysProc.running)
            sysProc.running = true;
        if (!userProc.running)
            userProc.running = true;
    }

    function isCriticalUnit(unitName: string): bool {
        const uLower = (unitName || "").toLowerCase();
        return criticalUnits.some(c => uLower === c || uLower === c.replace(".service", "") || uLower + ".service" === c);
    }

    function executeServiceAction(unitName: string, action: string, scope: string): void {
        if ((action === "stop" || action === "disable") && isCriticalUnit(unitName)) {
            pendingCriticalAction = {
                unit: unitName,
                action: action,
                scope: scope
            };
            return;
        }

        confirmAndRunAction(unitName, action, scope);
    }

    function confirmAndRunAction(unitName: string, action: string, scope: string): void {
        const newBusy = Object.assign({}, busyUnits);
        newBusy[unitName] = true;
        busyUnits = newBusy;

        currentActionUnit = unitName;

        if (scope === "system") {
            actionProc.command = ["pkexec", "systemctl", action, unitName];
        } else {
            actionProc.command = ["systemctl", "--user", action, unitName];
        }

        actionProc.running = true;
    }

    function confirmCriticalAction(): void {
        if (!pendingCriticalAction)
            return;
        const act = pendingCriticalAction;
        pendingCriticalAction = null;
        confirmAndRunAction(act.unit, act.action, act.scope);
    }

    function cancelCriticalAction(): void {
        pendingCriticalAction = null;
    }

    Component.onCompleted: fetchServices()

    Timer {
        interval: 3000
        repeat: true
        running: root.visible
        onTriggered: root.fetchServices()
    }

    Process {
        id: sysProc

        command: ["python3", `${Quickshell.shellDir}/modules/nexus/scripts/manage_systemd.py`, "list", "system"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.systemServices = JSON.parse(text);
                } catch (e) {
                    root.systemServices = [];
                }
            }
        }
    }

    Process {
        id: userProc

        command: ["python3", `${Quickshell.shellDir}/modules/nexus/scripts/manage_systemd.py`, "list", "user"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.userServices = JSON.parse(text);
                } catch (e) {
                    root.userServices = [];
                }
            }
        }
    }

    Process {
        id: actionProc

        onExited: exitCode => {
            if (root.currentActionUnit) {
                const newBusy = Object.assign({}, root.busyUnits);
                delete newBusy[root.currentActionUnit];
                root.busyUnits = newBusy;
                root.currentActionUnit = "";
            }
            root.fetchServices();
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        // Scope Switcher Header
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: scopeLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: scopeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                IconTextButton {
                    text: qsTr("System Services (%1)").arg(root.systemServices.length)
                    icon: "dns"
                    type: root.selectedScope === "system" ? TextButton.Filled : TextButton.Tonal
                    onClicked: root.selectedScope = "system"
                }

                IconTextButton {
                    text: qsTr("User Services (%1)").arg(root.userServices.length)
                    icon: "person"
                    type: root.selectedScope === "user" ? TextButton.Filled : TextButton.Tonal
                    onClicked: root.selectedScope = "user"
                }

                Item {
                    Layout.fillWidth: true
                }

                IconButton {
                    icon: "refresh"
                    type: IconButton.Tonal
                    tooltipText: qsTr("Refresh services")
                    onClicked: root.fetchServices()
                }
            }
        }

        // Search & State Filters
        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: filterLayout.implicitHeight + Tokens.padding.medium * 2

            ColumnLayout {
                id: filterLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "search"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.medium
                    }

                    StyledTextField {
                        id: searchField

                        Layout.fillWidth: true
                        placeholderText: qsTr("Search services by name or description...")
                        text: root.searchText
                        onTextChanged: root.searchText = text
                    }

                    IconButton {
                        visible: root.searchText.length > 0
                        icon: "close"
                        type: IconButton.Text
                        onClicked: {
                            searchField.text = "";
                            root.searchText = "";
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        text: qsTr("All (%1)").arg(root.currentRawServices.length)
                        type: root.stateFilter === "all" ? TextButton.Filled : TextButton.Tonal
                        onClicked: root.stateFilter = "all"
                    }

                    TextButton {
                        text: qsTr("Active (%1)").arg(root.activeCount)
                        type: root.stateFilter === "active" ? TextButton.Filled : TextButton.Tonal
                        onClicked: root.stateFilter = "active"
                    }

                    TextButton {
                        text: qsTr("Inactive (%1)").arg(root.inactiveCount)
                        type: root.stateFilter === "inactive" ? TextButton.Filled : TextButton.Tonal
                        onClicked: root.stateFilter = "inactive"
                    }

                    TextButton {
                        text: qsTr("Failed (%1)").arg(root.failedCount)
                        type: root.stateFilter === "failed" ? TextButton.Filled : TextButton.Tonal
                        onClicked: root.stateFilter = "failed"
                    }
                }
            }
        }

        // Empty state
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.filteredServices.length === 0
            implicitHeight: emptyLayout.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: emptyLayout

                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    color: Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No matching systemd units found")
                    color: Colours.palette.m3outline
                    font: Tokens.font.body.large
                }
            }
        }

        // Service items list
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.filteredServices.length > 0
            spacing: Tokens.spacing.extraSmall / 2

            Repeater {
                model: root.filteredServices

                delegate: ConnectedRect {
                    id: serviceItem

                    required property var modelData
                    required property int index

                    readonly property string unitName: modelData.unit || ""
                    readonly property string activeState: (modelData.active || "").toLowerCase()
                    readonly property string subState: (modelData.sub || "").toLowerCase()
                    readonly property string fileState: (modelData.fileState || "").toLowerCase()
                    readonly property bool isActive: activeState === "active"
                    readonly property bool isFailed: activeState === "failed" || subState === "failed"
                    readonly property bool isBusy: !!root.busyUnits[unitName]

                    first: index === 0
                    last: index === root.filteredServices.length - 1
                    Layout.fillWidth: true
                    implicitHeight: itemContent.implicitHeight + Tokens.padding.medium * 2

                    RowLayout {
                        id: itemContent

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        // Status Icon Badge
                        StyledRect {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: Tokens.rounding.full
                            color: serviceItem.isFailed ? Colours.palette.m3errorContainer : (serviceItem.isActive ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh)

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: serviceItem.isFailed ? "error" : (serviceItem.isActive ? "check_circle" : "pause_circle")
                                color: serviceItem.isFailed ? Colours.palette.m3onErrorContainer : (serviceItem.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3outline)
                                fontStyle: Tokens.font.icon.medium
                            }
                        }

                        // Unit Details
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacing.small

                                StyledText {
                                    text: serviceItem.modelData.name || serviceItem.unitName
                                    font: Tokens.font.title.small
                                    elide: Text.ElideRight
                                }

                                StyledRect {
                                    radius: Tokens.rounding.extraSmall
                                    color: serviceItem.isFailed ? Colours.palette.m3errorContainer : (serviceItem.isActive ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHighest)
                                    implicitWidth: badgeText.implicitWidth + Tokens.padding.small * 2
                                    implicitHeight: badgeText.implicitHeight + Tokens.padding.extraSmall

                                    StyledText {
                                        id: badgeText

                                        anchors.centerIn: parent
                                        text: serviceItem.isFailed ? "failed" : `${serviceItem.activeState} (${serviceItem.subState})`
                                        color: serviceItem.isFailed ? Colours.palette.m3onErrorContainer : (serviceItem.isActive ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant)
                                        font: Tokens.font.label.small
                                    }
                                }

                                StyledRect {
                                    visible: serviceItem.fileState !== "unknown"
                                    radius: Tokens.rounding.extraSmall
                                    color: Colours.tPalette.m3surfaceContainerHighest
                                    implicitWidth: fileBadgeText.implicitWidth + Tokens.padding.small * 2
                                    implicitHeight: fileBadgeText.implicitHeight + Tokens.padding.extraSmall

                                    StyledText {
                                        id: fileBadgeText

                                        anchors.centerIn: parent
                                        text: serviceItem.fileState
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.label.small
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: serviceItem.modelData.description || serviceItem.unitName
                                color: Colours.palette.m3outline
                                font: Tokens.font.body.small
                                elide: Text.ElideRight
                            }
                        }

                        // Action Controls
                        RowLayout {
                            spacing: Tokens.spacing.small

                            Loader {
                                active: serviceItem.isBusy
                                visible: active

                                sourceComponent: LoadingIndicator {
                                    implicitSize: 24
                                }
                            }

                            RowLayout {
                                visible: !serviceItem.isBusy
                                spacing: Tokens.spacing.extraSmall

                                IconButton {
                                    visible: serviceItem.isActive
                                    icon: "refresh"
                                    type: IconButton.Tonal
                                    tooltipText: qsTr("Restart service")
                                    onClicked: root.executeServiceAction(serviceItem.unitName, "restart", root.selectedScope)
                                }

                                IconButton {
                                    visible: serviceItem.isActive
                                    icon: "stop"
                                    type: IconButton.Tonal
                                    tooltipText: qsTr("Stop service")
                                    onClicked: root.executeServiceAction(serviceItem.unitName, "stop", root.selectedScope)
                                }

                                IconButton {
                                    visible: !serviceItem.isActive
                                    icon: "play_arrow"
                                    type: IconButton.Tonal
                                    tooltipText: qsTr("Start service")
                                    onClicked: root.executeServiceAction(serviceItem.unitName, "start", root.selectedScope)
                                }

                                IconButton {
                                    visible: serviceItem.fileState === "disabled"
                                    icon: "add_circle"
                                    type: IconButton.Text
                                    tooltipText: qsTr("Enable on boot")
                                    onClicked: root.executeServiceAction(serviceItem.unitName, "enable", root.selectedScope)
                                }

                                IconButton {
                                    visible: serviceItem.fileState === "enabled"
                                    icon: "do_not_disturb_on"
                                    type: IconButton.Text
                                    tooltipText: qsTr("Disable on boot")
                                    onClicked: root.executeServiceAction(serviceItem.unitName, "disable", root.selectedScope)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Critical Service Confirmation Dialog Overlay
    Item {
        id: criticalDialogOverlay

        anchors.fill: parent
        visible: root.pendingCriticalAction !== null
        z: 9999

        Rectangle {
            anchors.fill: parent
            color: "#80000000"

            MouseArea {
                anchors.fill: parent
                onClicked: root.cancelCriticalAction()
            }
        }

        StyledRect {
            anchors.centerIn: parent
            width: Math.min(480, parent.width - 32)
            implicitHeight: dialogLayout.implicitHeight + Tokens.padding.large * 2
            color: Colours.tPalette.m3surfaceContainerHigh
            radius: Tokens.rounding.large

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: dialogLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "warning"
                    color: Colours.palette.m3error
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Critical System Service Warning")
                    font: Tokens.font.title.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Modifying critical service '%1' may cause system or desktop session instability. Are you sure you want to proceed?").arg(root.pendingCriticalAction ? root.pendingCriticalAction.unit : "")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.medium

                    TextButton {
                        text: qsTr("Cancel")
                        type: TextButton.Tonal
                        onClicked: root.cancelCriticalAction()
                    }

                    TextButton {
                        text: qsTr("Proceed")
                        type: TextButton.Filled
                        onClicked: root.confirmCriticalAction()
                    }
                }
            }
        }
    }
}
