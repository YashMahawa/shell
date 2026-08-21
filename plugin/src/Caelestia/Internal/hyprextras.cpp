#include "hyprextras.hpp"
#include "hyprdevices.hpp"

#include <qdir.h>
#include <qjsonarray.h>
#include <qlocalsocket.h>
#include <qloggingcategory.h>
#include <qvariant.h>

Q_LOGGING_CATEGORY(lcHypr, "caelestia.internal.hypr", QtInfoMsg)

namespace caelestia::internal::hypr {

HyprExtras::HyprExtras(QObject* parent)
    : QObject(parent)
    , m_requestSocket("")
    , m_eventSocket("")
    , m_socket(nullptr)
    , m_socketValid(false)
    , m_devices(new HyprDevices(this)) {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        qCWarning(lcHypr) << "$HYPRLAND_INSTANCE_SIGNATURE is unset. Unable to connect to Hyprland socket.";
        return;
    }

    auto hyprDir = QString("%1/hypr/%2").arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = "/tmp/hypr/" + his;

        if (!QDir(hyprDir).exists()) {
            qCWarning(lcHypr) << "Hyprland socket directory does not exist. Unable to connect to Hyprland socket.";
            return;
        }
    }

    m_requestSocket = hyprDir + "/.socket.sock";
    m_eventSocket = hyprDir + "/.socket2.sock";

    refreshOptions();
    refreshDevices();

    m_socket = new QLocalSocket(this);

    QObject::connect(m_socket, &QLocalSocket::errorOccurred, this, &HyprExtras::socketError);
    QObject::connect(m_socket, &QLocalSocket::stateChanged, this, &HyprExtras::socketStateChanged);
    QObject::connect(m_socket, &QLocalSocket::readyRead, this, &HyprExtras::readEvent);

    m_socket->connectToServer(m_eventSocket, QLocalSocket::ReadOnly);
}

QVariantHash HyprExtras::options() const {
    return m_options;
}

HyprDevices* HyprExtras::devices() const {
    return m_devices;
}

