//@ pragma UseQApplication
import QtQuick
import QtQml
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import "bar" as Bar
import "sysclock" as Clock
import "leftpanel" as LeftPanel
import "rightpanel" as RightPanel

ShellRoot {
    id: shellRoot

    // Clock.ClockWidget {}
    LoggingCategory {
        defaultLogLevel: LoggingCategory.Critical
        name: "quickshell.dbus.properties"
    }
    Variants {
        model: Quickshell.screens
        delegate: Bar.BarWindow {}
    }

    // Track left panel visibility with animation state
    property bool leftPanelAnimating: false
    property bool leftPanelShouldShow: Bar.GlobalState.leftPanelVisible

    onLeftPanelShouldShowChanged: {
        leftPanelAnimating = true;
        if (leftPanelShouldShow) {
            leftFocusGrab.active = true;
        }
    }

    HyprlandFocusGrab {
        id: leftFocusGrab
        windows: [leftPanelWindow]
        onCleared: Bar.GlobalState.leftPanelVisible = false
    }

    PanelWindow {
        id: leftPanelWindow

        readonly property int panelWidth: 380

        color: "transparent"
        visible: shellRoot.leftPanelShouldShow || shellRoot.leftPanelAnimating

        anchors {
            top: true
            left: true
            bottom: true
        }
        implicitWidth: panelWidth + Bar.Config.outerGaps

        WlrLayershell.namespace: "quickshell:leftpanel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        Shortcut {
            context: Qt.ApplicationShortcut
            enabled: leftPanelWindow.visible
            sequence: "Escape"
            onActivated: Bar.GlobalState.leftPanelVisible = false
        }

        Item {
            id: leftPanelContainer
            y: Bar.Config.outerGaps
            width: leftPanelWindow.panelWidth
            height: parent.height - Bar.Config.outerGaps * 2

            x: Bar.GlobalState.leftPanelVisible ? Bar.Config.outerGaps : -leftPanelWindow.panelWidth - Bar.Config.outerGaps

            Behavior on x {
                NumberAnimation {
                    id: leftPanelSlide
                    duration: Bar.Config.motion.duration.medium
                    easing.type: Bar.GlobalState.leftPanelVisible ? Easing.OutCubic : Easing.InCubic
                    onRunningChanged: {
                        if (!running) {
                            shellRoot.leftPanelAnimating = false;
                            if (!Bar.GlobalState.leftPanelVisible) {
                                leftFocusGrab.active = false;
                            }
                        }
                    }
                }
            }

            LeftPanel.LeftPanel {
                anchors.fill: parent
            }
        }
    }

    // Track right panel visibility with animation state
    property bool rightPanelAnimating: false
    property bool rightPanelShouldShow: Bar.GlobalState.rightPanelVisible

    onRightPanelShouldShowChanged: {
        rightPanelAnimating = true;
        if (rightPanelShouldShow) {
            rightFocusGrab.active = true;
        }
    }

    HyprlandFocusGrab {
        id: rightFocusGrab
        windows: [rightPanelWindow]
        onCleared: Bar.GlobalState.rightPanelVisible = false
    }

    PanelWindow {
        id: rightPanelWindow

        readonly property int panelWidth: 420

        color: "transparent"
        visible: shellRoot.rightPanelShouldShow || shellRoot.rightPanelAnimating

        anchors {
            top: true
            right: true
            bottom: true
        }
        implicitWidth: panelWidth

        WlrLayershell.namespace: "quickshell:rightpanel"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        Shortcut {
            context: Qt.ApplicationShortcut
            enabled: rightPanelWindow.visible
            sequence: "Escape"
            onActivated: Bar.GlobalState.rightPanelVisible = false
        }

        Item {
            id: rightPanelContainer
            y: Bar.Config.outerGaps
            width: rightPanelWindow.panelWidth
            height: parent.height - Bar.Config.outerGaps * 2

            x: Bar.GlobalState.rightPanelVisible ? 0 : rightPanelWindow.panelWidth

            Behavior on x {
                NumberAnimation {
                    id: rightPanelSlide
                    duration: Bar.Config.motion.duration.medium
                    easing.type: Bar.GlobalState.rightPanelVisible ? Easing.OutCubic : Easing.InCubic
                    onRunningChanged: {
                        if (!running) {
                            shellRoot.rightPanelAnimating = false;
                            if (!Bar.GlobalState.rightPanelVisible) {
                                rightFocusGrab.active = false;
                            }
                        }
                    }
                }
            }

            RightPanel.RightPanel {
                anchors.fill: parent
            }
        }
    }
}
