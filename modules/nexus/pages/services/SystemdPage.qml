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

    property string selectedScope: "user"
    property bool expertMode: false
    property string searchText: ""
    property string stateFilter: "all"
    property list<var> systemServices: []
    property list<var> userServices: []
    property var busyUnits: ({})
    property string discoveryError: ""
    property string actionError: ""

    property var pendingImpactData: null
    property string currentActionUnit: ""
    property string currentActionType: ""
    property string confirmTypedText: ""

    title: qsTr("Systemd Unit Manager")
    isSubPage: true

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
        discoveryError = "";
        if (!sysProc.running)
            sysProc.running = true;
        if (!userProc.running)
            userProc.running = true;
    }

    function requestServiceAction(unitName: string, action: string, scope: string, itemData: var): void {
        actionError = "";
        currentActionUnit = unitName;
        currentActionType = action;

        const isDestructive = action === "stop" || action === "disable" || action === "restart";
        const isCritical = itemData && itemData.isCritical;
        const isSystemScope = scope === "system";

        if (isDestructive || isCritical || isSystemScope) {
            const newBusy = Object.assign({}, busyUnits);
            newBusy[unitName] = true;
            busyUnits = newBusy;

            impactProc.command = ["python3", `${Quickshell.shellDir}/modules/nexus/scripts/manage_systemd.py`, "impact", unitName, scope];
            impactProc.running = true;
            return;
        }

        confirmAndRunAction(unitName, action, scope);
    }

    function confirmAndRunAction(unitName: string, action: string, scope: string): void {
        const newBusy = Object.assign({}, busyUnits);
        newBusy[unitName] = true;
        busyUnits = newBusy;

        currentActionUnit = unitName;
        currentActionType = action;

        if (scope === "system") {
            actionProc.command = ["pkexec", "systemctl", action, unitName];
        } else {
            actionProc.command = ["systemctl", "--user", action, unitName];
        }

        actionProc.running = true;
    }

    function cancelImpactAction(): void {
        if (currentActionUnit) {
            const newBusy = Object.assign({}, busyUnits);
            delete newBusy[currentActionUnit];
            busyUnits = newBusy;
        }
        pendingImpactData = null;
        confirmTypedText = "";
        currentActionUnit = "";
        currentActionType = "";
    }

    Component.onCompleted: fetchServices()

    Timer {
        interval: 5000
        repeat: true
        running: root.visible && root.pendingImpactData === null
        onTriggered: root.fetchServices()
    }

    Process {
        id: sysProc

        command: ["python3", `${Quickshell.shellDir}/modules/nexus/scripts/manage_systemd.py`, "list", "system"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text);
                    if (Array.isArray(res)) {
                        root.systemServices = res;
                    } else if (res && typeof res === "object") {
                        root.systemServices = res.services || [];
                        if (res.error)
                            root.discoveryError = res.error;
                    }
                } catch (e) {
                    root.systemServices = [];
                    root.discoveryError = "Failed to parse system units response: " + e.message;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    root.discoveryError = text.trim();
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
                    const res = JSON.parse(text);
                    if (Array.isArray(res)) {
                        root.userServices = res;
                    } else if (res && typeof res === "object") {
                        root.userServices = res.services || [];
                        if (res.error)
                            root.discoveryError = res.error;
                    }
                } catch (e) {
                    root.userServices = [];
                    root.discoveryError = "Failed to parse user units response: " + e.message;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    root.discoveryError = text.trim();
                }
            }
        }
    }

    Process {
        id: impactProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(text);
                    root.pendingImpactData = res;
                    root.confirmTypedText = "";
                } catch (e) {
                    root.actionError = "Failed to analyze unit dependency impact: " + e.message;
                }
                if (root.currentActionUnit) {
                    const newBusy = Object.assign({}, root.busyUnits);
                    delete newBusy[root.currentActionUnit];
                    root.busyUnits = newBusy;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    root.actionError = text.trim();
                }
                if (root.currentActionUnit) {
                    const newBusy = Object.assign({}, root.busyUnits);
                    delete newBusy[root.currentActionUnit];
                    root.busyUnits = newBusy;
                }
            }
        }
    }

    Process {
        id: actionProc

        onExited: (exitCode, exitStatus) => {
            if (root.currentActionUnit) {
                const newBusy = Object.assign({}, root.busyUnits);
                delete newBusy[root.currentActionUnit];
                root.busyUnits = newBusy;
                root.currentActionUnit = "";
            }
            if (exitCode !== 0) {
                if (!root.actionError) {
                    root.actionError = qsTr("Command failed with exit code %1").arg(exitCode);
                }
            } else {
                root.actionError = "";
            }
            root.fetchServices();
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    root.actionError = text.trim();
                }
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.medium

        // Header: Scope Switcher & Expert Mode Toggle
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
                    text: qsTr("User Services (%1)").arg(root.userServices.length)
                    icon: "person"
                    type: root.selectedScope === "user" ? TextButton.Filled : TextButton.Tonal
                    onClicked: root.selectedScope = "user"
                }

                IconTextButton {
                    text: qsTr("System Services (%1)").arg(root.systemServices.length)
                    icon: "dns"
                    type: root.selectedScope === "system" ? TextButton.Filled : TextButton.Tonal
                    onClicked: root.selectedScope = "system"
                }

                Item {
                    Layout.fillWidth: true
                }

                RowLayout {
                    visible: root.selectedScope === "system"
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("Expert Mode")
                        font: Tokens.font.label.large
                        color: root.expertMode ? Colours.palette.m3error : Colours.palette.m3onSurface
                    }

                    StyledSwitch {
                        checked: root.expertMode
                        onToggled: root.expertMode = checked
                    }
                }

                IconButton {
                    icon: "refresh"
                    type: IconButton.Tonal
                    tooltipText: qsTr("Refresh services")
                    onClicked: root.fetchServices()
                }
            }
        }

        // Scope Mode Information Banner
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.selectedScope === "system"
            implicitHeight: bannerLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: bannerLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: root.expertMode ? "warning" : "info"
                    color: root.expertMode ? Colours.palette.m3error : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.expertMode ? qsTr("Expert Mode Enabled: Full control over system units is granted. Destructive actions require dependency verification and typed confirmation.") : qsTr("System Services Read-Only View: Non-allowlisted system services cannot be modified without enabling Expert Mode.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Error Banner (Discovery or Action Errors)
        ConnectedRect {
            Layout.fillWidth: true
            visible: root.discoveryError.length > 0 || root.actionError.length > 0
            implicitHeight: errorBannerLayout.implicitHeight + Tokens.padding.medium * 2

            RowLayout {
                id: errorBannerLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "error"
                    color: Colours.palette.m3error
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.discoveryError || root.actionError
                    color: Colours.palette.m3onErrorContainer
                    font: Tokens.font.body.medium
                    wrapMode: Text.WordWrap
                }

                IconButton {
                    icon: "close"
                    type: IconButton.Text
                    onClicked: {
                        root.discoveryError = "";
                        root.actionError = "";
                    }
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
                    text: root.discoveryError.length > 0 ? qsTr("Unable to retrieve systemd units (see error above)") : qsTr("No matching systemd units found")
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

                    readonly property bool isCritical: !!modelData.isCritical
                    readonly property bool isAllowlisted: !!modelData.isAllowlisted
                    readonly property bool canModify: root.selectedScope === "user" || root.expertMode || isAllowlisted

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

                                // Active state badge
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

                                // Critical Service Badge
                                StyledRect {
                                    visible: serviceItem.isCritical
                                    radius: Tokens.rounding.extraSmall
                                    color: Colours.palette.m3errorContainer
                                    implicitWidth: critBadgeText.implicitWidth + Tokens.padding.small * 2
                                    implicitHeight: critBadgeText.implicitHeight + Tokens.padding.extraSmall

                                    StyledText {
                                        id: critBadgeText

                                        anchors.centerIn: parent
                                        text: qsTr("Critical")
                                        color: Colours.palette.m3onErrorContainer
                                        font: Tokens.font.label.small
                                    }
                                }

                                // Read-Only Badge (in system mode when non-allowlisted and expert mode off)
                                StyledRect {
                                    visible: root.selectedScope === "system" && !serviceItem.canModify
                                    radius: Tokens.rounding.extraSmall
                                    color: Colours.tPalette.m3surfaceContainerHighest
                                    implicitWidth: roBadgeText.implicitWidth + Tokens.padding.small * 2
                                    implicitHeight: roBadgeText.implicitHeight + Tokens.padding.extraSmall

                                    StyledText {
                                        id: roBadgeText

                                        anchors.centerIn: parent
                                        text: qsTr("Read-Only")
                                        color: Colours.palette.m3outline
                                        font: Tokens.font.label.small
                                    }
                                }

                                // File State Badge
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
                                    enabled: serviceItem.canModify
                                    icon: "refresh"
                                    type: IconButton.Tonal
                                    tooltipText: serviceItem.canModify ? qsTr("Restart service") : qsTr("Enable Expert Mode to modify system service")
                                    onClicked: root.requestServiceAction(serviceItem.unitName, "restart", root.selectedScope, serviceItem.modelData)
                                }

                                IconButton {
                                    visible: serviceItem.isActive
                                    enabled: serviceItem.canModify
                                    icon: "stop"
                                    type: IconButton.Tonal
                                    tooltipText: serviceItem.canModify ? qsTr("Stop service") : qsTr("Enable Expert Mode to modify system service")
                                    onClicked: root.requestServiceAction(serviceItem.unitName, "stop", root.selectedScope, serviceItem.modelData)
                                }

                                IconButton {
                                    visible: !serviceItem.isActive
                                    enabled: serviceItem.canModify
                                    icon: "play_arrow"
                                    type: IconButton.Tonal
                                    tooltipText: serviceItem.canModify ? qsTr("Start service") : qsTr("Enable Expert Mode to modify system service")
                                    onClicked: root.requestServiceAction(serviceItem.unitName, "start", root.selectedScope, serviceItem.modelData)
                                }

                                IconButton {
                                    visible: serviceItem.fileState === "disabled"
                                    enabled: serviceItem.canModify
                                    icon: "add_circle"
                                    type: IconButton.Text
                                    tooltipText: serviceItem.canModify ? qsTr("Enable on boot") : qsTr("Enable Expert Mode to modify system service")
                                    onClicked: root.requestServiceAction(serviceItem.unitName, "enable", root.selectedScope, serviceItem.modelData)
                                }

                                IconButton {
                                    visible: serviceItem.fileState === "enabled"
                                    enabled: serviceItem.canModify
                                    icon: "do_not_disturb_on"
                                    type: IconButton.Text
                                    tooltipText: serviceItem.canModify ? qsTr("Disable on boot") : qsTr("Enable Expert Mode to modify system service")
                                    onClicked: root.requestServiceAction(serviceItem.unitName, "disable", root.selectedScope, serviceItem.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Dependency & Impact Preview Confirmation Dialog Overlay
    Item {
        id: impactDialogOverlay

        readonly property var impactData: root.pendingImpactData

        anchors.fill: parent
        visible: impactData !== null
        z: 9999

        Rectangle {
            anchors.fill: parent
            color: "#80000000"

            MouseArea {
                anchors.fill: parent
                onClicked: root.cancelImpactAction()
            }
        }

        StyledRect {
            anchors.centerIn: parent
            width: Math.min(520, parent.width - 32)
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
                    text: (impactDialogOverlay.impactData && impactDialogOverlay.impactData.isCriticalChain) ? "warning" : "info"
                    color: (impactDialogOverlay.impactData && impactDialogOverlay.impactData.isCriticalChain) ? Colours.palette.m3error : Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Confirm %1: %2").arg((root.currentActionType || "action").toUpperCase()).arg(impactDialogOverlay.impactData ? impactDialogOverlay.impactData.unit : "")
                    font: Tokens.font.title.medium
                }

                // Impact/Critical Warning Message
                StyledRect {
                    Layout.fillWidth: true
                    visible: impactDialogOverlay.impactData && (impactDialogOverlay.impactData.isCriticalChain || impactDialogOverlay.impactData.isCritical)
                    color: Colours.palette.m3errorContainer
                    radius: Tokens.rounding.medium
                    implicitHeight: warnLayout.implicitHeight + Tokens.padding.medium * 2

                    ColumnLayout {
                        id: warnLayout

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            text: qsTr("CRITICAL SERVICE WARNING")
                            font: Tokens.font.label.large
                            color: Colours.palette.m3onErrorContainer
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: impactDialogOverlay.impactData ? (impactDialogOverlay.impactData.chainReason || impactDialogOverlay.impactData.criticalReason || qsTr("Modifying this service may impact system or session stability.")) : ""
                            color: Colours.palette.m3onErrorContainer
                            font: Tokens.font.body.small
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Active Dependents Section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        text: {
                            const deps = impactDialogOverlay.impactData ? impactDialogOverlay.impactData.activeDependents : [];
                            return (deps && deps.length > 0) ? qsTr("Active Dependent Services Affected (%1):").arg(deps.length) : qsTr("No active dependent services affected.");
                        }
                        font: Tokens.font.label.medium
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    Repeater {
                        model: impactDialogOverlay.impactData ? (impactDialogOverlay.impactData.activeDependents || []) : []

                        delegate: StyledText {
                            required property string modelData
                            text: "• " + modelData
                            font: Tokens.font.body.small
                            color: Colours.palette.m3error
                        }
                    }
                }

                // Typed Confirmation Instruction & Input Field
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Type the exact unit name '%1' below to confirm:").arg(impactDialogOverlay.impactData ? impactDialogOverlay.impactData.unit : "")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurface
                        wrapMode: Text.WordWrap
                    }

                    StyledTextField {
                        id: typedInput

                        Layout.fillWidth: true
                        placeholderText: impactDialogOverlay.impactData ? impactDialogOverlay.impactData.unit : ""
                        text: root.confirmTypedText
                        onTextChanged: root.confirmTypedText = text
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.medium

                    TextButton {
                        text: qsTr("Cancel")
                        type: TextButton.Tonal
                        onClicked: root.cancelImpactAction()
                    }

                    TextButton {
                        text: qsTr("Proceed & Execute")
                        type: TextButton.Filled
                        enabled: {
                            if (!impactDialogOverlay.impactData) return false;
                            const target = (impactDialogOverlay.impactData.unit || "").trim().toLowerCase();
                            const val = root.confirmTypedText.trim().toLowerCase();
                            return val === target || val + ".service" === target;
                        }
                        onClicked: {
                            const unit = impactDialogOverlay.impactData.unit;
                            const act = root.currentActionType;
                            root.pendingImpactData = null;
                            root.confirmTypedText = "";
                            root.confirmAndRunAction(unit, act, root.selectedScope);
                        }
                    }
                }
            }
        }
    }
}

