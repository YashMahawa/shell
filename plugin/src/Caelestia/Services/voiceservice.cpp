#include "voiceservice.hpp"

#include <algorithm>
#include <random>
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>

#include <QClipboard>
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
#include <QThread>

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
        setState("idle", "");
    });

    loadConfig();
    refreshKeys();
}

VoiceService::~VoiceService() {
    if (m_isRecording) {
        m_isRecording = false;
        if (m_recordThread.joinable()) {
            m_recordThread.request_stop();
            m_recordThread.join();
        }
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

void VoiceService::appendAudioChunk(const char* data, qsizetype size) {
    QMutexLocker locker(&m_pcmMutex);
    if (m_isRecording) {
        m_pcmData.append(data, size);
    }
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

    {
        QMutexLocker locker(&m_pcmMutex);
        m_pcmData.clear();
    }

    m_isRecording = true;
    setState("listening", "Listening…", "Press F9 again to transcribe");
    m_safetyTimer->start(60000);

    if (m_recordThread.joinable()) {
        m_recordThread.request_stop();
        m_recordThread.join();
    }

    m_recordThread = std::jthread([this](std::stop_token token) {
        pw_init(nullptr, nullptr);
        pw_main_loop* loop = pw_main_loop_new(nullptr);
        if (!loop) {
            pw_deinit();
            return;
        }

        pw_properties* props = pw_properties_new(
            PW_KEY_MEDIA_TYPE, "Audio", PW_KEY_MEDIA_CATEGORY, "Capture", PW_KEY_MEDIA_ROLE, "Music", nullptr);
        pw_properties_set(props, PW_KEY_STREAM_CAPTURE_SINK, "false");
        pw_properties_set(props, PW_KEY_NODE_PASSIVE, "true");

        std::vector<uint8_t> buffer(1024);
        spa_pod_builder b;
        spa_pod_builder_init(&b, buffer.data(), static_cast<uint32_t>(buffer.size()));

        spa_audio_info_raw info{};
        info.format = SPA_AUDIO_FORMAT_S16;
        info.rate = 16000;
        info.channels = 1;

        const spa_pod* params[1];
        params[0] = spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);

        struct PWContext {
            pw_stream* stream = nullptr;
            VoiceService* service = nullptr;
        } ctx;
        ctx.service = this;

        pw_stream_events events{};
        events.version = PW_VERSION_STREAM_EVENTS;
        events.process = [](void* data) {
            auto* c = static_cast<PWContext*>(data);
            pw_buffer* buf = pw_stream_dequeue_buffer(c->stream);
            if (!buf)
                return;

            const spa_buffer* sbuf = buf->buffer;
            if (sbuf && sbuf->datas[0].data) {
                const char* samples = static_cast<const char*>(sbuf->datas[0].data);
                uint32_t size = sbuf->datas[0].chunk->size;
                if (samples && size > 0) {
                    c->service->appendAudioChunk(samples, static_cast<qsizetype>(size));
                }
            }
            pw_stream_queue_buffer(c->stream, buf);
        };

        ctx.stream = pw_stream_new_simple(pw_main_loop_get_loop(loop), "caelestia-voice", props, &events, &ctx);
        if (ctx.stream) {
            pw_stream_connect(
                ctx.stream,
                PW_DIRECTION_INPUT,
                PW_ID_ANY,
                static_cast<pw_stream_flags>(
                    PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS),
                params,
                1);

            while (!token.stop_requested()) {
                pw_loop_iterate(pw_main_loop_get_loop(loop), 10);
            }

            pw_stream_destroy(ctx.stream);
        }

        pw_main_loop_destroy(loop);
        pw_deinit();
    });
}

void VoiceService::stopCapture() {
    if (!m_isRecording)
        return;

    m_isRecording = false;
    m_safetyTimer->stop();

    if (m_recordThread.joinable()) {
        m_recordThread.request_stop();
        m_recordThread.join();
    }

    QByteArray rawPcm;
    {
        QMutexLocker locker(&m_pcmMutex);
        rawPcm = m_pcmData;
        m_pcmData.clear();
    }

    QByteArray wavData;
    uint32_t pcmSize = static_cast<uint32_t>(rawPcm.size());
    uint32_t chunkSize = 36 + pcmSize;
    uint32_t sampleRate = 16000;
    uint16_t channels = 1;
    uint16_t bitsPerSample = 16;
    uint32_t byteRate = sampleRate * channels * (bitsPerSample / 8);
    uint16_t blockAlign = channels * (bitsPerSample / 8);
    uint32_t subchunk1Size = 16;
    uint16_t audioFormat = 1;

    wavData.append("RIFF", 4);
    wavData.append(reinterpret_cast<const char*>(&chunkSize), 4);
    wavData.append("WAVE", 4);
    wavData.append("fmt ", 4);
    wavData.append(reinterpret_cast<const char*>(&subchunk1Size), 4);
    wavData.append(reinterpret_cast<const char*>(&audioFormat), 2);
    wavData.append(reinterpret_cast<const char*>(&channels), 2);
    wavData.append(reinterpret_cast<const char*>(&sampleRate), 4);
    wavData.append(reinterpret_cast<const char*>(&byteRate), 4);
    wavData.append(reinterpret_cast<const char*>(&blockAlign), 2);
    wavData.append(reinterpret_cast<const char*>(&bitsPerSample), 2);
    wavData.append("data", 4);
    wavData.append(reinterpret_cast<const char*>(&pcmSize), 4);
    wavData.append(rawPcm);

    if (pcmSize < 4800) {
        setState("empty", "No clear speech detected");
        scheduleResetToIdle(3000);
        return;
    }

    setState("processing", "Transcribing…", "Gemini is cleaning up your words");
    processTranscription(wavData);
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

void VoiceService::cancel() {
    m_idleResetTimer->stop();
    m_safetyTimer->stop();

    if (m_isRecording) {
        m_isRecording = false;
        if (m_recordThread.joinable()) {
            m_recordThread.request_stop();
            m_recordThread.join();
        }
    }

    if (m_activeReply) {
        m_activeReply->abort();
        m_activeReply->deleteLater();
        m_activeReply = nullptr;
    }

    {
        QMutexLocker locker(&m_pcmMutex);
        m_pcmData.clear();
    }

    setState("idle", "", "");
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
    QProcess::execute("wl-copy", {"--", text});

    QThread::msleep(60);

    const int ret = QProcess::execute("wtype", {"-M", "ctrl", "-k", "v", "-m", "ctrl"});
    if (ret != 0) {
        QProcess::execute("ydotool", {"key", "29:1", "47:1", "47:0", "29:0"});
    }
}

} // namespace caelestia::services
