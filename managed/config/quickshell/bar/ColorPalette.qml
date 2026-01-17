pragma Singleton
import "./Colors.js" as Colors
import QtQml
import Quickshell

Singleton {
    readonly property var palette: Colors.palette
}