void HyprExtras::message(const QString& message) {
    if (message.isEmpty()) {
        return;
    }

    makeRequest(message, [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "message: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::batchMessage(const QStringList& messages) {
    if (messages.isEmpty()) {
        return;
    }

    makeRequest("[[BATCH]]" + messages.join(";"), [](bool success, const QByteArray& res) {
        if (!success) {
            qCWarning(lcHypr) << "batchMessage: request error:" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::applyOptions(const QVariantHash& options) {
    if (options.isEmpty()) {
        return;
    }

    QString request;
    request.reserve(12 + options.size() * 40);
    request += QLatin1String("[[BATCH]]");
    for (auto it = options.constBegin(); it != options.constEnd(); ++it) {
        if (!m_usingLua) {
            request +=
                QLatin1String("keyword ") + it.key() + QLatin1Char(' ') + it.value().toString() + QLatin1Char(';');
        } else {
            auto parts = it.key().split(':');
            request += "eval hl.config({ " + parts.join(" = { ") + " = " + it.value().toString() +
                       QString(" }").repeated(parts.size() - 1) + " });";
        }
    }

    makeRequest(request, [this](bool success, const QByteArray& res) {
        if (success) {
            refreshOptions();
        } else {
            qCWarning(lcHypr) << "applyOptions: request error" << QString::fromUtf8(res);
        }
    });
}

void HyprExtras::refreshOptions() {
    if (!m_optionsRefresh.isNull()) {
        m_optionsRefreshPending = true;
        return;
    }

    m_optionsRefreshPending = false;
    m_optionsRefresh = makeRequestJson("descriptions", [this](bool success, const QJsonDocument& response) {
        m_optionsRefresh.reset();
        if (!success) {
            if (m_optionsRefreshPending) {
                m_optionsRefreshPending = false;
                refreshOptions();
            }
            return;
        }

        const auto options = response.array();
        bool dirty = false;

        for (const auto& o : std::as_const(options)) {
            const auto obj = o.toObject();
            const auto key = obj.value("value").toString();
            const auto value = obj.value("data").toObject().value("current").toVariant();
            if (m_options.value(key) != value) {
                dirty = true;
                m_options.insert(key, value);
            }
        }

        if (dirty) {
            emit optionsChanged();
        }

        if (m_optionsRefreshPending) {
            m_optionsRefreshPending = false;
            refreshOptions();
        }
    });
}

void HyprExtras::refreshDevices() {
    if (!m_devicesRefresh.isNull()) {
        m_devicesRefreshPending = true;
        return;
    }

    m_devicesRefreshPending = false;
    m_devicesRefresh = makeRequestJson("devices", [this](bool success, const QJsonDocument& response) {
        m_devicesRefresh.reset();
        if (success) {
            m_devices->updateLastIpcObject(response.object());
        }

        if (m_devicesRefreshPending) {
            m_devicesRefreshPending = false;
            refreshDevices();
        }
    });
}

void HyprExtras::socketError(QLocalSocket::LocalSocketError error) const {
    if (!m_socketValid) {
        qCWarning(lcHypr) << "socketError: unable to connect to Hyprland event socket:" << error;
    } else {
        qCWarning(lcHypr) << "socketError: Hyprland event socket error:" << error;
    }
}

void HyprExtras::socketStateChanged(QLocalSocket::LocalSocketState state) {
    if (state == QLocalSocket::UnconnectedState && m_socketValid) {
        qCWarning(lcHypr) << "socketStateChanged: Hyprland event socket disconnected.";
    }

    const bool wasConnected = m_socketValid;
    m_socketValid = (state == QLocalSocket::ConnectedState);

    if (m_socketValid && !wasConnected) {
        resetCapabilities();
        refreshOptions();
        refreshDevices();
    }
}

void HyprExtras::resetCapabilities() {
    m_hasV2Config = false;
    m_hasV2Layout = false;
}

void HyprExtras::readEvent() {
    while (m_socket && m_socket->canReadLine()) {
        auto rawEvent = m_socket->readLine();
        if (rawEvent.endsWith('\n')) {
            rawEvent.chop(1);
        }
        if (rawEvent.endsWith('\r')) {
            rawEvent.chop(1);
        }
        if (rawEvent.isEmpty()) {
            continue;
        }

        const int sep = rawEvent.indexOf(">>");
        if (sep != -1) {
            const auto name = QString::fromUtf8(rawEvent.left(sep));
            const auto data = QString::fromUtf8(rawEvent.mid(sep + 2));
            handleEvent(name, data);
        } else {
            handleEvent(QString::fromUtf8(rawEvent), QString());
        }
    }
}

void HyprExtras::handleEvent(const QString& name, const QString& data) {
    if (name == QLatin1String("configreloadedv2")) {
        m_hasV2Config = true;
        refreshOptions();
    } else if (name == QLatin1String("configreloaded")) {
        if (!m_hasV2Config) {
            refreshOptions();
        }
    } else if (name == QLatin1String("activelayoutv2")) {
        m_hasV2Layout = true;
        const auto parts = data.split(QLatin1Char(','));
        if (parts.size() >= 3) {
            const auto kbName = parts[0].trimmed();
            const auto layoutName = parts[1].trimmed();
            bool ok = false;
            const int layoutIdx = parts[2].trimmed().toInt(&ok);
            if (ok && m_devices) {
                m_devices->updateActiveLayout(kbName, layoutName, layoutIdx);
            }
        }
        refreshDevices();
    } else if (name == QLatin1String("activelayout")) {
        if (!m_hasV2Layout) {
            const auto parts = data.split(QLatin1Char(','));
            if (parts.size() >= 2 && m_devices) {
                const auto kbName = parts[0].trimmed();
                const auto layoutName = parts[1].trimmed();
                m_devices->updateActiveLayout(kbName, layoutName, -1);
            }
            refreshDevices();
        }
    }
}

HyprExtras::SocketPtr HyprExtras::makeRequestJson(
    const QString& request, const std::function<void(bool, QJsonDocument)>& callback) {
    return makeRequest("j/" + request, [callback](bool success, const QByteArray& response) {
        callback(success, QJsonDocument::fromJson(response));
    });
}

HyprExtras::SocketPtr HyprExtras::makeRequest(
    const QString& request, const std::function<void(bool, QByteArray)>& callback) {
    if (m_requestSocket.isEmpty()) {
        return SocketPtr();
    }

    auto socket = SocketPtr::create(this);

    QObject::connect(socket.data(), &QLocalSocket::connected, this, [=, this]() {
        QObject::connect(socket.data(), &QLocalSocket::readyRead, this, [socket, callback]() {
            const auto response = socket->readAll();
            callback(true, std::move(response));
            socket->close();
        });

        socket->write(request.toUtf8());
        socket->flush();
    });

    QObject::connect(socket.data(), &QLocalSocket::errorOccurred, this, [=](QLocalSocket::LocalSocketError err) {
        qCWarning(lcHypr) << "makeRequest: error making request:" << err << "| request:" << request;
        callback(false, {});
        socket->close();
    });

    socket->connectToServer(m_requestSocket);

    return socket;
}

} // namespace caelestia::internal::hypr
