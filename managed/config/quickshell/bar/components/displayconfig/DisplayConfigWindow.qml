pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell._Window
import qs.common.materialkit as MK
import qs.bar
import ".."
import "."

Item {
  id: root

  property bool open: false
  property Item targetItem: null
  readonly property var hostWindow: targetItem ? targetItem.QsWindow.window : null
  property string newProfileName: ""

  readonly property var profileIds: Object.keys(HyprDisplayProfilesService.profiles || {})
  readonly property string selectedProfileId: {
    if (profileSelector.currentIndex < 0 || profileSelector.currentIndex >= root.profileIds.length)
      return "";
    return root.profileIds[profileSelector.currentIndex];
  }

  function profileNameById(id) {
    return id ? (HyprDisplayProfilesService.profiles[id]?.name || id) : "";
  }

  function saveProfile() {
    const name = root.newProfileName.trim();
    if (!name)
      return;
    const managed = HyprDisplayService.generateManagedBlock(HyprDisplayConfigState.buildApplyMap());
    HyprDisplayProfilesService.createProfile(name, managed);
    root.newProfileName = "";
  }

  PopupWindow {
    id: popup

    visible: root.open && root.hostWindow
    color: "transparent"
    implicitWidth: 980
    implicitHeight: 760

    anchor {
      adjustment: PopupAdjustment.SlideX | PopupAdjustment.SlideY | PopupAdjustment.ResizeX | PopupAdjustment.ResizeY
      edges: Edges.Top
      gravity: Edges.Bottom
      rect.height: 0
      rect.width: root.targetItem ? root.targetItem.width : 0
      rect.x: (root.targetItem && root.hostWindow) ? root.hostWindow.itemRect(root.targetItem).x : 0
      rect.y: (root.targetItem && root.hostWindow) ? (root.hostWindow.itemRect(root.targetItem).y + root.targetItem.height + Config.space.sm) : 0
      window: root.hostWindow
    }

    Rectangle {
      anchors.fill: parent
      radius: Config.shape.corner.lg
      color: Config.barPopupSurface
      border.width: 1
      border.color: Qt.alpha(Config.color.outline_variant, 0.68)
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Config.space.lg
      spacing: Config.space.md

      RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.md

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Config.space.xs

          Text {
            color: Config.color.on_surface
            font.family: Config.fontFamily
            font.pixelSize: Config.type.titleLarge.size
            font.weight: Config.type.titleLarge.weight
            renderType: Text.NativeRendering
            text: "Display Configuration"
          }

          Text {
            color: Config.color.on_surface_variant
            font.family: Config.fontFamily
            font.pixelSize: Config.type.bodySmall.size
            renderType: Text.NativeRendering
            text: "Arrange monitors, tune Hyprland output settings, and save display profiles."
          }
        }

        ActionChip {
          text: "Refresh"
          onClicked: {
            HyprDisplayProfilesService.load();
            HyprDisplayConfigState.refresh();
          }
        }
        ActionChip {
          text: "Close"
          onClicked: root.open = false
        }
      }

      Rectangle {
        Layout.fillWidth: true
        visible: HyprDisplayConfigState.applyError !== "" || HyprDisplayService.lastError !== "" || HyprDisplayProfilesService.lastError !== ""
        radius: Config.shape.corner.md
        color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.error, 0.16))
        border.width: 1
        border.color: Qt.alpha(Config.color.error, 0.5)
        implicitHeight: errorText.implicitHeight + Config.space.md * 2

        Text {
          id: errorText

          anchors.fill: parent
          anchors.margins: Config.space.md
          color: Config.color.error
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodySmall.size
          renderType: Text.NativeRendering
          wrapMode: Text.WordWrap
          text: HyprDisplayConfigState.applyError || HyprDisplayService.lastError || HyprDisplayProfilesService.lastError
        }
      }

      MK.Flickable {
        id: contentFlickable

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        interactive: !monitorCanvas.dragActive
        contentWidth: width
        contentHeight: contentColumn.implicitHeight

        ColumnLayout {
          id: contentColumn

          width: contentFlickable.width
          spacing: Config.space.md

          Rectangle {
            Layout.fillWidth: true
            radius: Config.shape.corner.md
            color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container, 0.48))
            border.width: 1
            border.color: Qt.alpha(Config.color.outline_variant, 0.55)
            implicitHeight: profileColumn.implicitHeight + Config.space.lg * 2

            ColumnLayout {
              id: profileColumn

              anchors.fill: parent
              anchors.margins: Config.space.lg
              spacing: Config.space.md

              RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Config.space.xs

                  Text {
                    color: Config.color.on_surface
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.titleSmall.size
                    font.weight: Config.type.titleSmall.weight
                    renderType: Text.NativeRendering
                    text: "Display Profiles"
                  }

                  Text {
                    color: Config.color.on_surface_variant
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.bodySmall.size
                    renderType: Text.NativeRendering
                    text: "Save and switch between known monitor layouts."
                  }
                }

                Text {
                  color: Config.color.primary
                  font.family: Config.fontFamily
                  font.pixelSize: Config.type.labelMedium.size
                  font.weight: Config.type.labelMedium.weight
                  renderType: Text.NativeRendering
                  text: {
                    const id = HyprDisplayProfilesService.activeProfileId;
                    return id ? ("Active: " + root.profileNameById(id)) : "No active profile";
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.sm

                StyledField {
                  Layout.fillWidth: true
                  placeholderText: "New profile name"
                  text: root.newProfileName
                  onTextChanged: root.newProfileName = text
                  onAccepted: root.saveProfile()
                }

                ActionChip {
                  id: saveProfileChip

                  text: "Save Profile"
                  onClicked: root.saveProfile()
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Config.space.sm

                StyledComboBox {
                  id: profileSelector

                  Layout.fillWidth: true
                  model: root.profileIds
                  currentIndex: Math.max(0, root.profileIds.indexOf(HyprDisplayProfilesService.activeProfileId))
                  delegate: ItemDelegate {
                    required property string modelData
                    width: parent ? parent.width : 260
                    text: root.profileNameById(modelData) + (HyprDisplayProfilesService.activeProfileId === modelData ? " (active)" : "")
                  }
                  contentItem: Text {
                    color: Config.color.on_surface
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.bodyMedium.size
                    elide: Text.ElideRight
                    text: {
                      const id = root.selectedProfileId;
                      return id ? root.profileNameById(id) : "Select profile";
                    }
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                ActionChip {
                  text: "Activate"
                  onClicked: {
                    if (!root.selectedProfileId)
                      return;
                    HyprDisplayProfilesService.activateProfile(root.selectedProfileId);
                    HyprDisplayConfigState.refresh();
                  }
                }
                ActionChip {
                  text: "Delete"
                  onClicked: {
                    if (root.selectedProfileId)
                      HyprDisplayProfilesService.deleteProfile(root.selectedProfileId);
                  }
                }
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            radius: Config.shape.corner.md
            color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container, 0.48))
            border.width: 1
            border.color: Qt.alpha(Config.color.outline_variant, 0.55)
            implicitHeight: monitorColumn.implicitHeight + Config.space.lg * 2

            ColumnLayout {
              id: monitorColumn

              anchors.fill: parent
              anchors.margins: Config.space.lg
              spacing: Config.space.md

              ColumnLayout {
                Layout.fillWidth: true
                  spacing: Config.space.xs

                Text {
                  color: Config.color.on_surface
                  font.family: Config.fontFamily
                  font.pixelSize: Config.type.titleSmall.size
                  font.weight: Config.type.titleSmall.weight
                  renderType: Text.NativeRendering
                  text: "Monitor Configuration"
                }

                Text {
                  color: Config.color.on_surface_variant
                  font.family: Config.fontFamily
                  font.pixelSize: Config.type.bodySmall.size
                  renderType: Text.NativeRendering
                  text: "Drag monitors to reposition them, then fine-tune output settings below."
                }
              }

              MonitorCanvas {
                id: monitorCanvas

                Layout.fillWidth: true
              }

              Repeater {
                model: HyprDisplayConfigState.outputNames

                delegate: OutputCard {
                  required property string modelData
                  Layout.fillWidth: true
                  outputName: modelData
                }
              }
            }
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        radius: Config.shape.corner.md
        color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container_high, 0.56))
        border.width: 1
        border.color: Qt.alpha(Config.color.outline_variant, 0.55)
        implicitHeight: actionRow.implicitHeight + Config.space.md * 2

        RowLayout {
          id: actionRow

          anchors.fill: parent
          anchors.margins: Config.space.md
          spacing: Config.space.sm

          Text {
            Layout.fillWidth: true
            color: Config.color.on_surface_variant
            font.family: Config.fontFamily
            font.pixelSize: Config.type.bodySmall.size
            renderType: Text.NativeRendering
            text: HyprDisplayConfigState.waitingConfirm
              ? ("Confirm changes within " + HyprDisplayConfigState.confirmRemainingSeconds + "s or they will revert automatically.")
              : (HyprDisplayConfigState.hasPending ? "Pending display changes ready to apply." : "No pending display changes.")
          }

          ActionChip {
            text: "Discard"
            visible: !HyprDisplayConfigState.waitingConfirm
            onClicked: HyprDisplayConfigState.clearPending()
          }
          ActionChip {
            text: "Apply"
            visible: !HyprDisplayConfigState.waitingConfirm
            onClicked: HyprDisplayConfigState.apply()
          }
          ActionChip {
            text: "Keep Changes"
            visible: HyprDisplayConfigState.waitingConfirm
            onClicked: HyprDisplayConfigState.confirm()
          }
          ActionChip {
            text: "Revert"
            visible: HyprDisplayConfigState.waitingConfirm
            onClicked: HyprDisplayConfigState.revert()
          }
        }
      }
    }
  }
}
