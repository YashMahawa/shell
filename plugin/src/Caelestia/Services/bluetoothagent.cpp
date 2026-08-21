#include "bluetoothagent.hpp"

#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusConnectionInterface>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcBtAgent, "caelestia.services.bluetoothagent", QtInfoMsg)

namespace caelestia::services {

BluetoothAgent::BluetoothAgent(QObject* parent)
    : QObject(parent) {
    m_timeoutTimer = new QTimer(this);
    m_timeoutTimer->setSingleShot(true);
    connect(m_timeoutTimer, &QTimer::timeout, this, &BluetoothAgent::handleTimeout);

    auto bus = QDBusConnection::systemBus();
    if (bus.isConnected()) {
        m_serviceWatcher = new QDBusServiceWatcher(
            QStringLiteral("org.bluez"),
            bus,
            QDBusServiceWatcher::WatchForOwnerChange,
            this
        );

        connect(m_serviceWatcher, &QDBusServiceWatcher::serviceOwnerChanged,
                this, &BluetoothAgent::onBluezServiceOwnerChanged);
    } else {
        qCWarning(lcBtAgent) << "System bus not connected, BluetoothAgent cannot register.";
    }
}

BluetoothAgent::~BluetoothAgent() {
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Agent shutting down"));
    unregisterAgent();
}

void BluetoothAgent::setCapability(const QString& cap) {
    if (m_capability == cap) return;
    m_capability = cap;
    emit capabilityChanged();

    if (m_registered) {
        unregisterAgent();
        registerAgent();
    }
}

void BluetoothAgent::registerAgent() {
    if (m_registered) return;

    auto bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) return;

    const QString agentPath = QStringLiteral("/org/caelestia/BluetoothAgent");
    if (!bus.registerObject(agentPath, this, QDBusConnection::ExportAllSlots)) {
        qCWarning(lcBtAgent) << "Failed to register DBus object at" << agentPath;
        return;
    }

    QDBusInterface agentManager(
        QStringLiteral("org.bluez"),
        QStringLiteral("/org/bluez"),
        QStringLiteral("org.bluez.AgentManager1"),
        bus
    );

    if (!agentManager.isValid()) {
        qCWarning(lcBtAgent) << "BlueZ AgentManager1 interface not available.";
        bus.unregisterObject(agentPath);
        return;
    }

    QDBusObjectPath path(agentPath);
    QDBusReply<void> regReply = agentManager.call(
        QStringLiteral("RegisterAgent"),
        QVariant::fromValue(path),
        m_capability
    );

    if (!regReply.isValid()) {
        qCWarning(lcBtAgent) << "Failed to register BlueZ agent:" << regReply.error().message();
        bus.unregisterObject(agentPath);
        return;
    }

    QDBusReply<void> defReply = agentManager.call(
        QStringLiteral("RequestDefaultAgent"),
        QVariant::fromValue(path)
    );
    if (!defReply.isValid()) {
        qCWarning(lcBtAgent) << "Failed to set default agent:" << defReply.error().message();
    }

    m_registered = true;
    m_wasRegistered = true;
    qCInfo(lcBtAgent) << "Registered BlueZ agent at" << agentPath << "with capability" << m_capability;
    emit registeredChanged();
}

void BluetoothAgent::unregisterAgent() {
    m_wasRegistered = false;
    const QString agentPath = QStringLiteral("/org/caelestia/BluetoothAgent");
    auto bus = QDBusConnection::systemBus();
    if (bus.isConnected()) {
        if (m_registered) {
            QDBusInterface agentManager(
                QStringLiteral("org.bluez"),
                QStringLiteral("/org/bluez"),
                QStringLiteral("org.bluez.AgentManager1"),
                bus
            );

            if (agentManager.isValid()) {
                QDBusObjectPath path(agentPath);
                agentManager.call(QStringLiteral("UnregisterAgent"), QVariant::fromValue(path));
            }
        }
        bus.unregisterObject(agentPath);
    }

    if (m_registered) {
        m_registered = false;
        qCInfo(lcBtAgent) << "Unregistered BlueZ agent";
        emit registeredChanged();
    }
}

void BluetoothAgent::respondPinCode(const QString& pin) {
    if (m_timeoutTimer) m_timeoutTimer->stop();

    if (m_hasPendingMsg) {
        auto bus = QDBusConnection::systemBus();
        bus.send(m_pendingMsg.createReply(pin));
        m_hasPendingMsg = false;
    }

    m_requestActive = false;
    emit requestActiveChanged();
    emit pairingFinished();
}

void BluetoothAgent::respondPasskey(quint32 passkey) {
    if (m_timeoutTimer) m_timeoutTimer->stop();

    if (m_hasPendingMsg) {
        auto bus = QDBusConnection::systemBus();
        bus.send(m_pendingMsg.createReply(passkey));
        m_hasPendingMsg = false;
    }

    m_requestActive = false;
    emit requestActiveChanged();
    emit pairingFinished();
}

