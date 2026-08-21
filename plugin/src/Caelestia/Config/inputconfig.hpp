#pragma once

#include "configobject.hpp"
#include <qvariant.h>

namespace caelestia::config {

class InputConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(double, pointerSpeed, 0.0)
    CONFIG_PROPERTY(bool, touchpadTapToClick, true)
    CONFIG_PROPERTY(bool, touchpadNaturalScroll, true)
    CONFIG_PROPERTY(int, keyboardRepeatRate, 35)
    CONFIG_PROPERTY(int, keyboardRepeatDelay, 250)
    CONFIG_PROPERTY(bool, usingLua, false)
    CONFIG_PROPERTY(QVariantMap, devices, {})

    // Aliases
    Q_PROPERTY(double mouseSensitivity READ pointerSpeed WRITE set_pointerSpeed NOTIFY pointerSpeedChanged)
    Q_PROPERTY(bool tapToClick READ touchpadTapToClick WRITE set_touchpadTapToClick NOTIFY touchpadTapToClickChanged)
    Q_PROPERTY(bool naturalScroll READ touchpadNaturalScroll WRITE set_touchpadNaturalScroll NOTIFY touchpadNaturalScrollChanged)
    Q_PROPERTY(int repeatRate READ keyboardRepeatRate WRITE set_keyboardRepeatRate NOTIFY keyboardRepeatRateChanged)
    Q_PROPERTY(int repeatDelay READ keyboardRepeatDelay WRITE set_keyboardRepeatDelay NOTIFY keyboardRepeatDelayChanged)

public:
    explicit InputConfig(QObject* parent = nullptr);

    // Per-device settings helpers
    Q_INVOKABLE void setDeviceSetting(const QString& deviceName, const QString& key, const QVariant& value);
    Q_INVOKABLE QVariant deviceSetting(const QString& deviceName, const QString& key, const QVariant& defaultValue = QVariant()) const;
    Q_INVOKABLE void removeDeviceSetting(const QString& deviceName, const QString& key = QString());

    // Version-aware Lua / Config generator
    [[nodiscard]] Q_INVOKABLE QString generateLuaConfig() const;
    [[nodiscard]] Q_INVOKABLE QString generateConfConfig() const;
    [[nodiscard]] Q_INVOKABLE QString generateConfig(bool forceLua = false) const;

    // Atomic write to disk for next boot using QSaveFile
    Q_INVOKABLE bool saveGeneratedConfig(const QString& customFilePath = QString(), bool forceLua = false);

    // Live validated socket IPC
    Q_INVOKABLE bool dispatchCompositorIpc();

    void applyInputSettings();
};

} // namespace caelestia::config
