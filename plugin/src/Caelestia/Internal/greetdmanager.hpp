#pragma once

#include <QObject>
#include <QString>
#include <QLocalSocket>
#include <QJsonObject>
#include <QTimer>
#include <qqmlintegration.h>

namespace caelestia {

class GreetdManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString currentUser READ currentUser WRITE setCurrentUser NOTIFY currentUserChanged)

public:
    explicit GreetdManager(QObject* parent = nullptr);

    QString currentUser() const;
    void setCurrentUser(const QString& user);

    Q_INVOKABLE void authenticate(const QString& user, const QString& password);
    Q_INVOKABLE void startSession(const QStringList& cmd);

signals:
    void currentUserChanged();
    void authSuccess();
    void authFailed(const QString& reason);
    void status(const QString& message);

private slots:
    void handleReadyRead();
    void handleError(QLocalSocket::LocalSocketError error);
    void handleConnected();
    void handleTimeout();

private:
    void sendRequest(const QJsonObject& req);
    void processResponse(const QJsonObject& res);
    void resetState(const QString& errorReason = QString());

    QString m_currentUser;
    QLocalSocket* m_socket;
    QTimer* m_timer;

    enum class State { Idle, Connecting, Auth_CreatingSession, Auth_PostingAuth, StartingSession };
    State m_state = State::Idle;

    QString m_pendingUser;
    QString m_pendingPassword;
    QByteArray m_buffer;
};

} // namespace caelestia