void BluetoothAgent::respondConfirmation(bool accept) {
    if (m_timeoutTimer) m_timeoutTimer->stop();

    if (m_hasPendingMsg) {
        auto bus = QDBusConnection::systemBus();
        if (accept) {
            bus.send(m_pendingMsg.createReply());
        } else {
            bus.send(m_pendingMsg.createErrorReply(
                QStringLiteral("org.bluez.Error.Rejected"),
                QStringLiteral("Pairing rejected by user")
            ));
        }
        m_hasPendingMsg = false;
    }

    m_requestActive = false;
    emit requestActiveChanged();
    if (accept) {
        emit pairingFinished();
    } else {
        emit pairingCanceled();
    }
}

void BluetoothAgent::respondAuthorization(bool accept) {
    respondConfirmation(accept);
}

void BluetoothAgent::cancelPairing() {
    if (m_timeoutTimer) m_timeoutTimer->stop();

    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Pairing canceled by user"));
    emit pairingCanceled();
}

void BluetoothAgent::clearError() {
    if (!m_pairingError.isEmpty()) {
        m_pairingError.clear();
        emit pairingErrorChanged();
    }
}

// DBus slots
void BluetoothAgent::Release() {
    qCInfo(lcBtAgent) << "Agent released by BlueZ";
    m_registered = false;
    m_wasRegistered = false;
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Agent released by BlueZ"));
    emit registeredChanged();
}

QString BluetoothAgent::RequestPinCode(const QDBusObjectPath& device) {
    qCInfo(lcBtAgent) << "RequestPinCode for" << device.path();
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    QDBusMessage msg;
    if (calledFromDBus()) {
        setDelayedReply(true);
        msg = message();
    }
    fetchDeviceInfo(device);
    m_pinCode.clear();
    emit pinCodeChanged();
    setPendingRequest(msg, QStringLiteral("pincode"), device);
    return QString();
}

void BluetoothAgent::DisplayPinCode(const QDBusObjectPath& device, const QString& pincode) {
    qCInfo(lcBtAgent) << "DisplayPinCode for" << device.path() << ":" << pincode;

    if (m_requestActive && m_devicePath == device.path() && m_requestType == QStringLiteral("displaypin")) {
        if (m_pinCode != pincode) {
            m_pinCode = pincode;
            emit pinCodeChanged();
        }
        if (m_timeoutTimer) m_timeoutTimer->start(60000);
        return;
    }

    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    fetchDeviceInfo(device);
    m_pinCode = pincode;
    emit pinCodeChanged();
    setPendingRequest(QDBusMessage(), QStringLiteral("displaypin"), device);
}

quint32 BluetoothAgent::RequestPasskey(const QDBusObjectPath& device) {
    qCInfo(lcBtAgent) << "RequestPasskey for" << device.path();
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    QDBusMessage msg;
    if (calledFromDBus()) {
        setDelayedReply(true);
        msg = message();
    }
    fetchDeviceInfo(device);
    m_passkey = 0;
    emit passkeyChanged();
    setPendingRequest(msg, QStringLiteral("passkey"), device);
    return 0;
}

void BluetoothAgent::DisplayPasskey(const QDBusObjectPath& device, quint32 passkey, quint16 entered) {
    qCInfo(lcBtAgent) << "DisplayPasskey for" << device.path() << ":" << passkey << "(" << entered << "entered)";

    if (m_requestActive && m_devicePath == device.path() && m_requestType == QStringLiteral("displaypasskey")) {
        if (m_passkey != passkey) {
            m_passkey = passkey;
            emit passkeyChanged();
        }
        if (m_passkeyEntered != entered) {
            m_passkeyEntered = entered;
            emit passkeyEnteredChanged();
        }
        if (m_timeoutTimer) m_timeoutTimer->start(60000);
        return;
    }

    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    fetchDeviceInfo(device);
    m_passkey = passkey;
    emit passkeyChanged();
    m_passkeyEntered = entered;
    emit passkeyEnteredChanged();
    setPendingRequest(QDBusMessage(), QStringLiteral("displaypasskey"), device);
}

void BluetoothAgent::RequestConfirmation(const QDBusObjectPath& device, quint32 passkey) {
    qCInfo(lcBtAgent) << "RequestConfirmation for" << device.path() << "passkey:" << passkey;
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    QDBusMessage msg;
    if (calledFromDBus()) {
        setDelayedReply(true);
        msg = message();
    }
    fetchDeviceInfo(device);
    m_passkey = passkey;
    emit passkeyChanged();
    setPendingRequest(msg, QStringLiteral("confirmation"), device);
}

