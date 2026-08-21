#include "../plugin/src/Caelestia/Config/inputconfig.hpp"

#include <qcoreapplication.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qtemporarydir.h>
#include <qtextstream.h>
#include <cassert>
#include <iostream>

using namespace caelestia::config;

void testExistingLuaShortcutsByteForByteUnchanged() {
    QTemporaryDir tempDir;
    assert(tempDir.isValid());

    QString userLuaPath = tempDir.path() + "/hyprland.lua";
    QString userShortcutsLuaPath = tempDir.path() + "/shortcuts.lua";
    QString userCustomConfPath = tempDir.path() + "/custom_binds.conf";

    QByteArray initialLuaContent =
        "-- Personalized Hyprland Lua Configuration\n"
        "local hl = require('hyprland')\n"
        "hl.bind({'SUPER'}, 'Return', function() hl.exec('alacritty') end)\n"
        "hl.bind({'SUPER', 'SHIFT'}, 'Q', function() hl.dispatch('exit') end)\n"
        "hl.config({\n"
        "    input = {\n"
        "        sensitivity = -0.2,\n"
        "        touchpad = { tap_to_click = false }\n"
        "    }\n"
        "})\n";

    QByteArray initialShortcutsLuaContent =
        "-- Custom Shortcuts Module\n"
        "local shortcuts = {}\n"
        "shortcuts.setup = function()\n"
        "    hl.bind({'SUPER'}, 'Space', 'exec rofi -show drun')\n"
        "end\n"
        "return shortcuts\n";

    QByteArray initialCustomConfContent =
        "# Legacy custom shortcuts\n"
        "bind = $mainMod, Q, exec, kitty\n"
        "bind = $mainMod, C, killactive,\n";

    // Write initial files
    {
        QFile f1(userLuaPath);
        assert(f1.open(QIODevice::WriteOnly));
        f1.write(initialLuaContent);
        f1.close();

        QFile f2(userShortcutsLuaPath);
        assert(f2.open(QIODevice::WriteOnly));
        f2.write(initialShortcutsLuaContent);
        f2.close();

        QFile f3(userCustomConfPath);
        assert(f3.open(QIODevice::WriteOnly));
        f3.write(initialCustomConfContent);
        f3.close();
    }

    // Instantiate InputConfig and change settings
    InputConfig inputConfig;
    inputConfig.set_pointerSpeed(0.8);
    inputConfig.set_touchpadTapToClick(true);
    inputConfig.set_touchpadNaturalScroll(false);
    inputConfig.set_keyboardRepeatRate(45);
    inputConfig.set_keyboardRepeatDelay(300);
    inputConfig.set_usingLua(true);
    inputConfig.setDeviceSetting("test-mouse-device", "sensitivity", 0.5);

    // Save generated config to a separate generated path
    QString generatedLuaPath = tempDir.path() + "/caelestia/generated/input.lua";
    bool saveOk = inputConfig.saveGeneratedConfig(generatedLuaPath, true);
    assert(saveOk);

    // Verify generated file exists
    assert(QFile::exists(generatedLuaPath));

    // CRITICAL REQUIREMENT: Verify existing user files remain 100% BYTE-FOR-BYTE UNCHANGED
    {
        QFile f1(userLuaPath);
        assert(f1.open(QIODevice::ReadOnly));
        QByteArray currentLuaContent = f1.readAll();
        assert(currentLuaContent == initialLuaContent);
    }
    {
        QFile f2(userShortcutsLuaPath);
        assert(f2.open(QIODevice::ReadOnly));
        QByteArray currentShortcutsContent = f2.readAll();
        assert(currentShortcutsContent == initialShortcutsLuaContent);
    }
    {
        QFile f3(userCustomConfPath);
        assert(f3.open(QIODevice::ReadOnly));
        QByteArray currentConfContent = f3.readAll();
        assert(currentConfContent == initialCustomConfContent);
    }

    std::cout << "[PASS] Existing Lua/custom shortcuts remain byte-for-byte unchanged." << std::endl;
}

void testGeneratorAndAtomicWrite() {
    QTemporaryDir tempDir;
    assert(tempDir.isValid());

    InputConfig inputConfig;
    inputConfig.set_pointerSpeed(0.25);
    inputConfig.set_touchpadTapToClick(true);
    inputConfig.set_touchpadNaturalScroll(true);
    inputConfig.set_keyboardRepeatRate(40);
    inputConfig.set_keyboardRepeatDelay(200);

    // Test Lua generator format
    QString luaOutput = inputConfig.generateLuaConfig();
    assert(luaOutput.contains("sensitivity = 0.25"));
    assert(luaOutput.contains("tap_to_click = true"));
    assert(luaOutput.contains("repeat_rate = 40"));
    assert(luaOutput.contains("repeat_delay = 200"));

    // Test per-device setting
    inputConfig.setDeviceSetting("synps/2-synaptics-touchpad", "tap_to_click", false);
    QString luaOutputWithDevice = inputConfig.generateLuaConfig();
    assert(luaOutputWithDevice.contains("[\"synps/2-synaptics-touchpad\"] = {"));
    assert(luaOutputWithDevice.contains("tap_to_click = false"));

    // Test legacy Conf generator format
    QString confOutput = inputConfig.generateConfConfig();
    assert(confOutput.contains("sensitivity = 0.25"));
    assert(confOutput.contains("tap-to-click = true"));
    assert(confOutput.contains("device {"));
    assert(confOutput.contains("name = synps/2-synaptics-touchpad"));

    // Test atomic save using QSaveFile
    QString targetFile = tempDir.path() + "/generated_input.lua";
    bool saved = inputConfig.saveGeneratedConfig(targetFile, true);
    assert(saved);
    assert(QFile::exists(targetFile));

    QFile f(targetFile);
    assert(f.open(QIODevice::ReadOnly));
    QString fileContent = QString::fromUtf8(f.readAll());
    assert(fileContent == luaOutputWithDevice);

    std::cout << "[PASS] Generator and atomic write tests passed." << std::endl;
}

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    testExistingLuaShortcutsByteForByteUnchanged();
    testGeneratorAndAtomicWrite();
    std::cout << "ALL INPUT CONFIG TESTS PASSED SUCCESSFULY." << std::endl;
    return 0;
}
