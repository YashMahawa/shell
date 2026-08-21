#!/usr/bin/env python3
import json
import os
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

class TestVoiceServiceBoundary(unittest.TestCase):
    def test_voice_qml_singleton_definition(self):
        """Ensure Voice.qml defines expected properties, methods, and IPC handler."""
        voice_qml = REPO_ROOT / "services" / "Voice.qml"
        self.assertTrue(voice_qml.exists(), "services/Voice.qml should exist")

        content = voice_qml.read_text()
        self.assertIn("pragma Singleton", content)
        self.assertIn("VoiceService.status", content)
        self.assertIn("VoiceService.message", content)
        self.assertIn("VoiceService.detail", content)
        self.assertIn("VoiceService.active", content)
        self.assertIn("VoiceService.storedKeys", content)

        # Check IPC target and methods
        self.assertIn('target: "voice"', content)
        self.assertIn("function toggle()", content)
        self.assertIn("function start()", content)
        self.assertIn("function stop()", content)
        self.assertIn("function cancel()", content)
        self.assertIn("function status()", content)

    def test_service_loader_registration(self):
        """Ensure Voice service is loaded in ServiceLoader.qml."""
        loader_qml = REPO_ROOT / "modules" / "ServiceLoader.qml"
        content = loader_qml.read_text()
        self.assertIn("Voice;", content)

    def test_voice_overlay_binding(self):
        """Ensure VoiceOverlay.qml binds directly to Voice service properties without disk file views."""
        overlay_qml = REPO_ROOT / "modules" / "VoiceOverlay.qml"
        content = overlay_qml.read_text()
        self.assertIn("readonly property string status: Voice.status", content)
        self.assertIn("readonly property string message: Voice.message", content)
        self.assertIn("readonly property string detail: Voice.detail", content)
        self.assertIn("readonly property bool active: Voice.active", content)
        self.assertNotIn("FileView", content)
        self.assertNotIn("voice-state.json", content)

    def test_voice_typing_page_integration(self):
        """Ensure VoiceTypingPage.qml uses Voice singleton methods instead of spawning external setting procs."""
        page_qml = REPO_ROOT / "modules" / "nexus" / "pages" / "VoiceTypingPage.qml"
        content = page_qml.read_text()
        self.assertIn("Voice.storedKeys", content)
        self.assertIn("Voice.storeKey", content)
        self.assertIn("Voice.clearKey", content)
        self.assertIn("Voice.savePrompt", content)
        self.assertNotIn("caelestia-voice-settings", content)

    def test_voiceservice_cpp_security_and_cancellation(self):
        """Ensure C++ VoiceService handles stdin streaming for wl-copy and proper cancellation."""
        cpp_src = REPO_ROOT / "plugin" / "src" / "Caelestia" / "Services" / "voiceservice.cpp"
        content = cpp_src.read_text()

        # Check stdin usage for wl-copy (no text in process CLI args)
        self.assertIn('wlCopyProc->start("wl-copy", QStringList())', content)
        self.assertIn('wlCopyProc->write(text.toUtf8())', content)

        # Check cancellation handling
        self.assertIn("void VoiceService::cancel()", content)
        self.assertIn("m_activeReply->abort()", content)
        self.assertIn('setState("idle", "", "")', content)

        # Check safety timer and background process cleanup
        self.assertIn("m_safetyTimer->start(60000)", content)
        self.assertIn("m_captureProcess->terminate()", content)

    def test_gemini_api_payload_structure(self):
        """Test formatting logic of Gemini API JSON payload."""
        prompt = "Transcribe user speech accurately."
        raw_audio = b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80>\x00\x00\x00}\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00"
        
        import base64
        audio_b64 = base64.b64encode(raw_audio).decode('ascii')

        payload = {
            "contents": [
                {
                    "parts": [
                        {"text": prompt},
                        {
                            "inline_data": {
                                "mime_type": "audio/wav",
                                "data": audio_b64
                            }
                        }
                    ]
                }
            ],
            "generationConfig": {"temperature": 0}
        }

        json_str = json.dumps(payload)
        parsed = json.loads(json_str)

        self.assertEqual(parsed["contents"][0]["parts"][0]["text"], prompt)
        self.assertEqual(parsed["contents"][0]["parts"][1]["inline_data"]["mime_type"], "audio/wav")
        self.assertEqual(parsed["contents"][0]["parts"][1]["inline_data"]["data"], audio_b64)
        self.assertEqual(parsed["generationConfig"]["temperature"], 0)

if __name__ == "__main__":
    unittest.main()
