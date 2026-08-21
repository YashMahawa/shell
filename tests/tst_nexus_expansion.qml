pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Caelestia.Config
import qs.modules.nexus.pages as NexusPages
import qs.modules.nexus.pages.panels as NexusPanels

TestCase {
    id: testCase
    name: "NexusSettingsExpansionTests"

    function test_global_config_schema_paths() {
        // Verify GlobalConfig schema paths and types
        compare(typeof GlobalConfig.bar.edge, "string")
        compare(typeof GlobalConfig.bar.persistent, "boolean")
        compare(typeof GlobalConfig.bar.showOnHover, "boolean")
        compare(typeof GlobalConfig.bar.dragThreshold, "number")

        compare(typeof GlobalConfig.appearance.rounding.scale, "number")
        compare(typeof GlobalConfig.appearance.padding.scale, "number")
        compare(typeof GlobalConfig.appearance.spacing.scale, "number")
        compare(typeof GlobalConfig.appearance.font.scale, "number")

        compare(typeof GlobalConfig.sidebar.enabled, "boolean")
        compare(typeof GlobalConfig.sidebar.dragThreshold, "number")

        compare(typeof GlobalConfig.launcher.enabled, "boolean")
        compare(typeof GlobalConfig.launcher.maxShown, "number")

        compare(typeof GlobalConfig.dashboard.enabled, "boolean")
        compare(typeof GlobalConfig.dashboard.showDashboard, "boolean")
    }

    function test_bar_edge_valid_values() {
        const validEdges = ["left", "top", "right", "bottom"]
        verify(validEdges.indexOf(GlobalConfig.bar.edge) !== -1)
    }
}
