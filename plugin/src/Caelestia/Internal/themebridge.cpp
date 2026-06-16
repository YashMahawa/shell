#include "themebridge.hpp"
#include <QFile>
#include <QFileInfo>
#include <QDebug>

namespace caelestia {

bool ThemeBridge::exportGreeterTheme(const QString& sourcePath) {
    QString dest = "/var/tmp/caelestia-greeter-theme.json";
    
    // Check if it exists
    if (QFile::exists(dest)) {
        // Try to remove it
        if (!QFile::remove(dest)) {
            qWarning() << "ThemeBridge: Cannot remove existing greeter theme (permission denied?). Theme export failed.";
            return false;
        }
    }
    
    if (QFile::copy(sourcePath, dest)) {
        QFile::setPermissions(dest, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ReadGroup | QFileDevice::ReadOther);
        return true;
    }
    
    qWarning() << "ThemeBridge: Failed to copy theme to" << dest;
    return false;
}

} // namespace caelestia
