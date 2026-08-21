#include "voiceservice.hpp"

#include <algorithm>
#include <random>

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLoggingCategory>
#include <QProcess>
#include <QStandardPaths>

Q_LOGGING_CATEGORY(lcVoice, "caelestia.services.voice", QtInfoMsg)

namespace caelestia::services {

static const char* DEFAULT_PROMPT =
    "Transcribe the user's speech accurately. Remove accidental filler words and apply spoken "
    "mid-sentence corrections, keeping only the corrected wording. Add natural punctuation. Do not censor "
    "profanity. Do not answer the user or invent facts: output only what was spoken. If there is only silence, "
    "background noise, or unintelligible speech, output exactly <NO TEXT>.";

VoiceService::VoiceService(QObject* parent)
    : Service(parent) {
    m_networkManager = new QNetworkAccessManager(this);

    m_safetyTimer = new QTimer(this);
    m_safetyTimer->setSingleShot(true);
    connect(m_safetyTimer, &QTimer::timeout, this, &VoiceService::stopCapture);

    m_idleResetTimer = new QTimer(this);
    m_idleResetTimer->setSingleShot(true);
    connect(m_idleResetTimer, &QTimer::timeout, this, [this]() {
        setState("idle", "", "");
    });

    loadConfig();
    refreshKeys();
}

VoiceService::~VoiceService() {
    if (m_isRecording || (m_captureProcess && m_captureProcess->state() != QProcess::NotRunning)) {
        m_isRecording = false;
        if (m_captureProcess) {
            m_captureProcess->disconnect();
            m_captureProcess->terminate();
            if (!m_captureProcess->waitForFinished(300)) {
                m_captureProcess->kill();
            }
        }
    }
    if (!m_tempWavPath.isEmpty() && QFile::exists(m_tempWavPath)) {
        QFile::remove(m_tempWavPath);
    }
}

QVariantList VoiceService::storedKeys() const {
    QVariantList list;
    list.append(m_keyPresence[0]);
    list.append(m_keyPresence[1]);
    list.append(m_keyPresence[2]);
    return list;
}

QVariantMap VoiceService::statusInfo() const {
    QVariantMap map;
    map["status"] = m_status;
    map["message"] = m_message;
    map["detail"] = m_detail;
    map["keys"] = storedKeys();
    map["prompt"] = m_prompt;
    map["model"] = m_model;
    return map;
}

void VoiceService::setState(const QString& status, const QString& message, const QString& detail) {
    const bool wasActive = active();

    if (m_status != status) {
        m_status = status;
        emit statusChanged();
    }
    if (m_message != message) {
        m_message = message;
        emit messageChanged();
    }
    if (m_detail != detail) {
        m_detail = detail;
        emit detailChanged();
    }
    if (active() != wasActive) {
        emit activeChanged();
    }
}

void VoiceService::scheduleResetToIdle(int delayMs) {
    m_idleResetTimer->start(delayMs);
}

void VoiceService::loadConfig() {
    const QString configPath = QDir::homePath() + "/.config/caelestia/voice-typing.json";
    QFile file(configPath);

    m_prompt = QString::fromUtf8(DEFAULT_PROMPT);
    m_model = "gemini-3.1-flash-lite";

    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            if (obj.contains("prompt") && obj["prompt"].isString()) {
                m_prompt = obj["prompt"].toString();
            }
            if (obj.contains("model") && obj["model"].isString()) {
                m_model = obj["model"].toString();
            }
        }
    }

    emit promptChanged();
    emit modelChanged();
}

