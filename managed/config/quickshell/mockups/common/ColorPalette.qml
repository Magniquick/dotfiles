pragma Singleton
import QtQml
import Quickshell
import "."

Singleton {
    readonly property var color: Colors.color
    readonly property var palette: Colors.palette
}
