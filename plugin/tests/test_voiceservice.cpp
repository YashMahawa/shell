#include <QtTest>
#include "Services/voiceservice.hpp"

using namespace caelestia::services;

class TestVoiceService : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        qRegisterMetaType<VoiceService*>();
    }

    void testInitialState() {
        VoiceService voice;
        QCOMPARE(voice.status(), QString("idle"));
        QCOMPARE(voice.message(), QString(""));
        QCOMPARE(voice.detail(), QString(""));
        QCOMPARE(voice.active(), false);
        QCOMPARE(voice.storedKeys().size(), 3);
    }

    void testCancelStateReset() {
        VoiceService voice;
        voice.startCapture();
        QCOMPARE(voice.status(), QString("listening"));
        QCOMPARE(voice.active(), true);

        voice.cancel();
        QCOMPARE(voice.status(), QString("idle"));
        QCOMPARE(voice.active(), false);
        QCOMPARE(voice.message(), QString(""));
        QCOMPARE(voice.detail(), QString(""));
    }

    void testStatusInfoFormat() {
        VoiceService voice;
        QVariantMap info = voice.statusInfo();
        QCOMPARE(info.value("status").toString(), QString("idle"));
        QVERIFY(info.contains("keys"));
        QVERIFY(info.contains("prompt"));
        QVERIFY(info.contains("model"));
    }
};

QTEST_MAIN(TestVoiceService)
#include "test_voiceservice.moc"