void VoiceService::saveConfig() {
    const QString configDir = QDir::homePath() + "/.config/caelestia";
    QDir().mkpath(configDir);

    const QString configPath = configDir + "/voice-typing.json";
    QJsonObject obj;
    obj["prompt"] = m_prompt;
    obj["model"] = m_model;

    QFile file(configPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

QString VoiceService::lookupSecretDBus(int slot) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return QString();

    QDBusMessage searchMsg = QDBusMessage::createMethodCall(
        "org.freedesktop.secrets", "/org/freedesktop/secrets", "org.freedesktop.Secret.Service", "SearchItems");

    QHash<QString, QString> attrs;
    attrs["application"] = "caelestia";
    attrs["purpose"] = "gemini-voice";
    attrs["slot"] = QString::number(slot);

    searchMsg << QVariant::fromValue(attrs);
    QDBusMessage reply = bus.call(searchMsg);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().size() < 2)
        return QString();

    QList<QDBusObjectPath> unlocked = qvariant_cast<QList<QDBusObjectPath>>(reply.arguments().at(0));
    QList<QDBusObjectPath> locked = qvariant_cast<QList<QDBusObjectPath>>(reply.arguments().at(1));

    QDBusObjectPath itemPath;
    if (!unlocked.isEmpty()) {
        itemPath = unlocked.first();
    } else if (!locked.isEmpty()) {
        itemPath = locked.first();
    } else {
        return QString();
    }

    QDBusMessage openSessMsg = QDBusMessage::createMethodCall(
        "org.freedesktop.secrets", "/org/freedesktop/secrets", "org.freedesktop.Secret.Service", "OpenSession");
    openSessMsg << "plain" << QVariant::fromValue(QDBusVariant(QString("")));
    QDBusMessage openSessReply = bus.call(openSessMsg);

    QDBusObjectPath sessionPath("/");
    if (openSessReply.type() == QDBusMessage::ReplyMessage && openSessReply.arguments().size() >= 2) {
        sessionPath = qvariant_cast<QDBusObjectPath>(openSessReply.arguments().at(1));
    }

    QDBusMessage getSecMsg = QDBusMessage::createMethodCall(
        "org.freedesktop.secrets", itemPath.path(), "org.freedesktop.Secret.Item", "GetSecret");
    getSecMsg << QVariant::fromValue(sessionPath);
    QDBusMessage getSecReply = bus.call(getSecMsg);

    if (getSecReply.type() != QDBusMessage::ReplyMessage || getSecReply.arguments().isEmpty())
        return QString();

    const QDBusArgument arg = getSecReply.arguments().at(0).value<QDBusArgument>();
    QDBusObjectPath sess;
    QByteArray params;
    QByteArray secretBytes;
    QString contentType;

    arg.beginStructure();
    arg >> sess >> params >> secretBytes >> contentType;
    arg.endStructure();

    return QString::fromUtf8(secretBytes).trimmed();
}

bool VoiceService::storeSecretDBus(int slot, const QString& secret) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;

    QDBusMessage openSessMsg = QDBusMessage::createMethodCall(
        "org.freedesktop.secrets", "/org/freedesktop/secrets", "org.freedesktop.Secret.Service", "OpenSession");
    openSessMsg << "plain" << QVariant::fromValue(QDBusVariant(QString("")));
    QDBusMessage openSessReply = bus.call(openSessMsg);

    QDBusObjectPath sessionPath("/");
    if (openSessReply.type() == QDBusMessage::ReplyMessage && openSessReply.arguments().size() >= 2) {
        sessionPath = qvariant_cast<QDBusObjectPath>(openSessReply.arguments().at(1));
    }

    QDBusMessage createMsg = QDBusMessage::createMethodCall(
        "org.freedesktop.secrets",
        "/org/freedesktop/secrets/aliases/default",
        "org.freedesktop.Secret.Collection",
        "CreateItem");

    QVariantMap properties;
    properties["org.freedesktop.Secret.Item.Label"] = QString("Caelestia Gemini voice key %1").arg(slot);

    QHash<QString, QString> attrs;
    attrs["application"] = "caelestia";
    attrs["purpose"] = "gemini-voice";
    attrs["slot"] = QString::number(slot);
    properties["org.freedesktop.Secret.Item.Attributes"] = QVariant::fromValue(attrs);

    QDBusArgument secretArg;
    secretArg.beginStructure();
    secretArg << sessionPath << QByteArray() << secret.trimmed().toUtf8() << QString("text/plain");
    secretArg.endStructure();

    createMsg << properties << QVariant::fromValue(secretArg) << true;

    QDBusMessage reply = bus.call(createMsg);
    return reply.type() == QDBusMessage::ReplyMessage;
}

bool VoiceService::clearSecretDBus(int slot) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;

    QDBusMessage searchMsg = QDBusMessage::createMethodCall(
        "org.freedesktop.secrets", "/org/freedesktop/secrets", "org.freedesktop.Secret.Service", "SearchItems");

    QHash<QString, QString> attrs;
    attrs["application"] = "caelestia";
    attrs["purpose"] = "gemini-voice";
    attrs["slot"] = QString::number(slot);

    searchMsg << QVariant::fromValue(attrs);
    QDBusMessage reply = bus.call(searchMsg);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().size() < 2)
        return false;

    QList<QDBusObjectPath> unlocked = qvariant_cast<QList<QDBusObjectPath>>(reply.arguments().at(0));
    QList<QDBusObjectPath> locked = qvariant_cast<QList<QDBusObjectPath>>(reply.arguments().at(1));
    QList<QDBusObjectPath> all = unlocked + locked;

    for (const auto& item : all) {
        QDBusMessage delMsg = QDBusMessage::createMethodCall(
            "org.freedesktop.secrets", item.path(), "org.freedesktop.Secret.Item", "Delete");
        bus.call(delMsg);
    }
    return true;
}

