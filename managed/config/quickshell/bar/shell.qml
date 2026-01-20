import QtQml
import QtQuick
import Quickshell

ShellRoot {
    LoggingCategory {
        defaultLogLevel: LoggingCategory.Critical
        name: "quickshell.dbus.properties"
    }

    // Temporarily disable the bar; no windows will be created.
}
