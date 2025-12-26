import "../"
import QtQuick

BarBlock {
    id: text

    content: BarText {
        symbolText: ` ${Datetime.time}`
    }
}
