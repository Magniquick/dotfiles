import QtQuick
import QtQml
import Quickshell
import "."

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
