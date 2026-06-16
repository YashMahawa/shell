#pragma once

#include <QObject>
#include <QString>
#include <QLocalSocket>
#include <qqmlintegration.h>

namespace caelestia {

/**
 * @brief Native greetd authentication and session handoff manager.
 * 
 * This class implements the JSON over Unix socket IPC protocol used by greetd.
 * The typical protocol flow for authentication is:
 * 1. create_session (with username) -> greetd responds with an auth_message (e.g. PAM password prompt).
 * 2. post_auth_message_response (with secret) -> greetd responds with success (or error/another auth_message).
 * 3. start_session (with command array) -> greetd replaces itself with the target user's session.
 */
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

private:
    QString m_currentUser;
    QLocalSocket* m_socket;
};

} // namespace caelestia
