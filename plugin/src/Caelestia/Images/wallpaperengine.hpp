#pragma once

#include <qabstractitemmodel.h>
#include <qqmlintegration.h>
#include <qstring.h>
#include <qtimer.h>

namespace caelestia::images {

class WallpaperEngine : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)

public:
    enum Roles {
        PathRole = Qt::UserRole + 1,
        IsCurrentRole
    };

    explicit WallpaperEngine(QObject* parent = nullptr);

    static WallpaperEngine* create(QQmlEngine*, QJSEngine*);

    QString source() const { return m_source; }
    void setSource(const QString& source);

    Q_INVOKABLE void markReady(int index);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

signals:
    void sourceChanged();

private slots:
    void cleanup();

private:
    QString m_source;
    struct Wallpaper {
        QString path;
        bool isCurrent;
        bool isReady;
    };
    QList<Wallpaper> m_wallpapers;
    QTimer m_cleanupTimer;
};

} // namespace caelestia::images