void VoiceService::refreshKeys() {
    for (int slot = 1; slot <= 3; ++slot) {
        QString key = lookupSecretDBus(slot);
        if (key.length() >= 20) {
            m_cachedKeys[slot - 1] = key;
            m_keyPresence[slot - 1] = true;
        } else {
            m_cachedKeys[slot - 1].clear();
            m_keyPresence[slot - 1] = false;
        }
    }

    emit storedKeysChanged();
}

void VoiceService::storeKey(int slot, const QString& key) {
    if (slot < 1 || slot > 3)
        return;

    const QString trimmed = key.trimmed();
    if (trimmed.length() < 20)
        return;

    storeSecretDBus(slot, trimmed);
    m_cachedKeys[slot - 1] = trimmed;
    m_keyPresence[slot - 1] = true;
    emit storedKeysChanged();
}

void VoiceService::clearKey(int slot) {
    if (slot < 1 || slot > 3)
        return;

    clearSecretDBus(slot);
    m_cachedKeys[slot - 1].clear();
    m_keyPresence[slot - 1] = false;
    emit storedKeysChanged();
}

void VoiceService::savePrompt(const QString& prompt) {
    if (prompt.trimmed().length() < 40)
        return;

    m_prompt = prompt.trimmed();
    saveConfig();
    emit promptChanged();
}

QStringList VoiceService::getAllAvailableKeys() {
    QStringList keys;
    for (int i = 0; i < 3; ++i) {
        if (!m_cachedKeys[i].isEmpty() && !keys.contains(m_cachedKeys[i])) {
            keys.append(m_cachedKeys[i]);
        }
    }

    const QString home = QDir::homePath();
    const QStringList candidateFiles = {home + "/gemini_voice_assistant/paid_key", home + "/.gemini_api_key"};
    for (const auto& filePath : candidateFiles) {
        QFile file(filePath);
        if (file.open(QIODevice::ReadOnly)) {
            const QString val = QString::fromUtf8(file.readAll()).trimmed();
            if (val.length() >= 20 && !keys.contains(val)) {
                keys.append(val);
            }
        }
    }

    const QString envKey = qEnvironmentVariable("GEMINI_API_KEY").trimmed();
    if (envKey.length() >= 20 && !keys.contains(envKey)) {
        keys.append(envKey);
    }

    std::random_device rd;
    std::mt19937 g(rd());
    std::shuffle(keys.begin(), keys.end(), g);

    return keys;
}

QString VoiceService::findCaptureExecutable() const {
    const QString homeWorker = QDir::homePath() + "/.local/bin/caelestia-voice";
    if (QFile::exists(homeWorker)) {
        return homeWorker;
    }
    const QString sysWorker = QStandardPaths::findExecutable("caelestia-voice");
    if (!sysWorker.isEmpty()) {
        return sysWorker;
    }
    const QString pwRecord = QStandardPaths::findExecutable("pw-record");
    if (!pwRecord.isEmpty()) {
        return pwRecord;
    }
    const QString pwCat = QStandardPaths::findExecutable("pw-cat");
    if (!pwCat.isEmpty()) {
        return pwCat;
    }
    return "pw-record";
}

void VoiceService::toggle() {
    if (m_isRecording || m_status == "listening") {
        stopCapture();
    } else {
        startCapture();
    }
}

