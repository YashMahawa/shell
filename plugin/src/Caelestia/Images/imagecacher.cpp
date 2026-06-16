#include "imagecacher.hpp"

#include <qcryptographichash.h>
#include <qdatetime.h>
#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qimage.h>
#include <qjsondocument.h>
#include <qjsonobject.h>
#include <qvariant.h>
#include <qloggingcategory.h>
#include <qmutex.h>
#include <qpainter.h>
#include <qsavefile.h>
#include <qthreadpool.h>

Q_LOGGING_CATEGORY(lcCacher, "caelestia.images.cacher", QtInfoMsg)

namespace caelestia::images {

namespace {

QString sha256sum(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcCacher).noquote() << "sha256sum: failed to open" << path;
        return {};
    }

    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&file);
    file.close();

    return hash.result().toHex();
}

struct FileMetadata {
    qint64 size = 0;
    qint64 mtime = 0;
    QString hash;

    QJsonObject toJson() const {
        return QJsonObject{
            {"size", size},
            {"mtime", mtime},
            {"hash", hash}
        };
    }
    static FileMetadata fromJson(const QJsonObject& obj) {
        return FileMetadata{
            obj["size"].toVariant().toLongLong(),
            obj["mtime"].toVariant().toLongLong(),
            obj["hash"].toString()
        };
    }
};

QMutex s_metadataMutex;
QHash<QString, FileMetadata> s_metadata;
bool s_metadataLoaded = false;

void loadMetadata() {
    QMutexLocker locker(&s_metadataMutex);
    if (s_metadataLoaded) return;
    s_metadataLoaded = true;

    QFile file(ImageCacher::cacheDir() + QStringLiteral("/metadata.json"));
    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            for (auto it = obj.begin(); it != obj.end(); ++it) {
                s_metadata[it.key()] = FileMetadata::fromJson(it.value().toObject());
            }
        }
    }
}

void saveMetadata() {
    QMutexLocker locker(&s_metadataMutex);
    QJsonObject obj;
    for (auto it = s_metadata.begin(); it != s_metadata.end(); ++it) {
        obj[it.key()] = it.value().toJson();
    }
    
    QDir().mkpath(ImageCacher::cacheDir());
    QSaveFile saveFile(ImageCacher::cacheDir() + QStringLiteral("/metadata.json"));
    if (saveFile.open(QIODevice::WriteOnly)) {
        saveFile.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
        saveFile.commit();
    }
}

QString getOrComputeHash(const QString& path) {
    loadMetadata();

    QFileInfo info(path);
    qint64 size = info.size();
    qint64 mtime = info.lastModified().toMSecsSinceEpoch();

    {
        QMutexLocker locker(&s_metadataMutex);
        if (s_metadata.contains(path)) {
            const auto& meta = s_metadata[path];
            if (meta.size == size && meta.mtime == mtime && !meta.hash.isEmpty()) {
                return meta.hash;
            }
        }
    }

    QString hash = sha256sum(path);
    if (hash.isEmpty()) return {};

    {
        QMutexLocker locker(&s_metadataMutex);
        s_metadata[path] = FileMetadata{size, mtime, hash};
    }
    saveMetadata();

    return hash;
}

QString fillSuffix(ImageCacher::FillMode fillMode) {
    switch (fillMode) {
    case ImageCacher::FillMode::Crop:
        return QStringLiteral("crop");
    case ImageCacher::FillMode::Fit:
        return QStringLiteral("fit");
    default:
        return QStringLiteral("stretch");
    }
}

} // namespace

const QString& ImageCacher::cacheDir() {
    static const QString s_dir = [] {
        QString cache = qEnvironmentVariable("XDG_CACHE_HOME");
        if (cache.isEmpty())
            cache = QDir::homePath() + QStringLiteral("/.cache");
        return cache + QStringLiteral("/caelestia/imagecache");
    }();
    return s_dir;
}

QString ImageCacher::cachePathFor(const QString& sourcePath, const QSize& size, FillMode fillMode) {
    const QString sha = getOrComputeHash(sourcePath);
    if (sha.isEmpty())
        return {};

    const QString filename =
        QStringLiteral("%1@%2x%3-%4.png")
            .arg(sha, QString::number(size.width()), QString::number(size.height()), fillSuffix(fillMode));

    return cacheDir() + QLatin1Char('/') + filename;
}

ImageCacher* ImageCacher::instance() {
    static ImageCacher s_instance;
    return &s_instance;
}

ImageCacher::ImageCacher(QObject* parent)
    : QObject(parent) {}

void ImageCacher::schedule(const QString& sourcePath, const QSize& size, FillMode fillMode) {
    schedule(sourcePath, cachePathFor(sourcePath, size, fillMode), size, fillMode);
}

void ImageCacher::schedule(const QString& sourcePath, const QString& cachePath, const QSize& size, FillMode fillMode) {
    if (cachePath.isEmpty())
        return;

    {
        QMutexLocker locker(&m_mutex);
        if (m_inflight.contains(cachePath))
            return;
        m_inflight.insert(cachePath);
    }

    QThreadPool::globalInstance()->start([this, sourcePath, cachePath, size, fillMode]() {
        runJob(sourcePath, cachePath, size, fillMode);
        QMutexLocker locker(&m_mutex);
        m_inflight.remove(cachePath);
    });
}

void ImageCacher::runJob(const QString& sourcePath, const QString& cachePath, const QSize& size, FillMode fillMode) {
    if (QFile::exists(cachePath)) {
        return;
    }

    QImage image(sourcePath);
    if (image.isNull()) {
        qCWarning(lcCacher).noquote() << "Failed to decode source" << sourcePath;
        return;
    }

    Qt::AspectRatioMode scaleMode;
    switch (fillMode) {
    case FillMode::Crop:
        scaleMode = Qt::KeepAspectRatioByExpanding;
        break;
    case FillMode::Fit:
        scaleMode = Qt::KeepAspectRatio;
        break;
    case FillMode::Stretch:
        scaleMode = Qt::IgnoreAspectRatio;
        break;
    }

    image.convertTo(QImage::Format_ARGB32);
    image = image.scaled(size, scaleMode, Qt::SmoothTransformation);

    if (image.isNull()) {
        qCWarning(lcCacher).noquote() << "Failed to scale" << sourcePath;
        return;
    }

    QImage canvas;
    if (fillMode == FillMode::Stretch) {
        canvas = image;
    } else {
        canvas = QImage(size, QImage::Format_ARGB32);
        canvas.fill(Qt::transparent);

        QPainter painter(&canvas);
        painter.drawImage((size.width() - image.width()) / 2, (size.height() - image.height()) / 2, image);
        painter.end();
    }

    const QString parent = QFileInfo(cachePath).absolutePath();
    if (!QDir().mkpath(parent)) {
        qCWarning(lcCacher).noquote() << "Failed to create cache dir" << parent;
        return;
    }

    QSaveFile saveFile(cachePath);
    if (!saveFile.open(QIODevice::WriteOnly) || !canvas.save(&saveFile, "PNG") || !saveFile.commit()) {
        qCWarning(
            lcCacher, "Failed to save to %s: %s", qUtf8Printable(cachePath), qUtf8Printable(saveFile.errorString()));
        return;
    }

    qCDebug(lcCacher).noquote() << "Saved to" << cachePath;
}

} // namespace caelestia::images
