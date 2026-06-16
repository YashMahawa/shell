pragma Singleton
import QtQuick
import Caelestia.Services

QtObject {
    id: root
    property bool enabled: true
    property bool active: false
    
    // Globally accessible property to control expensive effects based on lite mode
    property real blurMultiplier: active ? 0.0 : 1.0
    property bool effectsEnabled: !active

    Connections {
        target: Cpu
        function onPercentageChanged() {
            evaluateConstraints(Cpu.percentage, Memory.percentage);
        }
    }
    
    Connections {
        target: Memory
        function onChanged() {
            evaluateConstraints(Cpu.percentage, Memory.percentage);
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
