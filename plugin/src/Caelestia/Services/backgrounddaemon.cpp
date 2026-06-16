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
    : QObject(parent), m_watcher(new QFileSystemWatcher(this)), m_scanWatcher(new QFutureWatcher<QVariantList>(this)), m_debounceTimer(new QTimer(this)), m_scanPending(false) {
    
    m_debounceTimer->setSingleShot(true);
    m_debounceTimer->setInterval(500);

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &BackgroundDaemon::onDirectoryChanged);
    connect(m_scanWatcher, &QFutureWatcher<QVariantList>::finished, this, &BackgroundDaemon::onScanFinished);
    connect(m_debounceTimer, &QTimer::timeout, this, &BackgroundDaemon::triggerScan);
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
        qDebug() << "BackgroundDaemon: Watching root directory" << wallpaperPath;
    }
    scanDirectoryAsync(wallpaperPath);
}

void BackgroundDaemon::onDirectoryChanged(const QString& path) {
    qDebug() << "BackgroundDaemon: Directory changed at" << path << ". Triggering metadata extraction.";
    Q_EMIT wallpaperDirectoryChanged(path);
    m_debounceTimer->start();
}

void BackgroundDaemon::triggerScan() {
    if (m_scanWatcher->isRunning()) {
        m_scanPending = true;
    } else {
        scanDirectoryAsync(m_currentPath);
    }
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
            map["name"] = it.fileName();
            list.append(map);
        }
        return list;
    });
    m_scanWatcher->setFuture(future);
}

void BackgroundDaemon::onScanFinished() {
    m_wallpapers = m_scanWatcher->result();
    Q_EMIT wallpapersChanged();

    // Update watched directories with any new nested folders
    if (!m_currentPath.isEmpty()) {
        QDirIterator dirIt(m_currentPath, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        QStringList newDirs;
        while (dirIt.hasNext()) {
            QString subDir = dirIt.next();
            if (!m_watchedPaths.contains(subDir)) {
                newDirs.append(subDir);
                m_watchedPaths.append(subDir);
            }
        }
        if (!newDirs.isEmpty()) {
            m_watcher->addPaths(newDirs);
            qDebug() << "BackgroundDaemon: Added" << newDirs.size() << "new nested directories to watcher.";
        }
    }

    if (m_scanPending) {
        m_scanPending = false;
        m_debounceTimer->start();
    }
}

}
