#include <QSignalSpy>
#include <QTest>
#include <QGuiApplication>
#include <QClipboard>
#include <QTimer>

#include "../src/Caelestia/Services/voiceservice.hpp"

using namespace caelestia::services;

class TestVoiceService : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        QVERIFY(QGuiApplication::clipboard() != nullptr);
    }

    void testInitialState() {
        VoiceService service;
        QCOMPARE(service.status(), QString("idle"));
        QCOMPARE(service.active(), false);
        QCOMPARE(service.message(), QString());
        QCOMPARE(service.detail(), QString());
        QCOMPARE(service.model(), QString("gemini-3.1-flash-lite"));
        QVERIFY(!service.prompt().isEmpty());
    }

    void testStartStopCapture() {
        VoiceService service;
        QSignalSpy statusSpy(&service, &VoiceService::statusChanged);
        QSignalSpy activeSpy(&service, &VoiceService::activeChanged);

        service.startCapture();
        QCOMPARE(service.status(), QString("listening"));
        QCOMPARE(service.active(), true);
        QCOMPARE(statusSpy.count(), 1);
        QCOMPARE(activeSpy.count(), 1);

        service.stopCapture();
        QVERIFY(service.status() == "empty" || service.status() == "processing" || service.status() == "error");
    }

    void testCancellation() {
        VoiceService service;
        service.startCapture();
        QCOMPARE(service.status(), QString("listening"));
        QCOMPARE(service.active(), true);

        service.cancel();
        QCOMPARE(service.status(), QString("idle"));
        QCOMPARE(service.active(), false);
        QCOMPARE(service.message(), QString(""));
        QCOMPARE(service.detail(), QString(""));
    }

    void testTimeout() {
        VoiceService service;
        service.startCapture();
        QCOMPARE(service.status(), QString("listening"));

        service.stopCapture();
        QVERIFY(service.status() != "listening");
    }

    void testRestart() {
        VoiceService service;

        // Cycle 1
        service.startCapture();
        QCOMPARE(service.status(), QString("listening"));
        service.cancel();
        QCOMPARE(service.status(), QString("idle"));

        // Cycle 2 (Restart)
        service.startCapture();
        QCOMPARE(service.status(), QString("listening"));
        service.stopCapture();
        QVERIFY(service.status() != "listening");

        // Cycle 3 (Restart again)
        service.startCapture();
        QCOMPARE(service.status(), QString("listening"));
        service.cancel();
        QCOMPARE(service.status(), QString("idle"));
    }

    void testClipboardAndPaste() {
        VoiceService service;
        QClipboard* cb = QGuiApplication::clipboard();
        QVERIFY(cb != nullptr);

        const QString testText = "Unit test clipboard text 12345";
        cb->setText(testText);
        QCOMPARE(cb->text(), testText);
    }

    void testKeysAndPromptManagement() {
        VoiceService service;
        QSignalSpy promptSpy(&service, &VoiceService::promptChanged);

        const QString newPrompt = "This is a custom prompt for transcription testing that is long enough.";
        service.savePrompt(newPrompt);
        QCOMPARE(service.prompt(), newPrompt);
        QCOMPARE(promptSpy.count(), 1);

        QSignalSpy keysSpy(&service, &VoiceService::storedKeysChanged);
        service.refreshKeys();
        QCOMPARE(service.storedKeys().size(), 3);
    }
};

QTEST_MAIN(TestVoiceService)
#include "test_voiceservice.moc"
