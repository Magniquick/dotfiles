pragma Singleton
import QtQml
import Quickshell
import "./Colors.js" as Colors 

// Singleton wrapper
Singleton{
  readonly property var palette: Colors.palette
}