void BluetoothAgent::RequestAuthorization(const QDBusObjectPath& device) {
    qCInfo(lcBtAgent) << "RequestAuthorization for" << device.path();
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    QDBusMessage msg;
    if (calledFromDBus()) {
        setDelayedReply(true);
        msg = message();
    }
    fetchDeviceInfo(device);
    setPendingRequest(msg, QStringLiteral("authorization"), device);
}

void BluetoothAgent::AuthorizeService(const QDBusObjectPath& device, const QString& uuid) {
    qCInfo(lcBtAgent) << "AuthorizeService for" << device.path() << "UUID:" << uuid;
    clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Canceled by new pairing request"));
    QDBusMessage msg;
    if (calledFromDBus()) {
        setDelayedReply(true);
        msg = message();
    }
    fetchDeviceInfo(device);
    setPendingRequest(msg, QStringLiteral("authorization"), device);
}

void BluetoothAgent::Cancel() {
    qCInfo(lcBtAgent) << "Pairing request canceled by remote device or BlueZ";
    if (m_timeoutTimer) m_timeoutTimer->stop();
    m_hasPendingMsg = false;
    m_pairingError = tr("Pairing canceled or timed out.");
    emit pairingErrorChanged();

    if (m_requestActive) {
        m_requestActive = false;
        emit requestActiveChanged();
    }
    emit pairingCanceled();
}

void BluetoothAgent::handleTimeout() {
    qCInfo(lcBtAgent) << "Pairing request timed out";
    if (m_requestActive || m_hasPendingMsg) {
        clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("Pairing request timed out"));
        m_pairingError = tr("Pairing request timed out.");
        emit pairingErrorChanged();
        emit pairingCanceled();
    }
}

void BluetoothAgent::onBluezServiceOwnerChanged(const QString& service, const QString& oldOwner, const QString& newOwner) {
    Q_UNUSED(service);
    Q_UNUSED(oldOwner);

    if (newOwner.isEmpty()) {
        qCInfo(lcBtAgent) << "BlueZ service stopped";
        clearPendingRequest(true, QStringLiteral("org.bluez.Error.Canceled"), QStringLiteral("BlueZ service stopped"));
        if (m_registered) {
            m_registered = false;
            emit registeredChanged();
        }
    } else {
        qCInfo(lcBtAgent) << "BlueZ service started/changed owner";
        if (m_wasRegistered) {
            registerAgent();
        }
    }
}

void BluetoothAgent::fetchDeviceInfo(const QDBusObjectPath& device) {
    m_devicePath = device.path();
    emit devicePathChanged();

    auto bus = QDBusConnection::systemBus();
    QDBusInterface devIf(
        QStringLiteral("org.bluez"),
        m_devicePath,
        QStringLiteral("org.bluez.Device1"),
        bus
    );

    if (devIf.isValid()) {
        QVariant nameVar = devIf.property("Alias");
        if (!nameVar.isValid() || nameVar.toString().isEmpty()) {
            nameVar = devIf.property("Name");
        }
        if (nameVar.isValid() && !nameVar.toString().isEmpty()) {
            m_deviceName = nameVar.toString();
        } else {
            m_deviceName = m_devicePath.section('/', -1);
        }

        m_deviceAddress = devIf.property("Address").toString();
        m_deviceIcon = devIf.property("Icon").toString();
        if (m_deviceIcon.isEmpty()) {
            m_deviceIcon = QStringLiteral("bluetooth");
        }
    } else {
        m_deviceName = m_devicePath.section('/', -1);
        m_deviceAddress.clear();
        m_deviceIcon = QStringLiteral("bluetooth");
    }

    emit deviceNameChanged();
    emit deviceAddressChanged();
    emit deviceIconChanged();
}

void BluetoothAgent::setPendingRequest(const QDBusMessage& msg, const QString& type, const QDBusObjectPath& device) {
    Q_UNUSED(device);

    m_pendingMsg = msg;
    m_hasPendingMsg = (msg.type() == QDBusMessage::MethodCallMessage);
    m_requestType = type;
    emit requestTypeChanged();

    clearError();

    m_requestActive = true;
    emit requestActiveChanged();

    if (m_timeoutTimer) m_timeoutTimer->start(60000);

    emit pairingRequested();
}

void BluetoothAgent::clearPendingRequest(bool sendError, const QString& errorName, const QString& errorMsg) {
    if (m_timeoutTimer) m_timeoutTimer->stop();

    if (m_hasPendingMsg) {
        if (sendError) {
            auto bus = QDBusConnection::systemBus();
            bus.send(m_pendingMsg.createErrorReply(errorName, errorMsg));
        }
        m_hasPendingMsg = false;
    }

    if (m_requestActive) {
        m_requestActive = false;
        emit requestActiveChanged();
    }
}

} // namespace caelestia::services
