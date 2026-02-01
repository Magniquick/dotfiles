pragma Singleton
import QtQml

QtObject {
    property bool leftPanelVisible: false
    property bool rightPanelVisible: false

    function toggleLeftPanel() {
        leftPanelVisible = !leftPanelVisible;
    }

    function toggleRightPanel() {
        rightPanelVisible = !rightPanelVisible;
    }
}
