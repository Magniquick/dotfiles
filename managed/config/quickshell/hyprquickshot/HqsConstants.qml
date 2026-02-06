pragma Singleton
import QtQml

QtObject {
    readonly property int grabDelayMs: 60
    readonly property int countdownStartValue: 3
    readonly property int countdownTickMs: 900
}
