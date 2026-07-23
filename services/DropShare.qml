pragma Singleton

import Quickshell

Singleton {
    // True for the whole drag gesture (hold/move/release), even while still
    // over the clipboard panel. Prevents hover-dismiss from destroying the
    // drag source mid-gesture.
    property bool session: false

    // True only after the pointer has left the clipboard panel bounds.
    // That is when we free layershell focus/mask so other apps can receive
    // the drop. Setting this on hold was crashing Qt (mask rebuild under
    // an active DragHandler).
    property bool active: false

    function beginSession(): void {
        session = true;
        active = false;
    }

    function leavePanel(): void {
        if (session)
            active = true;
    }

    function reenterPanel(): void {
        // Optional: keep active once left so mask thrashing doesn't crash.
        // Intentionally no-op — once outside, stay free for drop targets.
    }

    function end(): void {
        session = false;
        active = false;
    }
}
