pragma Singleton

import Quickshell

Singleton {
    // Armed only during native drags so ordinary application clicks pass through.
    property bool active: false
}
