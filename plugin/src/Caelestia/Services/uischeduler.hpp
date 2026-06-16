#pragma once

#include <qobject.h>
#include <qqmlengine.h>
#include <qtimer.h>

namespace caelestia::services {

class UiScheduler : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool throttled READ throttled WRITE setThrottled NOTIFY throttledChanged)

public:
    explicit UiScheduler(QObject* parent = nullptr);

    bool throttled() const;
    void setThrottled(bool t);

signals:
    void throttledChanged();
    void tick();

private:
    void updateTimer();

    bool m_throttled = false;
    QTimer* m_timer;
};

} // namespace caelestia::services
