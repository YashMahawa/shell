pragma Singleton
import QtQuick
QtObject {
    id: root
    property bool enabled: true
    // Automatically disables high-GPU blur and glassmorphism effects when system resources are constrained
}