void VoiceService::startCapture() {
    if (m_isRecording)
        return;

    m_idleResetTimer->stop();

    m_tempWavPath = QDir::tempPath() + QString("/caelestia-voice-%1.wav").arg(QCoreApplication::applicationPid());
    if (QFile::exists(m_tempWavPath)) {
        QFile::remove(m_tempWavPath);
    }

    if (m_captureProcess) {
        m_captureProcess->disconnect();
        if (m_captureProcess->state() != QProcess::NotRunning) {
            m_captureProcess->terminate();
            if (!m_captureProcess->waitForFinished(200)) {
                m_captureProcess->kill();
            }
        }
        m_captureProcess->deleteLater();
        m_captureProcess = nullptr;
    }

    m_captureProcess = new QProcess(this);
    const QString execPath = findCaptureExecutable();

    QStringList args;
    if (execPath.contains("caelestia-voice")) {
        args << "record" << m_tempWavPath;
    } else if (execPath.contains("pw-cat")) {
        args << "-r" << "--format=s16" << "--rate=16000" << "--channels=1" << m_tempWavPath;
    } else {
        args << "--format=s16" << "--rate=16000" << "--channels=1" << m_tempWavPath;
    }

    connect(m_captureProcess, &QProcess::errorOccurred, this, [this](QProcess::ProcessError) {
        if (m_isRecording) {
            m_isRecording = false;
            m_safetyTimer->stop();
            setState("error", "Capture failed", "Could not start audio capture process");
            scheduleResetToIdle(3000);
        }
    });

    connect(m_captureProcess, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus exitStatus) {
        if (m_isRecording) {
            m_isRecording = false;
            m_safetyTimer->stop();
            if (exitCode != 0 || exitStatus != QProcess::NormalExit) {
                setState("error", "Capture failed", "Audio capture process exited unexpectedly");
                scheduleResetToIdle(3000);
            }
        }
    });

    m_captureProcess->start(execPath, args);
    if (!m_captureProcess->waitForStarted(1000)) {
        m_captureProcess->deleteLater();
        m_captureProcess = nullptr;
        m_isRecording = false;
        setState("error", "Capture failed", "Failed to launch recording worker");
        scheduleResetToIdle(3000);
        return;
    }

    m_isRecording = true;
    setState("listening", "Listening…", "Press F9 again to transcribe");
    m_safetyTimer->start(60000);
}

void VoiceService::stopCapture() {
    if (!m_isRecording && (!m_captureProcess || m_captureProcess->state() == QProcess::NotRunning)) {
        return;
    }

    m_isRecording = false;
    m_safetyTimer->stop();

    if (m_captureProcess) {
        m_captureProcess->disconnect();
        if (m_captureProcess->state() != QProcess::NotRunning) {
            m_captureProcess->terminate();
            if (!m_captureProcess->waitForFinished(500)) {
                m_captureProcess->kill();
                m_captureProcess->waitForFinished(200);
            }
        }
        m_captureProcess->deleteLater();
        m_captureProcess = nullptr;
    }

    QByteArray wavData;
    QFile wavFile(m_tempWavPath);
    if (wavFile.open(QIODevice::ReadOnly)) {
        wavData = wavFile.readAll();
        wavFile.close();
        QFile::remove(m_tempWavPath);
    }

    if (wavData.size() < 4800) {
        setState("empty", "No clear speech detected");
        scheduleResetToIdle(3000);
        return;
    }

    setState("processing", "Transcribing…", "Gemini is cleaning up your words");
    processTranscription(wavData);
}

void VoiceService::cancel() {
    m_idleResetTimer->stop();
    m_safetyTimer->stop();

    m_isRecording = false;

    if (m_captureProcess) {
        m_captureProcess->disconnect();
        if (m_captureProcess->state() != QProcess::NotRunning) {
            m_captureProcess->terminate();
            if (!m_captureProcess->waitForFinished(300)) {
                m_captureProcess->kill();
            }
        }
        m_captureProcess->deleteLater();
        m_captureProcess = nullptr;
    }

    if (!m_tempWavPath.isEmpty() && QFile::exists(m_tempWavPath)) {
        QFile::remove(m_tempWavPath);
    }

    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply->deleteLater();
        m_activeReply = nullptr;
    }

    setState("idle", "", "");
}

void VoiceService::processTranscription(const QByteArray& wavData) {
    QStringList keys = getAllAvailableKeys();
    if (keys.isEmpty()) {
        setState("error", "Gemini key unavailable", "Add it in Settings > Voice typing");
        scheduleResetToIdle(5000);
        return;
    }

    sendGeminiRequest(keys, wavData);
}

