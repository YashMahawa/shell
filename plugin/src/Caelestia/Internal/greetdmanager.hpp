#pragma once

#include <QObject>
#include <QString>
#include <QLocalSocket>
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

private:
    QString m_currentUser;
    QLocalSocket* m_socket;
};

} // namespace caelestia
