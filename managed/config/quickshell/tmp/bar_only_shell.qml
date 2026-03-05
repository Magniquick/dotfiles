import Quickshell
import "../bar" as Bar

ShellRoot {
  Variants {
    model: Quickshell.screens
    delegate: Bar.BarWindow {}
  }
}
