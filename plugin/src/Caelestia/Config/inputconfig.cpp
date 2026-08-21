#include "inputconfig.hpp"

#include <qdir.h>
#include <qfile.h>
#include <qfileinfo.h>
#include <qlocalsocket.h>
#include <qloggingcategory.h>
#include <qstandardpaths.h>
#include <qtextstream.h>

namespace caelestia::config {

InputConfig::InputConfig(QObject* parent)
    : ConfigObject(parent) {
    connect(this, &ConfigObject::propertiesChanged, this, [this] {
        applyInputSettings();
    });
}

void InputConfig::applyInputSettings() {
    syncVariablesFile();
    dispatchCompositorIpc();
}

void InputConfig::syncVariablesFile() {
    QString configDir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/caelestia/");
    QDir().mkpath(configDir);
    QString varsFilePath = configDir + QStringLiteral("hypr-vars.conf");

    QFile file(varsFilePath);
    QStringList lines;
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        while (!in.atEnd()) {
            lines.append(in.readLine());
        }
        file.close();
    }

    struct VarDef {
        QString name;
        QString value;
        bool found = false;
    };

    QList<VarDef> vars = {
        { QStringLiteral("$pointerSensitivity"), QString::number(pointerSpeed()) },
        { QStringLiteral("$touchpadTapToClick"), touchpadTapToClick() ? QStringLiteral("true") : QStringLiteral("false") },
        { QStringLiteral("$touchpadNaturalScroll"), touchpadNaturalScroll() ? QStringLiteral("true") : QStringLiteral("false") },
        { QStringLiteral("$kbRepeatRate"), QString::number(keyboardRepeatRate()) },
        { QStringLiteral("$kbRepeatDelay"), QString::number(keyboardRepeatDelay()) }
    };

    for (int i = 0; i < lines.size(); ++i) {
        QString trimmed = lines[i].trimmed();
        for (auto& var : vars) {
            if (trimmed.startsWith(var.name + QStringLiteral(" ")) ||
                trimmed.startsWith(var.name + QStringLiteral("="))) {
                lines[i] = var.name + QStringLiteral(" = ") + var.value;
                var.found = true;
                break;
            }
        }
    }

    for (const auto& var : vars) {
        if (!var.found) {
            lines.append(var.name + QStringLiteral(" = ") + var.value);
        }
    }

    if (file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        QTextStream out(&file);
        for (const auto& line : lines) {
            out << line << "\n";
        }
        file.close();
    }
}

void InputConfig::dispatchCompositorIpc() {
    const auto his = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    if (his.isEmpty()) {
        return;
    }

    auto hyprDir = QString("%1/hypr/%2").arg(qEnvironmentVariable("XDG_RUNTIME_DIR"), his);
    if (!QDir(hyprDir).exists()) {
        hyprDir = QStringLiteral("/tmp/hypr/") + his;
        if (!QDir(hyprDir).exists()) {
            return;
        }
    }

    QString socketPath = hyprDir + QStringLiteral("/.socket.sock");
    QLocalSocket socket;
    socket.connectToServer(socketPath);
    if (socket.waitForConnected(100)) {
        QString payload = QStringLiteral("[[BATCH]]keyword input:sensitivity %1;"
                                         "keyword input:touchpad:tap-to-click %2;"
                                         "keyword input:touchpad:natural_scroll %3;"
                                         "keyword input:repeat_rate %4;"
                                         "keyword input:repeat_delay %5")
                              .arg(pointerSpeed())
                              .arg(touchpadTapToClick() ? 1 : 0)
                              .arg(touchpadNaturalScroll() ? 1 : 0)
                              .arg(keyboardRepeatRate())
                              .arg(keyboardRepeatDelay());
        socket.write(payload.toUtf8());
        socket.flush();
        socket.waitForBytesWritten(100);
        socket.close();
    }
}

} // namespace caelestia::config
