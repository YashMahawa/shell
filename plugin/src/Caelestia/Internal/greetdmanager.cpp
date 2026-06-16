#include "greetdmanager.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcessEnvironment>

namespace caelestia {

GreetdManager::GreetdManager(QObject* parent) : QObject(parent), m_socket(new QLocalSocket(this)), m_timer(new QTimer(this)) {
    m_timer->setSingleShot(true);
    m_timer->setInterval(10000); // 10 seconds timeout
    connect(m_timer, &QTimer::timeout, this, &GreetdManager::handleTimeout);
    connect(m_socket, &QLocalSocket::connected, this, &GreetdManager::handleConnected);
    connect(m_socket, &QLocalSocket::readyRead, this, &GreetdManager::handleReadyRead);
    connect(m_socket, &QLocalSocket::errorOccurred, this, &GreetdManager::handleError);
}

QString GreetdManager::currentUser() const {
    return m_currentUser;
}

void GreetdManager::setCurrentUser(const QString& user) {
    if (m_currentUser != user) {
        m_currentUser = user;
        emit currentUserChanged();
    }
}

void GreetdManager::resetState(const QString& errorReason) {
    m_timer->stop();
    m_state = State::Idle;
    m_pendingUser.clear();
    m_pendingPassword.clear();
    m_buffer.clear();
    if (m_socket->state() != QLocalSocket::UnconnectedState) {
        m_socket->disconnectFromServer();
    }
    if (!errorReason.isEmpty()) {
        emit authFailed(errorReason);
    }
}

void GreetdManager::authenticate(const QString& user, const QString& password) {
    if (m_state != State::Idle) {
        resetState("Authentication already in progress");
        return;
    }

    QString sockPath = QProcessEnvironment::systemEnvironment().value("GREETD_SOCK");
    if (sockPath.isEmpty()) {
        emit authFailed("GREETD_SOCK not set");
        return;
    }

    m_pendingUser = user;
    m_pendingPassword = password;
    m_buffer.clear();
    m_state = State::Connecting;
    m_timer->start();

    if (m_socket->state() != QLocalSocket::UnconnectedState) {
        m_socket->disconnectFromServer();
    }
    
    m_socket->connectToServer(sockPath);
}

void GreetdManager::handleConnected() {
    if (m_state == State::Connecting) {
        m_timer->start();
        m_state = State::Auth_CreatingSession;
        QJsonObject createReq;
        createReq["type"] = "create_session";
        createReq["username"] = m_pendingUser;
        sendRequest(createReq);
    }
}

void GreetdManager::handleError(QLocalSocket::LocalSocketError error) {
    if (m_state != State::Idle) {
        resetState("Socket error: " + m_socket->errorString());
    }
}

void GreetdManager::sendRequest(const QJsonObject& req) {
    QByteArray reqData = QJsonDocument(req).toJson(QJsonDocument::Compact);
    quint32 len = reqData.length();
    
    QByteArray packet;
    packet.append(reinterpret_cast<const char*>(&len), sizeof(len));
    packet.append(reqData);
    
    m_socket->write(packet);
}

void GreetdManager::handleReadyRead() {
    m_buffer.append(m_socket->readAll());

    while (m_buffer.length() >= 4) {
        quint32 resLen = *reinterpret_cast<const quint32*>(m_buffer.constData());
        int totalLen = 4 + static_cast<int>(resLen);
        if (m_buffer.length() < totalLen) {
            break; // Need more data
        }

        QByteArray resData = m_buffer.mid(4, static_cast<int>(resLen));
        m_buffer.remove(0, totalLen);

        QJsonObject res = QJsonDocument::fromJson(resData).object();
        processResponse(res);
    }
}

void GreetdManager::processResponse(const QJsonObject& res) {
    QString type = res["type"].toString();

    if (type == "error") {
        resetState(res["error_description"].toString());
        return;
    }

    if (m_state == State::Auth_CreatingSession) {
        if (type == "success") {
            setCurrentUser(m_pendingUser);
            m_pendingPassword.clear(); // Clear password as it's no longer needed
            m_state = State::Idle;
            m_timer->stop();
            emit authSuccess();
        } else if (type == "auth_message") {
            m_state = State::Auth_PostingAuth;
            m_timer->start();
            QJsonObject authReq;
            authReq["type"] = "post_auth_message_response";
            authReq["response"] = m_pendingPassword;
            sendRequest(authReq);
            m_pendingPassword.clear(); // Clear it immediately after sending
        } else {
            resetState("Unexpected create_session response");
        }
    } else if (m_state == State::Auth_PostingAuth) {
        if (type == "auth_message") {
            resetState("PAM/Auth Error: " + res["auth_message"].toString());
        } else if (type == "success") {
            setCurrentUser(m_pendingUser);
            m_state = State::Idle;
            m_timer->stop();
            emit authSuccess();
        } else {
            resetState("Unexpected response type");
        }
    } else if (m_state == State::StartingSession) {
        // usually we don't handle this as greetd replaces itself or drops connection,
        // but if we get here and it's success, we just go to idle.
        if (type == "success") {
            m_state = State::Idle;
            m_timer->stop();
        } else {
            resetState("Failed to start session");
        }
    }
}

void GreetdManager::startSession(const QStringList& cmd) {
    if (m_socket->state() != QLocalSocket::ConnectedState) {
        return;
    }
    if (cmd.isEmpty() || cmd.first().isEmpty()) {
        emit authFailed("Invalid session command");
        return;
    }

    m_state = State::StartingSession;
    m_timer->start();
    QJsonObject startReq;
    startReq["type"] = "start_session";
    QJsonArray cmdArray;
    for (const QString& c : cmd) cmdArray.append(c);
    startReq["cmd"] = cmdArray;

    sendRequest(startReq);
}

void GreetdManager::handleTimeout() {
    if (m_state != State::Idle) {
        emit status("Authentication timed out");
        // Cancel the greetd session by disconnecting
        // resetState handles disconnecting, clearing state/passwords, and emitting authFailed
        resetState("Authentication timed out");
    }
}

} // namespace caelestia
