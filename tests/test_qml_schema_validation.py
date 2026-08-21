#!/usr/bin/env python3
import os
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

class TestQmlSchemaAndSettings(unittest.TestCase):
    def test_no_config_drift_in_nexus_pages(self):
        """Ensure nexus settings pages write and read from GlobalConfig rather than mixing Config and GlobalConfig."""
        pages_dir = REPO_ROOT / "modules" / "nexus" / "pages"
        for qml_file in pages_dir.glob("**/*.qml"):
            content = qml_file.read_text()
            # Skip wallandstyle subpages which read per-screen nexus wallpapers per row
            if "wallandstyle" in str(qml_file):
                continue
            # Look for controls binding property checked/value to Config.<group>.<prop> while writing to GlobalConfig.<group>.<prop>
            mismatches = re.findall(r'checked:\s*Config\.(\w+)\.([^\n]+)', content)
            self.assertEqual(len(mismatches), 0, f"Found Config read mismatch in {qml_file.name}: {mismatches}")

    def test_selectrow_active_item_types(self):
        """Ensure SelectRow active properties bind to MenuItem instances rather than localized string literals."""
        taskbar_panel = REPO_ROOT / "modules" / "nexus" / "pages" / "panels" / "TaskbarPanel.qml"
        content = taskbar_panel.read_text()
        # Verify active property returns an id (e.g. itemLeft, itemTop) instead of qsTr("...")
        self.assertNotIn('return qsTr("Left")', content)
        self.assertIn('return itemLeft', content)

    def test_updates_page_real_provider(self):
        """Ensure UpdatesPage uses real Process update checks and contains no fake timer success assignments."""
        updates_page = REPO_ROOT / "modules" / "nexus" / "pages" / "UpdatesPage.qml"
        content = updates_page.read_text()
        # Verify checkTimer is deleted or removed
        self.assertNotIn('id: checkTimer', content)
        self.assertIn('property Process updateCheckProcess: Process', content)
        self.assertIn('UNAVAILABLE', content)
        self.assertIn('hasError', content)

    def test_plugins_page_real_statuses(self):
        """Ensure PluginsPage queries real service singletons for status output."""
        plugins_page = REPO_ROOT / "modules" / "nexus" / "pages" / "PluginsPage.qml"
        content = plugins_page.read_text()
        self.assertIn('Audio.sink', content)
        self.assertIn('Nmcli.wifiEnabled', content)
        self.assertIn('VPN.active', content)
        self.assertIn('Weather.cc', content)
        self.assertIn('Brightness.monitors', content)

if __name__ == "__main__":
    unittest.main()
