pragma Singleton
import QtQuick
import Caelestia.Services

QtObject {
    id: root
    property bool enabled: true
    property bool active: false
    property bool autoDetect: false
    
    // Globally accessible property to control expensive effects based on lite mode
    property real blurMultiplier: active ? 0.0 : 1.0
    property bool effectsEnabled: !active

    property QtObject _cpuRef: null
    property QtObject _memRef: null

    onAutoDetectChanged: {
        if (autoDetect) {
            _cpuRef = Qt.createQmlObject('import Caelestia.Services; ServiceRef { service: Cpu }', root);
            _memRef = Qt.createQmlObject('import Caelestia.Services; ServiceRef { service: Memory }', root);
        } else {
            if (_cpuRef) {
                _cpuRef.destroy();
                _cpuRef = null;
            }
            if (_memRef) {
                _memRef.destroy();
                _memRef = null;
            }
        }
    }

    property Connections _cpuConn: Connections {
        target: autoDetect ? Cpu : null
        function onPercentageChanged() {
            if (autoDetect) evaluateConstraints(Cpu.percentage, Memory.percentage);
        }
    }
    
    property Connections _memConn: Connections {
        target: autoDetect ? Memory : null
        function onChanged() {
            if (autoDetect) evaluateConstraints(Cpu.percentage, Memory.percentage);
        }
    }

    // Automatically disables high-GPU blur and glassmorphism effects when system resources are constrained
    function evaluateConstraints(cpuUsage, memUsage) {
        if (!enabled) {
            active = false;
            return;
        }
        
        // Thresholds for auto-enabling lite mode
        if (cpuUsage > 85.0 || memUsage > 80.0) {
            if (!active) {
                console.log("TrueLite: High resource usage detected. Enabling lite mode.");
                active = true;
            }
        } else if (cpuUsage < 50.0 && memUsage < 50.0) {
            if (active) {
                console.log("TrueLite: Resources stable. Disabling lite mode.");
                active = false;
            }
        }
    }
    
    function toggle() {
        enabled = !enabled;
        console.log("TrueLite: Toggled. Enabled:", enabled);
        if (!enabled) active = false;
    }
}
