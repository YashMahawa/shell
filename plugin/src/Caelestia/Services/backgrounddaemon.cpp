#include "backgrounddaemon.hpp"
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QDebug>
#include <QThread>
#include <QtConcurrent>
#include <QVariantMap>

namespace caelestia::services {

BackgroundDaemon::BackgroundDaemon(QObject* parent) 
    : QObject(parent), m_watcher(new QFileSystemWatcher(this)), m_scanWatcher(new QFutureWatcher<QVariantList>(this)) {
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &BackgroundDaemon::onDirectoryChanged);
    connect(m_scanWatcher, &QFutureWatcher<QVariantList>::finished, this, &BackgroundDaemon::onScanFinished);
}

void BackgroundDaemon::startDaemon(const QString& wallpaperPath) {
    m_currentPath = wallpaperPath;
    QDir dir(wallpaperPath);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    
    if (!m_watchedPaths.contains(wallpaperPath)) {
        m_watcher->addPath(wallpaperPath);
        m_watchedPaths.append(wallpaperPath);
        qDebug() << "BackgroundDaemon: Watching directory" << wallpaperPath;
    }
    scanDirectoryAsync(wallpaperPath);
}

void BackgroundDaemon::onDirectoryChanged(const QString& path) {
    qDebug() << "BackgroundDaemon: Directory changed at" << path << ". Triggering metadata extraction.";
    Q_EMIT wallpaperDirectoryChanged(path);
    scanDirectoryAsync(path);
}

void BackgroundDaemon::scanDirectoryAsync(const QString& path) {
    QFuture<QVariantList> future = QtConcurrent::run([path]() {
        QVariantList list;
        QDirIterator it(path, QStringList() << "*.jpg" << "*.jpeg" << "*.png" << "*.webp", QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            QVariantMap map;
            map["path"] = it.filePath();
            map["parentDir"] = it.fileInfo().absolutePath();
            map["relativePath"] = it.filePath().mid(path.length() + (!path.endsWith('/') ? 1 : 0));
            list.append(map);
        }
        return list;
    });
    m_scanWatcher->setFuture(future);
}

void BackgroundDaemon::onScanFinished() {
    m_wallpapers = m_scanWatcher->result();
    Q_EMIT wallpapersChanged();
}

}
