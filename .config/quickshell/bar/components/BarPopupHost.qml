pragma ComponentBehavior: Bound
import ".."
import QtQml
import QtQuick

Item {
  id: root

  TooltipPopup {
    id: popup

    autoScroll: BarPopupState.autoScroll
    browserLink: BarPopupState.browserLink
    contentComponent: BarPopupState.contentComponent
    enabled: BarPopupState.enabled
    hoverable: BarPopupState.hoverable
    maximumHeight: BarPopupState.maximumHeight
    open: BarPopupState.open
    refreshing: BarPopupState.refreshing
    showBrowserIcon: BarPopupState.showBrowserIcon
    showRefreshIcon: BarPopupState.showRefreshIcon
    showScrollIndicator: BarPopupState.showScrollIndicator
    subtitle: BarPopupState.subtitle
    targetItem: BarPopupState.targetItem
    targetWindow: BarPopupState.targetWindow
    title: BarPopupState.title

    onRefreshRequested: BarPopupState.requestRefresh()
  }

  Binding {
    target: BarPopupState
    property: "contentItem"
    value: popup.contentItem
  }

  Binding {
    target: BarPopupState
    property: "visualActive"
    value: popup.visualActive
  }

  Connections {
    target: BarPopupState

    function onOpenChanged() {
      if (!BarPopupState.open && !BarPopupState.visualActive)
        BarPopupState.finishClose()
    }
  }

  Connections {
    target: popup

    function onPopupHoveredChanged() {
      BarPopupState.setPopupHovered(popup.popupHovered)
    }

    function onVisualActiveChanged() {
      if (!popup.visualActive && !BarPopupState.open)
        BarPopupState.finishClose()
    }
  }
}
