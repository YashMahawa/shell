#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QStringList>
#include <QFutureWatcher>
#include <QVariantList>
#include <qqmlintegration.h>

namespace caelestia::services {
class BackgroundDaemon : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList wallpapers READ wallpapers NOTIFY wallpapersChanged)

public:
    explicit BackgroundDaemon(QObject* parent = nullptr);
    ~BackgroundDaemon() override = default;

    Q_INVOKABLE void startDaemon(const QString& wallpaperPath);
    QVariantList wallpapers() const { return m_wallpapers; }

signals:
    void wallpaperDirectoryChanged(const QString& path);
    void wallpapersChanged();

private slots:
    void onDirectoryChanged(const QString& path);
    void onScanFinished();

private:
    void scanDirectoryAsync(const QString& path);

    QFileSystemWatcher* m_watcher;
    QStringList m_watchedPaths;
    QVariantList m_wallpapers;
    QFutureWatcher<QVariantList>* m_scanWatcher;
    QString m_currentPath;
};
}
