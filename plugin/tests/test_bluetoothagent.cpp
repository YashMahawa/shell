#include <QSignalSpy>
#include <QTest>
#include "Services/bluetoothagent.hpp"

using namespace caelestia::services;

class TestBluetoothAgent : public QObject {
    Q_OBJECT

private slots:
    void testInitialState();
    void testCapabilityChange();
    void testRequestPinCode();
    void testRequestPasskey();
    void testRequestConfirmation();
    void testRequestAuthorization();
    void testSingleActiveRequest();
    void testCancelByRemote();
    void testUserCancel();
    void testRelease();
};

void TestBluetoothAgent::testInitialState() {
    BluetoothAgent agent;
    QCOMPARE(agent.registered(), false);
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(agent.capability(), QString("KeyboardDisplay"));
    QVERIFY(agent.pairingError().isEmpty());
}

void TestBluetoothAgent::testCapabilityChange() {
    BluetoothAgent agent;
    QSignalSpy spy(&agent, &BluetoothAgent::capabilityChanged);
    agent.setCapability("DisplayYesNo");
    QCOMPARE(agent.capability(), QString("DisplayYesNo"));
    QCOMPARE(spy.count(), 1);
}

void TestBluetoothAgent::testRequestPinCode() {
    BluetoothAgent agent;
    QSignalSpy reqSpy(&agent, &BluetoothAgent::pairingRequested);
    QSignalSpy finSpy(&agent, &BluetoothAgent::pairingFinished);

    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestPinCode(devPath);

    QCOMPARE(agent.requestActive(), true);
    QCOMPARE(agent.requestType(), QString("pincode"));
    QCOMPARE(agent.devicePath(), devPath.path());
    QCOMPARE(reqSpy.count(), 1);

    agent.respondPinCode("123456");
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(finSpy.count(), 1);
}

void TestBluetoothAgent::testRequestPasskey() {
    BluetoothAgent agent;
    QSignalSpy reqSpy(&agent, &BluetoothAgent::pairingRequested);
    QSignalSpy finSpy(&agent, &BluetoothAgent::pairingFinished);

    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestPasskey(devPath);

    QCOMPARE(agent.requestActive(), true);
    QCOMPARE(agent.requestType(), QString("passkey"));
    QCOMPARE(reqSpy.count(), 1);

    agent.respondPasskey(654321);
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(finSpy.count(), 1);
}

void TestBluetoothAgent::testRequestConfirmation() {
    BluetoothAgent agent;
    QSignalSpy reqSpy(&agent, &BluetoothAgent::pairingRequested);
    QSignalSpy finSpy(&agent, &BluetoothAgent::pairingFinished);

    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestConfirmation(devPath, 987654);

    QCOMPARE(agent.requestActive(), true);
    QCOMPARE(agent.requestType(), QString("confirmation"));
    QCOMPARE(agent.passkey(), static_cast<quint32>(987654));
    QCOMPARE(reqSpy.count(), 1);

    agent.respondConfirmation(true);
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(finSpy.count(), 1);
}

void TestBluetoothAgent::testRequestAuthorization() {
    BluetoothAgent agent;
    QSignalSpy reqSpy(&agent, &BluetoothAgent::pairingRequested);
    QSignalSpy finSpy(&agent, &BluetoothAgent::pairingFinished);

    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestAuthorization(devPath);

    QCOMPARE(agent.requestActive(), true);
    QCOMPARE(agent.requestType(), QString("authorization"));
    QCOMPARE(reqSpy.count(), 1);

    agent.respondAuthorization(true);
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(finSpy.count(), 1);
}

void TestBluetoothAgent::testSingleActiveRequest() {
    BluetoothAgent agent;

    QDBusObjectPath devPath1("/org/bluez/hci0/dev_11_11_11_11_11_11");
    agent.RequestConfirmation(devPath1, 111111);
    QCOMPARE(agent.devicePath(), devPath1.path());
    QCOMPARE(agent.requestType(), QString("confirmation"));

    // Calling a new request should cancel the previous one and replace it
    QDBusObjectPath devPath2("/org/bluez/hci0/dev_22_22_22_22_22_22");
    agent.RequestPasskey(devPath2);
    QCOMPARE(agent.requestActive(), true);
    QCOMPARE(agent.devicePath(), devPath2.path());
    QCOMPARE(agent.requestType(), QString("passkey"));
}

void TestBluetoothAgent::testCancelByRemote() {
    BluetoothAgent agent;
    QSignalSpy cancelSpy(&agent, &BluetoothAgent::pairingCanceled);

    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestConfirmation(devPath, 123456);
    QCOMPARE(agent.requestActive(), true);

    agent.Cancel();
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(cancelSpy.count(), 1);
    QVERIFY(!agent.pairingError().isEmpty());
}

void TestBluetoothAgent::testUserCancel() {
    BluetoothAgent agent;
    QSignalSpy cancelSpy(&agent, &BluetoothAgent::pairingCanceled);

    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestConfirmation(devPath, 123456);
    QCOMPARE(agent.requestActive(), true);

    agent.cancelPairing();
    QCOMPARE(agent.requestActive(), false);
    QCOMPARE(cancelSpy.count(), 1);
}

void TestBluetoothAgent::testRelease() {
    BluetoothAgent agent;
    QDBusObjectPath devPath("/org/bluez/hci0/dev_11_22_33_44_55_66");
    agent.RequestConfirmation(devPath, 123456);
    QCOMPARE(agent.requestActive(), true);

    agent.Release();
    QCOMPARE(agent.registered(), false);
    QCOMPARE(agent.requestActive(), false);
}

QTEST_MAIN(TestBluetoothAgent)
#include "test_bluetoothagent.moc"
