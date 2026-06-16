#pragma once
#include <QObject>
#include <QString>
#include <qqmlintegration.h>

namespace caelestia {
class ThemeBridge : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit ThemeBridge(QObject* parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE bool exportGreeterTheme(const QString& sourcePath);
};
}
