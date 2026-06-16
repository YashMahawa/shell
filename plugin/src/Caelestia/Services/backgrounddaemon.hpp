#pragma once
#include <QObject>
namespace caelestia::services {
class BackgroundDaemon : public QObject {
    Q_OBJECT
public:
    explicit BackgroundDaemon(QObject* parent = nullptr);
    void startDaemon();
};
}
