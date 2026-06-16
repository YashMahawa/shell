#include "backgrounddaemon.hpp"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QThread>

namespace caelestia::services {

BackgroundDaemon::BackgroundDaemon(QObject* parent) 
    : QObject(parent), m_watcher(new QFileSystemWatcher(this)) {
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &BackgroundDaemon::onDirectoryChanged);
}

void BackgroundDaemon::startDaemon() {
    QString wallpaperPath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + "/Wallpapers";
    QDir dir(wallpaperPath);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    
    if (!m_watchedPaths.contains(wallpaperPath)) {
        m_watcher->addPath(wallpaperPath);
        m_watchedPaths.append(wallpaperPath);
        qDebug() << "BackgroundDaemon: Watching directory" << wallpaperPath;
    }
}

void BackgroundDaemon::onDirectoryChanged(const QString& path) {
    qDebug() << "BackgroundDaemon: Directory changed at" << path << ". Triggering metadata extraction.";
    // Native background event processing logic goes here
    Q_EMIT wallpaperDirectoryChanged(path);
}

}
