#include <algorithm>
#include "appdb.hpp"

#include <qloggingcategory.h>
#include <qsqldatabase.h>
#include <qsqlquery.h>
#include <quuid.h>
#include <QRunnable>
#include <QThreadPool>
#include <QMetaObject>


Q_LOGGING_CATEGORY(lcAppDb, "caelestia.appdb", QtInfoMsg)

namespace caelestia {

class SearchTask : public QRunnable {
public:
    SearchTask(const QString& query, const QStringList& keys, const QList<qreal>& weights, bool isTerminalOnly, bool useFuzzy, const QList<AppEntry*>& apps, AppDb* db)
        : m_query(query), m_keys(keys), m_weights(weights), m_isTerminalOnly(isTerminalOnly), m_useFuzzy(useFuzzy), m_apps(apps), m_db(db) {}

    void run() override {
        QObjectList results;
        if (m_query.isEmpty() && !m_isTerminalOnly) {
            for (auto* app : m_apps) {
                results.append(app->entry());
            }
        } else {
            QList<QPair<double, QObject*>> scoredApps;
            for (auto* app : m_apps) {
                if (m_isTerminalOnly && !app->entry()->property("runInTerminal").toBool()) {
                    continue;
                }
                if (m_query.isEmpty()) {
                    scoredApps.append({0.0, app->entry()});
                    continue;
                }

                double totalScore = 0;
                bool matched = false;
                for (int i = 0; i < m_keys.size(); ++i) {
                    QString val = app->property(m_keys[i].toUtf8().constData()).toString();
                    double score = m_useFuzzy ? fuzzyMatchScore(m_query, val) : exactMatchScore(m_query, val);
                    if (score > -10000.0) {
                        matched = true;
                        double w = i < m_weights.size() ? m_weights[i] : 1.0;
                        totalScore += score * w;
                    }
                }
                if (matched) {
                    scoredApps.append({totalScore, app->entry()});
                }
            }

            std::stable_sort(scoredApps.begin(), scoredApps.end(), [](const auto& a, const auto& b) {
                return a.first > b.first;
            });

            for (const auto& p : scoredApps) {
                results.append(p.second);
            }
        }

        QMetaObject::invokeMethod(m_db, [db = m_db, query = m_query, res = results]() {
            db->setSearchResults(query, res);
        });
    }

private:
    QString m_query;
    QStringList m_keys;
    QList<qreal> m_weights;
    bool m_isTerminalOnly;
    bool m_useFuzzy;
    QList<AppEntry*> m_apps;
    AppDb* m_db;

    double fuzzyMatchScore(const QString& query, const QString& target) const {
        if (query.isEmpty()) return 10000.0;
        if (target.isEmpty()) return -10000.0;
        QString q = query.toLower();
        QString t = target.toLower();
        int qIdx = 0;
        double score = 0.0;
        int consec = 0;
        for (int i = 0; i < t.length(); ++i) {
            if (qIdx < q.length() && t[i] == q[qIdx]) {
                qIdx++;
                score += 10.0 + consec * 5.0;
                consec++;
            } else {
                consec = 0;
                score -= 1.0;
            }
        }
        if (qIdx == q.length()) {
            score -= t.length();
            if (t.startsWith(q)) score += 50.0;
            return score;
        }
        return -10000.0;
    }

    double exactMatchScore(const QString& query, const QString& target) const {
        if (query.isEmpty()) return 10000.0;
        QString t = target.toLower();
        QString q = query.toLower();
        int idx = t.indexOf(q);
        if (idx != -1) {
            double score = 100.0 - t.length();
            if (idx == 0) score += 50.0;
            return score;
        }
        return -10000.0;
    }
};


AppEntry::AppEntry(QObject* entry, unsigned int frequency, QObject* parent)
    : QObject(parent)
    , m_entry(entry)
    , m_frequency(frequency) {
    const auto mo = m_entry->metaObject();
    const auto tmo = &AppEntry::staticMetaObject;

    for (const auto& prop :
        { "name", "comment", "execString", "startupClass", "genericName", "categories", "keywords" }) {
        const auto metaProp = mo->property(mo->indexOfProperty(prop));
        const auto thisMetaProp = tmo->property(tmo->indexOfProperty(prop));
        QObject::connect(m_entry, metaProp.notifySignal(), this, thisMetaProp.notifySignal());
    }

    QObject::connect(m_entry, &QObject::destroyed, this, [this]() {
        m_entry = nullptr;
        deleteLater();
    });
}

QObject* AppEntry::entry() const {
    return m_entry;
}

quint32 AppEntry::frequency() const {
    return m_frequency;
}

void AppEntry::setFrequency(unsigned int frequency) {
    if (m_frequency != frequency) {
        m_frequency = frequency;
        emit frequencyChanged();
    }
}

void AppEntry::incrementFrequency() {
    m_frequency++;
    emit frequencyChanged();
}

QString AppEntry::id() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("id").toString();
}

