#pragma once

#include "configobject.hpp"

namespace caelestia::config {

class InputConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    CONFIG_PROPERTY(double, pointerSpeed, 0.0)
    CONFIG_PROPERTY(bool, touchpadTapToClick, true)
    CONFIG_PROPERTY(bool, touchpadNaturalScroll, true)
    CONFIG_PROPERTY(int, keyboardRepeatRate, 35)
    CONFIG_PROPERTY(int, keyboardRepeatDelay, 250)

    // Aliases
    Q_PROPERTY(double mouseSensitivity READ pointerSpeed WRITE set_pointerSpeed NOTIFY pointerSpeedChanged)
    Q_PROPERTY(bool tapToClick READ touchpadTapToClick WRITE set_touchpadTapToClick NOTIFY touchpadTapToClickChanged)
    Q_PROPERTY(bool naturalScroll READ touchpadNaturalScroll WRITE set_touchpadNaturalScroll NOTIFY touchpadNaturalScrollChanged)
    Q_PROPERTY(int repeatRate READ keyboardRepeatRate WRITE set_keyboardRepeatRate NOTIFY keyboardRepeatRateChanged)
    Q_PROPERTY(int repeatDelay READ keyboardRepeatDelay WRITE set_keyboardRepeatDelay NOTIFY keyboardRepeatDelayChanged)

public:
    explicit InputConfig(QObject* parent = nullptr);

    void applyInputSettings();
    void syncVariablesFile();
    void dispatchCompositorIpc();
};

} // namespace caelestia::config
