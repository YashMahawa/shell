#include "uischeduler.hpp"

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
    m_timer->start(m_throttled ? 16 : 10);
}

} // namespace caelestia::services
