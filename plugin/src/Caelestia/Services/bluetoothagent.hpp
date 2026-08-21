#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusContext>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusObjectPath>
#include <QtDBus/QDBusServiceWatcher>
#include <qqmlintegration.h>

namespace caelestia::services {

class BluetoothAgent : public QObject, public QDBusContext {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)
    Q_PROPERTY(bool requestActive READ requestActive NOTIFY requestActiveChanged)
    Q_PROPERTY(QString requestType READ requestType NOTIFY requestTypeChanged)
    Q_PROPERTY(QString devicePath READ devicePath NOTIFY devicePathChanged)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY deviceNameChanged)
    Q_PROPERTY(QString deviceAddress READ deviceAddress NOTIFY deviceAddressChanged)
    Q_PROPERTY(QString deviceIcon READ deviceIcon NOTIFY deviceIconChanged)
    Q_PROPERTY(QString pinCode READ pinCode NOTIFY pinCodeChanged)
    Q_PROPERTY(quint32 passkey READ passkey NOTIFY passkeyChanged)
    Q_PROPERTY(quint16 passkeyEntered READ passkeyEntered NOTIFY passkeyEnteredChanged)
    Q_PROPERTY(QString pairingError READ pairingError NOTIFY pairingErrorChanged)
    Q_PROPERTY(QString capability READ capability WRITE setCapability NOTIFY capabilityChanged)

public:
    explicit BluetoothAgent(QObject* parent = nullptr);
    ~BluetoothAgent() override;

    bool registered() const { return m_registered; }
    bool requestActive() const { return m_requestActive; }
    QString requestType() const { return m_requestType; }
    QString devicePath() const { return m_devicePath; }
    QString deviceName() const { return m_deviceName; }
    QString deviceAddress() const { return m_deviceAddress; }
    QString deviceIcon() const { return m_deviceIcon; }
    QString pinCode() const { return m_pinCode; }
    quint32 passkey() const { return m_passkey; }
    quint16 passkeyEntered() const { return m_passkeyEntered; }
    QString pairingError() const { return m_pairingError; }
    QString capability() const { return m_capability; }
    void setCapability(const QString& cap);

    Q_INVOKABLE void registerAgent();
    Q_INVOKABLE void unregisterAgent();
    Q_INVOKABLE void respondPinCode(const QString& pin);
    Q_INVOKABLE void respondPasskey(quint32 passkey);
    Q_INVOKABLE void respondConfirmation(bool accept);
    Q_INVOKABLE void respondAuthorization(bool accept);
    Q_INVOKABLE void cancelPairing();
    Q_INVOKABLE void clearError();

signals:
    void registeredChanged();
    void requestActiveChanged();
    void requestTypeChanged();
    void devicePathChanged();
    void deviceNameChanged();
    void deviceAddressChanged();
    void deviceIconChanged();
    void pinCodeChanged();
    void passkeyChanged();
    void passkeyEnteredChanged();
    void pairingErrorChanged();
    void capabilityChanged();
    void pairingRequested();
    void pairingCanceled();
    void pairingFinished();

public slots: // org.bluez.Agent1 interface slots
    void Release();
    QString RequestPinCode(const QDBusObjectPath& device);
    void DisplayPinCode(const QDBusObjectPath& device, const QString& pincode);
    quint32 RequestPasskey(const QDBusObjectPath& device);
    void DisplayPasskey(const QDBusObjectPath& device, quint32 passkey, quint16 entered);
    void RequestConfirmation(const QDBusObjectPath& device, quint32 passkey);
    void RequestAuthorization(const QDBusObjectPath& device);
    void AuthorizeService(const QDBusObjectPath& device, const QString& uuid);
    void Cancel();

private slots:
    void onBluezServiceOwnerChanged(const QString& service, const QString& oldOwner, const QString& newOwner);
    void checkAdapterStatus();

private:
    void fetchDeviceInfo(const QDBusObjectPath& device);
    void setPendingRequest(const QDBusMessage& msg, const QString& type, const QDBusObjectPath& device);
    void clearPendingRequest(bool sendError = false, const QString& errorName = QString(), const QString& errorMsg = QString());

    bool m_registered = false;
    bool m_requestActive = false;
    QString m_requestType;
    QString m_devicePath;
    QString m_deviceName;
    QString m_deviceAddress;
    QString m_deviceIcon;
    QString m_pinCode;
    quint32 m_passkey = 0;
    quint16 m_passkeyEntered = 0;
    QString m_pairingError;
    QString m_capability = QStringLiteral("KeyboardDisplay");

    QDBusMessage m_pendingMsg;
    bool m_hasPendingMsg = false;
    QDBusServiceWatcher* m_serviceWatcher = nullptr;
};

} // namespace caelestia::services