QString AppEntry::name() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("name").toString();
}

QString AppEntry::comment() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("comment").toString();
}

QString AppEntry::execString() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("execString").toString();
}

QString AppEntry::startupClass() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("startupClass").toString();
}

QString AppEntry::genericName() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("genericName").toString();
}

QString AppEntry::categories() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("categories").toStringList().join(" ");
}

QString AppEntry::keywords() const {
    if (!m_entry) {
        return "";
    }
    return m_entry->property("keywords").toStringList().join(" ");
}

AppDb::AppDb(QObject* parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
    , m_uuid(QUuid::createUuid().toString()) {
    m_timer->setSingleShot(true);
    m_timer->setInterval(300);
    QObject::connect(m_timer, &QTimer::timeout, this, &AppDb::updateApps);

    auto db = QSqlDatabase::addDatabase("QSQLITE", m_uuid);
    db.setDatabaseName(":memory:");
    db.open();

    QSqlQuery query(db);
    query.exec("CREATE TABLE IF NOT EXISTS frequencies (id TEXT PRIMARY KEY, frequency INTEGER)");
}

QString AppDb::uuid() const {
    return m_uuid;
}

QString AppDb::path() const {
    return m_path;
}

void AppDb::setPath(const QString& path) {
    auto newPath = path.isEmpty() ? ":memory:" : path;

    if (m_path == newPath) {
        return;
    }

    m_path = newPath;
    emit pathChanged();

    auto db = QSqlDatabase::database(m_uuid, false);
    db.close();
    db.setDatabaseName(newPath);
    db.open();

    QSqlQuery query(db);
    query.exec("CREATE TABLE IF NOT EXISTS frequencies (id TEXT PRIMARY KEY, frequency INTEGER)");

    updateAppFrequencies();
}

QObjectList AppDb::entries() const {
    return m_entries;
}

void AppDb::setEntries(const QObjectList& entries) {
    if (m_entries == entries) {
        return;
    }

    m_entries = entries;
    emit entriesChanged();

    m_timer->start();
}

QStringList AppDb::favouriteApps() const {
    return m_favouriteApps;
}

void AppDb::setFavouriteApps(const QStringList& favApps) {
    if (m_favouriteApps == favApps) {
        return;
    }

    m_favouriteApps = favApps;
    emit favouriteAppsChanged();
    m_favouriteAppsRegex.clear();
    m_favouriteAppsRegex.reserve(m_favouriteApps.size());
    for (const QString& item : std::as_const(m_favouriteApps)) {
        const QRegularExpression re(regexifyString(item));
        if (re.isValid()) {
            m_favouriteAppsRegex << re;
        } else {
            qCWarning(lcAppDb) << "setFavouriteApps: regular expression is not valid:" << re.pattern();
        }
    }

    emit appsChanged();
}

QString AppDb::regexifyString(const QString& original) const {
    if (original.startsWith('^') && original.endsWith('$'))
        return original;

    const QString escaped = QRegularExpression::escape(original);
    return QStringLiteral("^%1$").arg(escaped);
}

QQmlListProperty<AppEntry> AppDb::apps() {
    return QQmlListProperty<AppEntry>(this, &getSortedApps());
}

void AppDb::incrementFrequency(const QString& id) {
    auto db = QSqlDatabase::database(m_uuid);
    QSqlQuery query(db);

    query.prepare("INSERT INTO frequencies (id, frequency) "
                  "VALUES (:id, 1) "
                  "ON CONFLICT (id) DO UPDATE SET frequency = frequency + 1");
    query.bindValue(":id", id);
    query.exec();

    auto* app = m_apps.value(id);
    if (app) {
        const auto before = getSortedApps();
        app->incrementFrequency();
        getSortedApps();
        if (before != m_sortedApps) {
            emit appsChanged();
        }
    } else {
        qCWarning(lcAppDb) << "incrementFrequency: could not find app with id" << id;
    }
}

QList<AppEntry*>& AppDb::getSortedApps() const {
    m_sortedApps = m_apps.values();

    // Pre-compute favourite status to avoid repeated regex matching during sort
    QSet<QString> favSet;
    favSet.reserve(m_sortedApps.size());
    for (const auto* app : std::as_const(m_sortedApps)) {
        if (isFavourite(app))
            favSet.insert(app->id());
    }

    std::sort(m_sortedApps.begin(), m_sortedApps.end(), [&favSet](AppEntry* a, AppEntry* b) {
        const bool aIsFav = favSet.contains(a->id());
        const bool bIsFav = favSet.contains(b->id());
        if (aIsFav != bIsFav)
            return aIsFav;
        if (a->frequency() != b->frequency())
            return a->frequency() > b->frequency();
        return a->name().localeAwareCompare(b->name()) < 0;
    });
    return m_sortedApps;
}

bool AppDb::isFavourite(const AppEntry* app) const {
    for (const QRegularExpression& re : m_favouriteAppsRegex) {
        if (re.match(app->id()).hasMatch()) {
            return true;
        }
    }
    return false;
}

quint32 AppDb::getFrequency(const QString& id) const {
    auto db = QSqlDatabase::database(m_uuid);
    QSqlQuery query(db);

    query.prepare("SELECT frequency FROM frequencies WHERE id = :id");
    query.bindValue(":id", id);

    if (query.exec() && query.next()) {
        return query.value(0).toUInt();
    }

    return 0;
}

void AppDb::updateAppFrequencies() {
    const auto before = getSortedApps();

    for (auto* app : std::as_const(m_apps)) {
        app->setFrequency(getFrequency(app->id()));
    }

    getSortedApps();
    if (before != m_sortedApps) {
        emit appsChanged();
    }
}

void AppDb::updateApps() {
    bool dirty = false;

    for (const auto& entry : std::as_const(m_entries)) {
        const auto id = entry->property("id").toString();
        if (!m_apps.contains(id)) {
            dirty = true;
            auto* const newEntry = new AppEntry(entry, getFrequency(id), this);
            QObject::connect(newEntry, &QObject::destroyed, this, [id, this]() {
                if (m_apps.remove(id)) {
                    emit appsChanged();
                }
            });
            m_apps.insert(id, newEntry);
        }
    }

    QSet<QString> newIds;
    for (const auto& entry : std::as_const(m_entries)) {
        newIds.insert(entry->property("id").toString());
    }

    for (auto it = m_apps.begin(); it != m_apps.end();) {
        if (!newIds.contains(it.key())) {
            dirty = true;
            it.value()->deleteLater();
            it = m_apps.erase(it);
        } else {
            ++it;
        }
    }

    if (dirty) {
        emit appsChanged();
    }
}





void AppDb::searchAsync(const QString& query, const QStringList& keys, const QList<qreal>& weights, bool isTerminalOnly, bool useFuzzy) {
    if (m_searchCache.contains(query)) {
        setSearchResults(query, m_searchCache.value(query));
        return;
    }
    auto* task = new SearchTask(query, keys, weights, isTerminalOnly, useFuzzy, m_sortedApps, this);
    QThreadPool::globalInstance()->start(task);
}

QObjectList AppDb::searchResults() const {
    return m_searchResults;
}

void AppDb::setSearchResults(const QString& query, const QObjectList& results) {
    if (!m_searchCache.contains(query)) {
        m_searchCache.insert(query, results);
        m_searchCacheOrder.append(query);
        if (m_searchCacheOrder.size() > 50) {
            m_searchCache.remove(m_searchCacheOrder.takeFirst());
        }
    }
    m_searchResults = results;
    emit searchResultsChanged();
}

} // namespace caelestia
