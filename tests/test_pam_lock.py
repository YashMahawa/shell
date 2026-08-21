#!/usr/bin/env python3
import re
import unittest

# Python representation of the regex/parsing logic in Pam.qml parsePamMessage
def parse_pam_message(msg):
    if not msg:
        return None

    clean = re.sub(r"^pam_\w+\([^)]+\):\s*", "", msg, flags=re.IGNORECASE).strip()

    lockout_match = re.search(
        r"(\d+)\s*(?:seconds|sec|sekunden|secondes|segundos|s)\s*(?:left|remaining|verbleibend|restantes)?\s*(?:to unlock)?",
        clean,
        re.IGNORECASE,
    ) or re.search(
        r"(\d+)\s*(?:seconds|sec|sekunden|secondes|segundos|s)?\s*(?:left|remaining|verbleibend|restantes)\s*(?:to unlock)?",
        clean,
        re.IGNORECASE,
    ) or re.search(
        r"(?:locked|gesperrt|verrouillé|bloqueado)\s*(?:for|für|pendant|por)?\s*(\d+)\s*(?:seconds|sec|sekunden|secondes|segundos|s)?",
        clean,
        re.IGNORECASE,
    )
    if lockout_match and lockout_match.group(1):
        secs = lockout_match.group(1)
        text = f"Account locked ({secs}s remaining)"
        return {"type": "lockout", "text": text, "seconds": int(secs), "raw": clean}

    if re.search(r"account is locked|account locked|kontosperre|compte verrouillé|cuenta bloqueada", clean, re.IGNORECASE):
        text = "Account locked due to failed attempts."
        return {"type": "lockout", "text": text, "seconds": None, "raw": clean}

    attempts_match = re.search(
        r"(\d+)\s*(?:more\s+)?attempts?\s*(?:remaining|left)",
        clean,
        re.IGNORECASE,
    ) or re.search(
        r"(\d+)\s*failed login attempts?",
        clean,
        re.IGNORECASE,
    ) or re.search(
        r"(\d+)\s*(?:verbleibende|restant|restantes)\s*(?:versuche|essais|intentos)",
        clean,
        re.IGNORECASE,
    )
    if attempts_match and attempts_match.group(1):
        count = int(attempts_match.group(1))
        plural = "" if count == 1 else "s"
        text = f"Incorrect password ({count} attempt{plural} remaining)"
        return {"type": "attempts", "text": text, "count": count, "raw": clean}

    if re.search(r"authentication (?:failure|failed)|invalid password|incorrect password|password incorrect|falsches passwort|mot de passe incorrect|contraseña incorrecta", clean, re.IGNORECASE):
        return {"type": "invalid_creds", "text": "Incorrect password. Please try again.", "raw": clean}

    sanitized = re.sub(r"[\r\n]+", " ", clean)
    if len(sanitized) > 80:
        sanitized = sanitized[:77] + "..."
    return {"type": "info", "text": sanitized, "raw": clean}


class MockLockConfig:
    def __init__(self, enable_fprint=True, max_fprint_tries=3, max_fprint_errors=2):
        self.enableFprint = enable_fprint
        self.maxFprintTries = max_fprint_tries
        self.maxFprintErrors = max_fprint_errors


class MockTimer:
    def __init__(self):
        self.running = False

    def start(self):
        self.running = True

    def stop(self):
        self.running = False

    def restart(self):
        self.running = True


class MockPamContext:
    def __init__(self):
        self.active = False
        self.message = ""
        self.available = True
        self.tries = 0
        self.errorTries = 0

    def abort(self):
        self.active = False

    def start(self):
        self.active = True


