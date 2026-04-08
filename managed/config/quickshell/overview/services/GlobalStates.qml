pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../common" as MainCommon

Singleton {
    id: root
    property bool overviewOpen: false
    property bool _syncing: false

    onOverviewOpenChanged: {
        if (_syncing) return;
        _syncing = true;
        if (overviewOpen)
            MainCommon.GlobalState.openOverview(null);
        else
            MainCommon.GlobalState.closeOverview();
        _syncing = false;
    }

    Connections {
        target: MainCommon.GlobalState
        function onOverviewVisibleChanged() {
            if (root._syncing) return;
            root._syncing = true;
            root.overviewOpen = MainCommon.GlobalState.overviewVisible;
            root._syncing = false;
        }
    }
}
