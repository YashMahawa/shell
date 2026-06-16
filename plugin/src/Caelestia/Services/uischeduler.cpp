#include "uischeduler.hpp"
#include <QMetaMethod>

namespace caelestia::services {

UiScheduler::UiScheduler(QObject* parent)
    : QObject(parent)
    , m_timer(new QTimer(this)) {
    m_timer->setTimerType(Qt::PreciseTimer);
    connect(m_timer, &QTimer::timeout, this, &UiScheduler::tick);
    updateTimer();
}

bool UiScheduler::throttled() const {
    return m_throttled;
}

void UiScheduler::setThrottled(bool t) {
    if (m_throttled == t)
        return;
    m_throttled = t;
    updateTimer();
    emit throttledChanged();
}

void UiScheduler::updateTimer() {
    if (isSignalConnected(QMetaMethod::fromSignal(&UiScheduler::tick))) {
        m_timer->start(m_throttled ? 16 : 10);
    } else {
        m_timer->stop();
    }
}

void UiScheduler::connectNotify(const QMetaMethod& signal) {
    QObject::connectNotify(signal);
    if (signal == QMetaMethod::fromSignal(&UiScheduler::tick)) {
        QMetaObject::invokeMethod(this, [this]() { updateTimer(); }, Qt::QueuedConnection);
    }
}

void UiScheduler::disconnectNotify(const QMetaMethod& signal) {
    QObject::disconnectNotify(signal);
    if (signal == QMetaMethod::fromSignal(&UiScheduler::tick)) {
        QMetaObject::invokeMethod(this, [this]() { updateTimer(); }, Qt::QueuedConnection);
    }
}

} // namespace caelestia::services
