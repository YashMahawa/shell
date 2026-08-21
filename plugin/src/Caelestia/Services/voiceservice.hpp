#pragma once

#include "service.hpp"

#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QObject>
#include <qqmlintegration.h>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariant>

#include <stop_token>
#include <thread>

namespace caelestia::services {

class VoiceService : public Service {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)
    Q_PROPERTY(QString detail READ detail NOTIFY detailChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(QVariantList storedKeys READ storedKeys NOTIFY storedKeysChanged)
    Q_PROPERTY(QString prompt READ prompt NOTIFY promptChanged)
    Q_PROPERTY(QString model READ model NOTIFY modelChanged)

public:
    explicit VoiceService(QObject* parent = nullptr);
    ~VoiceService() override;

    [[nodiscard]] QString status() const { return m_status; }
    [[nodiscard]] QString message() const { return m_message; }
    [[nodiscard]] QString detail() const { return m_detail; }
    [[nodiscard]] bool active() const { return !m_status.isEmpty() && m_status != "idle"; }
    [[nodiscard]] QVariantList storedKeys() const;
    [[nodiscard]] QString prompt() const { return m_prompt; }
    [[nodiscard]] QString model() const { return m_model; }

    Q_INVOKABLE void toggle();
    Q_INVOKABLE void startCapture();
    Q_INVOKABLE void stopCapture();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void storeKey(int slot, const QString& key);
    Q_INVOKABLE void clearKey(int slot);
    Q_INVOKABLE void savePrompt(const QString& prompt);
    Q_INVOKABLE void refreshKeys();
    Q_INVOKABLE QVariantMap statusInfo() const;

    void appendAudioChunk(const char* data, qsizetype size);

signals:
    void statusChanged();
    void messageChanged();
    void detailChanged();
    void activeChanged();
    void storedKeysChanged();
    void promptChanged();
    void modelChanged();

protected:
    void start() override {}
    void stop() override {}

private:
    void setState(const QString& status, const QString& message, const QString& detail = "");
    void loadConfig();
    void saveConfig();
    void fetchKeysFromKeyring();
    QString lookupSecretDBus(int slot);
    bool storeSecretDBus(int slot, const QString& secret);
    bool clearSecretDBus(int slot);
    QStringList getAllAvailableKeys();
    void processTranscription(const QByteArray& wavData);
    void sendGeminiRequest(QStringList remainingKeys, const QByteArray& wavData);
    void pasteText(const QString& text);
    void scheduleResetToIdle(int delayMs);

    QString m_status = "idle";
    QString m_message;
    QString m_detail;
    QString m_prompt;
    QString m_model = "gemini-3.1-flash-lite";

    bool m_keyPresence[3] = {false, false, false};
    QString m_cachedKeys[3];

    QTimer* m_safetyTimer = nullptr;
    QTimer* m_idleResetTimer = nullptr;
    QNetworkAccessManager* m_networkManager = nullptr;
    QNetworkReply* m_activeReply = nullptr;

    bool m_isRecording = false;
    QByteArray m_pcmData;
    QMutex m_pcmMutex;
    std::jthread m_recordThread;
};

} // namespace caelestia::services