class MockPamState:
    def __init__(self, config=None):
        self.config = config or MockLockConfig()
        self.lockMessage = ""
        self.classifiedMessage = None
        self.state = ""
        self.fprintState = ""
        self.buffer = ""
        self.unlocked = False

        self.passwd = MockPamContext()
        self.fprint = MockPamContext()

        self.errorRetry = MockTimer()
        self.stateReset = MockTimer()
        self.fprintStateReset = MockTimer()

    def handle_passwd_message(self, message):
        if message:
            parsed = parse_pam_message(message)
            self.classifiedMessage = parsed

            text_to_use = parsed["text"] if (parsed and parsed["type"] in ("lockout", "attempts")) else message
            if not self.lockMessage:
                self.lockMessage = text_to_use
            elif text_to_use not in self.lockMessage and message not in self.lockMessage:
                self.lockMessage += "\n" + text_to_use

    def handle_passwd_completed(self, pam_result, msg=""):
        self.passwd.message = msg
        if pam_result == "Success":
            return self.finishUnlock()

        parsed = parse_pam_message(msg)
        if parsed:
            self.classifiedMessage = parsed

        if pam_result == "Error":
            self.state = "error"
        elif pam_result == "MaxTries":
            self.state = "max"
        elif pam_result == "Failed":
            self.state = "fail"

        self.stateReset.restart()

    def handle_fprint_completed(self, pam_result):
        if not self.fprint.available:
            return

        if pam_result == "Success":
            return self.finishUnlock()

        if pam_result == "Error":
            self.fprint.errorTries += 1
            if self.fprint.errorTries < self.config.maxFprintErrors:
                self.fprintState = "error"
                self.fprint.abort()
                self.errorRetry.restart()
            else:
                self.fprintState = "error_max"
                self.fprint.abort()
                self.errorRetry.stop()
        elif pam_result in ("MaxTries", "Failed"):
            self.fprint.tries += 1
            if self.fprint.tries < self.config.maxFprintTries:
                self.fprintState = "fail"
                self.fprint.start()
            else:
                self.fprintState = "max"
                self.fprint.abort()

        self.fprintStateReset.start()

    def finishUnlock(self):
        self.fprint.abort()
        self.passwd.abort()
        self.errorRetry.stop()
        self.stateReset.stop()
        self.fprintStateReset.stop()
        self.unlocked = True

    def check_fprint_avail(self):
        if not self.fprint.available or not self.config.enableFprint:
            self.fprint.abort()
            return
        self.fprint.tries = 0
        self.fprint.errorTries = 0
        self.fprint.start()

    def secure_changed(self, secure):
        if secure:
            self.buffer = ""
            self.state = ""
            self.fprintState = ""
            self.lockMessage = ""
            self.classifiedMessage = None
            self.fprint.tries = 0
            self.fprint.errorTries = 0
            self.check_fprint_avail()
        else:
            self.fprint.abort()
            self.errorRetry.stop()
            self.stateReset.stop()
            self.fprintStateReset.stop()

    def get_display_message(self):
        if self.lockMessage:
            return self.lockMessage
        if self.classifiedMessage and self.classifiedMessage.get("text") and self.state in ("error", "fail", "max"):
            return self.classifiedMessage["text"]
        if self.fprintState == "error_max" or (self.fprintState == "error" and self.fprint.errorTries >= self.config.maxFprintErrors):
            return f"Fingerprint reader error ({self.fprint.errorTries}/{self.config.maxFprintErrors}). Please use password."
        if self.fprintState == "error":
            return f"Fingerprint reader error ({self.fprint.errorTries}/{self.config.maxFprintErrors}). Please try again."
        if self.state == "max" and self.fprintState in ("max", "error_max"):
            return "Maximum password and fingerprint attempts reached."
        if self.state == "max":
            if self.fprint.available and self.fprintState not in ("error_max", "max"):
                return "Maximum password attempts reached. Please use fingerprint."
            return "Maximum password attempts reached."
        if self.fprintState == "max":
            return "Maximum fingerprint attempts reached. Please use password."
        if self.state in ("fail", "error"):
            if self.fprint.available and self.fprintState not in ("error_max", "max"):
                return "Incorrect password. Please try again or use fingerprint."
            return "Incorrect password. Please try again."
        if self.fprintState == "fail":
            return f"Fingerprint not recognized ({self.fprint.tries}/{self.config.maxFprintTries}). Please try again or use password."
        return ""


