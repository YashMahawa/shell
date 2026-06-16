#include "greetdmanager.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcessEnvironment>
#include <QDebug>

namespace caelestia {

GreetdManager::GreetdManager(QObject* parent) : QObject(parent), m_socket(new QLocalSocket(this)) {}

QString GreetdManager::currentUser() const {
    return m_currentUser;
}

void GreetdManager::setCurrentUser(const QString& user) {
    if (m_currentUser != user) {
        m_currentUser = user;
        emit currentUserChanged();
    }
}

void GreetdManager::authenticate(const QString& user, const QString& password) {
    QString sockPath = QProcessEnvironment::systemEnvironment().value("GREETD_SOCK");
    if (sockPath.isEmpty()) {
        emit authFailed("GREETD_SOCK not set");
        return;
    }

    if (m_socket->state() != QLocalSocket::UnconnectedState) {
        m_socket->disconnectFromServer();
    }
    
    m_socket->connectToServer(sockPath);
    if (!m_socket->waitForConnected(1000)) {
        emit authFailed("Failed to connect to greetd");
        return;
    }

    // Helper lambda to send request and read response
    auto doReq = [this](const QJsonObject& req) -> QByteArray {
        QByteArray reqData = QJsonDocument(req).toJson(QJsonDocument::Compact);
        quint32 len = reqData.length();
        
        QByteArray packet;
        packet.append(reinterpret_cast<const char*>(&len), sizeof(len));
        packet.append(reqData);
        
        m_socket->write(packet);
        if (!m_socket->waitForBytesWritten(1000) || !m_socket->waitForReadyRead(1000)) {
            return QByteArray();
        }
        
        QByteArray lenBytes = m_socket->read(4);
        if (lenBytes.length() < 4) return QByteArray();
        
        quint32 resLen = *reinterpret_cast<const quint32*>(lenBytes.constData());
        
        QByteArray resData;
        while (resData.length() < resLen) {
            if (!m_socket->waitForReadyRead(1000)) break;
            resData.append(m_socket->read(resLen - resData.length()));
        }
        
        return resData;
    };

    // 1. Create session
    QJsonObject createReq;
    createReq["type"] = "create_session";
    createReq["username"] = user;

    QByteArray createResBytes = doReq(createReq);
    if (createResBytes.isEmpty()) {
        emit authFailed("Failed to communicate with greetd (create_session)");
        m_socket->disconnectFromServer();
        return;
    }

    QJsonObject createRes = QJsonDocument::fromJson(createResBytes).object();
    if (createRes["type"].toString() == "error") {
        emit authFailed(createRes["error_description"].toString());
        m_socket->disconnectFromServer();
        return;
    }

    // 2. Post auth response (password)
    QJsonObject authReq;
    authReq["type"] = "post_auth_message_response";
    authReq["response"] = password;

    QByteArray authResBytes = doReq(authReq);
    if (authResBytes.isEmpty()) {
        emit authFailed("Failed to communicate with greetd (post_auth)");
        m_socket->disconnectFromServer();
        return;
    }

    QJsonObject authRes = QJsonDocument::fromJson(authResBytes).object();
    if (authRes["type"].toString() == "error") {
        emit authFailed(authRes["error_description"].toString());
        m_socket->disconnectFromServer();
        return;
    }
    if (authRes["type"].toString() == "auth_message") {
        emit authFailed("PAM/Auth Error: " + authRes["auth_message"].toString());
        m_socket->disconnectFromServer();
        return;
    }
    if (authRes["type"].toString() != "success") {
        emit authFailed("Unexpected response type");
        m_socket->disconnectFromServer();
        return;
    }

    // Auth succeeded!
    setCurrentUser(user);
    emit authSuccess();
}

void GreetdManager::startSession(const QStringList& cmd) {
    if (m_socket->state() != QLocalSocket::ConnectedState) {
        return;
    }
    if (cmd.isEmpty() || cmd.first().isEmpty()) {
        emit authFailed("Invalid session command");
        return;
    }

    QJsonObject startReq;
    startReq["type"] = "start_session";
    QJsonArray cmdArray;
    for (const QString& c : cmd) cmdArray.append(c);
    startReq["cmd"] = cmdArray;

    QByteArray reqData = QJsonDocument(startReq).toJson(QJsonDocument::Compact);
    quint32 len = reqData.length();
    
    QByteArray packet;
    packet.append(reinterpret_cast<const char*>(&len), sizeof(len));
    packet.append(reqData);

    m_socket->write(packet);
    m_socket->waitForBytesWritten(1000);
    m_socket->waitForReadyRead(1000);
    
    QByteArray lenBytes = m_socket->read(4);
    if (lenBytes.length() == 4) {
        quint32 resLen = *reinterpret_cast<const quint32*>(lenBytes.constData());
        QByteArray resData;
        while (resData.length() < resLen) {
            if (!m_socket->waitForReadyRead(1000)) break;
            resData.append(m_socket->read(resLen - resData.length()));
        }
    }
}

} // namespace caelestia
