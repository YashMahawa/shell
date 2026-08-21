#pragma once

#include <qmutex.h>
#include <qobject.h>
#include <qqmlintegration.h>
#include <qtimer.h>

namespace caelestia {

class Qalculator : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString result READ result NOTIFY resultChanged)
    Q_PROPERTY(QString rawResult READ rawResult NOTIFY rawResultChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(bool initialized READ initialized NOTIFY initializedChanged)

public:
    explicit Qalculator(QObject* parent = nullptr);

    Q_INVOKABLE QString eval(const QString& expr, bool printExpr = true) const;
    Q_INVOKABLE void evalAsync(const QString& expr);

    [[nodiscard]] QString result() const;
    [[nodiscard]] QString rawResult() const;
    [[nodiscard]] bool busy() const;
    [[nodiscard]] bool initialized() const;

signals:
    void resultChanged();
    void rawResultChanged();
    void busyChanged();
    void initializedChanged();

private:
    void onThrottleTimeout();
    void checkPending();

    static QMutex s_calculatorMutex;

    QString m_result;
    QString m_rawResult;
    bool m_busy = false;
    bool m_initialized = false;
    bool m_calcRunning = false;
    bool m_pending = false;
    QString m_pendingExpr;
    quint64 m_generation = 0;
    QTimer* m_throttleTimer = nullptr;
};

} // namespace caelestia
