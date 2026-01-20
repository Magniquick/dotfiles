pragma Singleton

import Quickshell
import QtQuick

Singleton {
    SystemClock {
        id: clock
        precision: SystemClock.Hours
    }
    function format(fmt) {
        return Qt.formatDateTime(clock.date, fmt);
    }
}
