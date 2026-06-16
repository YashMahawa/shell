#include "wallpaperengine.hpp"

namespace caelestia::images {

WallpaperEngine* WallpaperEngine::create(QQmlEngine*, QJSEngine*) {
    return new WallpaperEngine();
}

WallpaperEngine::WallpaperEngine(QObject* parent)
    : QAbstractListModel(parent) {
    m_cleanupTimer.setInterval(1000);
    m_cleanupTimer.setSingleShot(true);
    connect(&m_cleanupTimer, &QTimer::timeout, this, &WallpaperEngine::cleanup);
}

void WallpaperEngine::setSource(const QString& source) {
    if (m_source == source) return;
    m_source = source;
    emit sourceChanged();

    for (int i = 0; i < m_wallpapers.size(); ++i) {
        if (m_wallpapers[i].isCurrent) {
            m_wallpapers[i].isCurrent = false;
            emit dataChanged(index(i), index(i), {IsCurrentRole});
        }
    }

    if (source.isEmpty()) {
        m_cleanupTimer.stop();
        if (!m_wallpapers.isEmpty()) {
            beginRemoveRows(QModelIndex(), 0, m_wallpapers.size() - 1);
            m_wallpapers.clear();
            endRemoveRows();
        }
    } else {
        beginInsertRows(QModelIndex(), m_wallpapers.size(), m_wallpapers.size());
        m_wallpapers.append({source, true, false});
        endInsertRows();
        m_cleanupTimer.start();
    }
}

void WallpaperEngine::markReady(int idx) {
    if (idx >= 0 && idx < m_wallpapers.size()) {
        m_wallpapers[idx].isReady = true;
        m_cleanupTimer.start();
    }
}

int WallpaperEngine::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_wallpapers.size();
}

QVariant WallpaperEngine::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= m_wallpapers.size()) return {};
    const auto& w = m_wallpapers[index.row()];
    if (role == PathRole) return w.path;
    if (role == IsCurrentRole) return w.isCurrent;
    return {};
}

QHash<int, QByteArray> WallpaperEngine::roleNames() const {
    return {
        {PathRole, "path"},
        {IsCurrentRole, "isCurrent"}
    };
}

void WallpaperEngine::cleanup() {
    if (m_source.isEmpty() || m_wallpapers.isEmpty() || !m_wallpapers.last().isReady) {
        return;
    }

    // Keep only the last one
    while (m_wallpapers.size() > 1) {
        beginRemoveRows(QModelIndex(), 0, 0);
        m_wallpapers.removeFirst();
        endRemoveRows();
    }
}

} // namespace caelestia::images
