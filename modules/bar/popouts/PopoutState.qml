import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    // Click-opened panels stay until Escape / click-away (not hover leave).
    property bool sticky

    signal detachRequested(mode: string)
}