void VoiceService::sendGeminiRequest(QStringList remainingKeys, const QByteArray& wavData) {
    if (remainingKeys.isEmpty()) {
        setState("error", "Voice typing failed", "All configured Gemini keys failed");
        scheduleResetToIdle(5000);
        return;
    }

    const QString apiKey = remainingKeys.takeFirst();
    const QUrl url(
        QString("https://generativelanguage.googleapis.com/v1beta/models/%1:generateContent?key=%2")
            .arg(m_model, apiKey));

    QJsonObject inlineDataObj;
    inlineDataObj["mime_type"] = "audio/wav";
    inlineDataObj["data"] = QString::fromLatin1(wavData.toBase64());

    QJsonObject promptPart;
    promptPart["text"] = m_prompt;

    QJsonObject audioPart;
    audioPart["inline_data"] = inlineDataObj;

    QJsonArray partsArray;
    partsArray.append(promptPart);
    partsArray.append(audioPart);

    QJsonObject contentObj;
    contentObj["parts"] = partsArray;

    QJsonArray contentsArray;
    contentsArray.append(contentObj);

    QJsonObject genConfigObj;
    genConfigObj["temperature"] = 0;

    QJsonObject rootObj;
    rootObj["contents"] = contentsArray;
    rootObj["generationConfig"] = genConfigObj;

    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    QNetworkReply* reply = m_networkManager->post(request, QJsonDocument(rootObj).toJson(QJsonDocument::Compact));
    m_activeReply = reply;

    connect(reply, &QNetworkReply::finished, this, [this, reply, remainingKeys, wavData]() {
        if (m_activeReply == reply) {
            m_activeReply = nullptr;
        }
        reply->deleteLater();

        if (reply->error() == QNetworkReply::OperationCanceledError || m_status == "idle") {
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            if (!remainingKeys.isEmpty()) {
                sendGeminiRequest(remainingKeys, wavData);
                return;
            }
            setState("error", "Voice typing failed", reply->errorString());
            scheduleResetToIdle(5000);
            return;
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        QString text;
        if (doc.isObject()) {
            const QJsonArray candidates = doc.object()["candidates"].toArray();
            if (!candidates.isEmpty()) {
                const QJsonArray parts = candidates.at(0).toObject()["content"].toObject()["parts"].toArray();
                if (!parts.isEmpty()) {
                    text = parts.at(0).toObject()["text"].toString().trimmed();
                }
            }
        }

        if (text.isEmpty() || text == "<NO TEXT>" || text == "(<NO TEXT>)") {
            setState("empty", "No clear speech detected");
            scheduleResetToIdle(3000);
        } else {
            pasteText(text);
            const QString preview = text.length() <= 120 ? text : text.left(117) + "…";
            setState("done", "Pasted", preview);
            scheduleResetToIdle(3000);
        }
    });
}

void VoiceService::pasteText(const QString& text) {
    if (QGuiApplication::clipboard()) {
        QGuiApplication::clipboard()->setText(text);
    }

    QProcess* wlCopyProc = new QProcess(this);
    connect(wlCopyProc, &QProcess::finished, wlCopyProc, &QObject::deleteLater);
    connect(wlCopyProc, &QProcess::errorOccurred, wlCopyProc, &QObject::deleteLater);
    wlCopyProc->start("wl-copy", QStringList());
    wlCopyProc->write(text.toUtf8());
    wlCopyProc->closeWriteChannel();

    QTimer::singleShot(60, this, []() {
        QProcess* wtypeProc = new QProcess();
        auto onWtypeFinished = [wtypeProc](int exitCode) {
            wtypeProc->deleteLater();
            if (exitCode != 0) {
                QProcess* ydotoolProc = new QProcess();
                QObject::connect(ydotoolProc, &QProcess::finished, ydotoolProc, &QObject::deleteLater);
                QObject::connect(ydotoolProc, &QProcess::errorOccurred, ydotoolProc, &QObject::deleteLater);
                ydotoolProc->start("ydotool", {"key", "29:1", "47:1", "47:0", "29:0"});
            }
        };
        QObject::connect(wtypeProc, &QProcess::finished, onWtypeFinished);
        QObject::connect(wtypeProc, &QProcess::errorOccurred, [wtypeProc]() {
            wtypeProc->deleteLater();
            QProcess* ydotoolProc = new QProcess();
            QObject::connect(ydotoolProc, &QProcess::finished, ydotoolProc, &QObject::deleteLater);
            QObject::connect(ydotoolProc, &QProcess::errorOccurred, ydotoolProc, &QObject::deleteLater);
            ydotoolProc->start("ydotool", {"key", "29:1", "47:1", "47:0", "29:0"});
        });
        wtypeProc->start("wtype", {"-M", "ctrl", "-k", "v", "-m", "ctrl"});
    });
}

} // namespace caelestia::services
