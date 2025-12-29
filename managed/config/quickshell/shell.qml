import QtQuick
import QtQml
import Quickshell

import "bar" as Bar
import "sysclock" as Clock

ShellRoot {
    Clock.ClockWidget {}
    LoggingCategory {
        defaultLogLevel: LoggingCategory.Critical
        name: "quickshell.dbus.properties"
    }
    Variants {
        model: Quickshell.screens
        delegate: Bar.BarWindow {
        }
    }
}
