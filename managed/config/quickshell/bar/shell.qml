import "."
import QtQml
import QtQuick
import Quickshell

ShellRoot {
    LoggingCategory {
        name: "quickshell.dbus.properties"
        defaultLogLevel: LoggingCategory.Critical
    }

    Variants {
        model: Quickshell.screens

        delegate: BarWindow {}
    }
}