class TestPamLockScreen(unittest.TestCase):

    def test_non_english_and_custom_pam_text(self):
        """Test non-English and custom PAM messages are preserved and result codes drive auth state."""
        pam = MockPamState()

        # German invalid password
        pam.handle_passwd_message("pam_unix(passwd:auth): Falsches Passwort")
        pam.handle_passwd_completed("Failed", "Falsches Passwort")
        self.assertEqual(pam.state, "fail")
        self.assertIn("Falsches Passwort", pam.classifiedMessage["raw"])

        # Custom module text
        pam_custom = MockPamState()
        pam_custom.handle_passwd_message("pam_custom_sec: Security module denied token 0x99")
        pam_custom.handle_passwd_completed("Error", "Security module denied token 0x99")
        self.assertEqual(pam_custom.state, "error")

        # Display falls back cleanly
        msg = pam_custom.get_display_message()
        self.assertTrue(len(msg) > 0)

    def test_split_multipart_messages(self):
        """Test multipart lockout messages accumulate line by line rather than overwriting."""
        pam = MockPamState()

        # Split lockout in English
        pam.handle_passwd_message("The account is locked due to 3 failed attempts.")
        pam.handle_passwd_message("(60 seconds left to unlock)")
        self.assertIn("\n", pam.lockMessage)
        self.assertIn("60s remaining", pam.lockMessage)

        # Split message in German
        pam_de = MockPamState()
        pam_de.handle_passwd_message("Der Account ist gesperrt.")
        pam_de.handle_passwd_message("(60 Sekunden verbleiben)")
        self.assertIn("\n", pam_de.lockMessage)
        self.assertTrue(len(pam_de.lockMessage.splitlines()) == 2)

    def test_unavailable_reader(self):
        """Test fingerprint reader unavailability falls back to password-only mode."""
        pam = MockPamState()
        pam.fprint.available = False
        pam.check_fprint_avail()

        self.assertFalse(pam.fprint.active)

        # Password error should not mention fingerprint when unavailable
        pam.handle_passwd_completed("Failed", "Invalid password")
        self.assertEqual(pam.get_display_message(), "Incorrect password. Please try again.")

    def test_cancellation(self):
        """Test cancellation stops active operations and clears state."""
        pam = MockPamState()
        pam.fprint.start()
        pam.buffer = "secret"
        pam.state = "fail"

        # Cancel session
        pam.secure_changed(False)

        self.assertFalse(pam.fprint.active)
        self.assertFalse(pam.errorRetry.running)
        self.assertFalse(pam.stateReset.running)

    def test_concurrent_password_fingerprint_success(self):
        """Test concurrent password/fingerprint authentication success cleans up active tasks."""
        pam = MockPamState()
        pam.passwd.start()
        pam.fprint.start()

        # Fingerprint succeeds first
        pam.handle_fprint_completed("Success")

        self.assertTrue(pam.unlocked)
        self.assertFalse(pam.fprint.active)
        self.assertFalse(pam.passwd.active)

    def test_lock_unlock_cycles(self):
        """Test lock/unlock cycles reset attempts, messages, and state buffers."""
        pam = MockPamState()
        pam.buffer = "1234"
        pam.fprint.tries = 2
        pam.fprint.errorTries = 1
        pam.lockMessage = "Previous lockout message"

        # Unlock
        pam.finishUnlock()
        self.assertTrue(pam.unlocked)

        # Lock again
        pam.unlocked = False
        pam.secure_changed(True)

        self.assertEqual(pam.buffer, "")
        self.assertEqual(pam.fprint.tries, 0)
        self.assertEqual(pam.fprint.errorTries, 0)
        self.assertEqual(pam.lockMessage, "")
        self.assertEqual(pam.state, "")

    def test_configurable_biometric_retry_policy(self):
        """Test biometric retry policy uses maxFprintErrors configuration."""
        config = MockLockConfig(max_fprint_errors=4, max_fprint_tries=5)
        pam = MockPamState(config=config)
        pam.check_fprint_avail()

        # Error 1
        pam.handle_fprint_completed("Error")
        self.assertEqual(pam.fprintState, "error")
        self.assertTrue(pam.errorRetry.running)

        # Error 2
        pam.handle_fprint_completed("Error")
        self.assertEqual(pam.fprintState, "error")
        self.assertTrue(pam.errorRetry.running)

        # Error 3
        pam.handle_fprint_completed("Error")
        self.assertEqual(pam.fprintState, "error")

        # Error 4 (max reached)
        pam.handle_fprint_completed("Error")
        self.assertEqual(pam.fprintState, "error_max")
        self.assertFalse(pam.errorRetry.running)


if __name__ == "__main__":
    unittest.main()
