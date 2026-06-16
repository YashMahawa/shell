#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QStringList>

namespace caelestia::services {
class BackgroundDaemon : public QObject {
    Q_OBJECT
public:
    explicit BackgroundDaemon(QObject* parent = nullptr);
    Q_INVOKABLE void startDaemon();

signals:
    void wallpaperDirectoryChanged(const QString& path);

private slots:
    void onDirectoryChanged(const QString& path);

private:
    QFileSystemWatcher* m_watcher;
    QStringList m_watchedPaths;
};
}
