import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell._Window
import qs.bar
import "../../../common" as Common
import ".."

Item {
  id: root

  property bool open: false
  property Item targetItem: null
  readonly property var hostWindow: targetItem ? targetItem.QsWindow.window : null
  property string newProfileName: ""
  property real popupX: 0
  property real popupY: 0
  property bool popupPosInitialized: false
  readonly property string selectedProfileId: {
    const ids = Object.keys(HyprDisplayProfilesService.profiles || {});
    if (profileSelector.currentIndex < 0 || profileSelector.currentIndex >= ids.length)
      return "";
    return ids[profileSelector.currentIndex];
  }

  function outputNames() {
    return Object.keys(HyprDisplayConfigState.outputs || {});
  }

  PopupWindow {
    id: popup
    visible: root.open && root.hostWindow
    color: "transparent"
    implicitWidth: 900
    implicitHeight: 680

    anchor {
      adjustment: PopupAdjustment.SlideX | PopupAdjustment.ResizeX
      edges: Edges.Top
      gravity: Edges.Bottom
      rect.height: 0
      rect.width: (root.targetItem && root.hostWindow) ? root.targetItem.width : 0
      rect.x: root.popupPosInitialized
        ? root.popupX
        : ((root.targetItem && root.hostWindow) ? root.hostWindow.itemRect(root.targetItem).x : 0)
      rect.y: root.popupPosInitialized
        ? root.popupY
        : ((root.targetItem && root.hostWindow) ? (root.hostWindow.itemRect(root.targetItem).y + root.targetItem.height + Config.space.sm) : 0)
      window: root.hostWindow
    }

    Rectangle {
      anchors.fill: parent
      color: Config.color.surface_container_high
      border.width: 1
      border.color: Config.color.outline_variant
      radius: Config.shape.corner.md
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Config.space.md
      spacing: Config.space.md

      RowLayout {
        id: headerRow
        Layout.fillWidth: true
        spacing: Config.space.sm
        Text {
          text: "Display Configuration"
          color: Config.color.on_surface
          font.family: Config.fontFamily
          font.pixelSize: Config.type.titleMedium.size
          font.weight: Config.type.titleMedium.weight
        }
        Item { Layout.fillWidth: true }
        ActionChip {
          text: "Refresh"
          onClicked: HyprDisplayConfigState.refresh()
        }
        ActionChip {
          text: "Close"
          onClicked: root.open = false
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 0
        z: 10

        MouseArea {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: headerRow.implicitHeight
          acceptedButtons: Qt.LeftButton
          hoverEnabled: true
          cursorShape: Qt.SizeAllCursor
          property real lastX: 0
          property real lastY: 0
          onPressed: {
            if (!root.popupPosInitialized && root.targetItem && root.hostWindow) {
              const r = root.hostWindow.itemRect(root.targetItem);
              root.popupX = r.x;
              root.popupY = r.y + root.targetItem.height + Config.space.sm;
              root.popupPosInitialized = true;
            }
            lastX = mouse.x;
            lastY = mouse.y;
          }
          onPositionChanged: {
            if (!(mouse.buttons & Qt.LeftButton))
              return;
            root.popupX += (mouse.x - lastX);
            root.popupY += (mouse.y - lastY);
            lastX = mouse.x;
            lastY = mouse.y;
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: HyprDisplayConfigState.applyError !== "" || HyprDisplayService.lastError !== ""
        text: HyprDisplayConfigState.applyError !== "" ? HyprDisplayConfigState.applyError : HyprDisplayService.lastError
        color: Config.color.error
        font.family: Config.fontFamily
        font.pixelSize: Config.type.bodySmall.size
        wrapMode: Text.WordWrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.sm
        TextField {
          id: profileName
          Layout.fillWidth: true
          placeholderText: "New profile name"
          text: root.newProfileName
          onTextChanged: root.newProfileName = text
        }
        ActionChip {
          text: "Save Profile"
          onClicked: {
            const name = root.newProfileName.trim();
            if (!name)
              return;
            const managed = HyprDisplayService.generateManagedBlock(HyprDisplayConfigState.buildApplyMap());
            HyprDisplayProfilesService.createProfile(name, managed);
            root.newProfileName = "";
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.sm
        ComboBox {
          id: profileSelector
          Layout.fillWidth: true
          model: Object.keys(HyprDisplayProfilesService.profiles || {})
          textRole: ""
          delegate: ItemDelegate {
            required property string modelData
            width: profileSelector.width
            text: (HyprDisplayProfilesService.profiles[modelData]?.name || modelData) + (HyprDisplayProfilesService.activeProfileId === modelData ? " (active)" : "")
          }
          contentItem: Text {
            text: {
              const id = root.selectedProfileId;
              if (!id)
                return "Select profile";
              return HyprDisplayProfilesService.profiles[id]?.name || id;
            }
            color: Config.color.on_surface
            font.family: Config.fontFamily
            verticalAlignment: Text.AlignVCenter
          }
        }
        ActionChip {
          text: "Activate"
          onClicked: {
            const id = root.selectedProfileId;
            if (id)
              HyprDisplayProfilesService.activateProfile(id);
            HyprDisplayConfigState.refresh();
          }
        }
        ActionChip {
          text: "Delete"
          onClicked: {
            const id = root.selectedProfileId;
            if (id)
              HyprDisplayProfilesService.deleteProfile(id);
          }
        }
      }

      ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          width: parent.width
          spacing: Config.space.md

          Repeater {
            model: root.outputNames()
            delegate: Rectangle {
              required property string modelData
              readonly property var output: HyprDisplayConfigState.getOutput(modelData)
              Layout.fillWidth: true
              radius: Config.shape.corner.sm
              color: Config.color.surface_container
              border.width: 1
              border.color: Config.color.outline_variant
              implicitHeight: body.implicitHeight + Config.space.md * 2

              ColumnLayout {
                id: body
                anchors.fill: parent
                anchors.margins: Config.space.md
                spacing: Config.space.sm

                RowLayout {
                  Layout.fillWidth: true
                  Text {
                    text: output ? output.name : modelData
                    color: Config.color.on_surface
                    font.family: Config.fontFamily
                    font.pixelSize: Config.type.titleSmall.size
                    font.weight: Config.type.titleSmall.weight
                  }
                  Item { Layout.fillWidth: true }
                  CheckBox {
                    text: "Disabled"
                    checked: output ? !!output.disabled : false
                    onToggled: HyprDisplayConfigState.setField(modelData, "disabled", checked)
                  }
                }

                GridLayout {
                  Layout.fillWidth: true
                  columns: 4
                  rowSpacing: Config.space.xs
                  columnSpacing: Config.space.sm

                  Label { text: "Mode"; color: Config.color.on_surface_variant }
                  TextField {
                    Layout.fillWidth: true
                    text: output && output.mode ? String(output.mode) : "preferred"
                    onEditingFinished: HyprDisplayConfigState.setField(modelData, "mode", text.trim() || "preferred")
                  }

                  Label { text: "Scale"; color: Config.color.on_surface_variant }
                  SpinBox {
                    Layout.fillWidth: true
                    from: 25
                    to: 400
                    value: output ? Math.round((output.scale || 1) * 100) : 100
                    onValueChanged: {
                      if (!activeFocus)
                        return;
                      HyprDisplayConfigState.setField(modelData, "scale", value / 100.0);
                    }
                  }

                  Label { text: "X"; color: Config.color.on_surface_variant }
                  SpinBox {
                    Layout.fillWidth: true
                    from: -20000; to: 20000
                    value: output ? (output.x || 0) : 0
                    onValueChanged: {
                      if (!activeFocus)
                        return;
                      HyprDisplayConfigState.setField(modelData, "x", value);
                    }
                  }
                  Label { text: "Y"; color: Config.color.on_surface_variant }
                  SpinBox {
                    Layout.fillWidth: true
                    from: -20000; to: 20000
                    value: output ? (output.y || 0) : 0
                    onValueChanged: {
                      if (!activeFocus)
                        return;
                      HyprDisplayConfigState.setField(modelData, "y", value);
                    }
                  }

                  Label { text: "Transform"; color: Config.color.on_surface_variant }
                  ComboBox {
                    Layout.fillWidth: true
                    model: ["0", "1", "2", "3", "4", "5", "6", "7"]
                    currentIndex: Math.max(0, Math.min(7, output ? (output.transform || 0) : 0))
                    onActivated: HyprDisplayConfigState.setField(modelData, "transform", parseInt(model[index]))
                  }
                  Label { text: "VRR"; color: Config.color.on_surface_variant }
                  ComboBox {
                    Layout.fillWidth: true
                    model: ["0", "1", "2"]
                    currentIndex: Math.max(0, Math.min(2, output ? (output.vrr || 0) : 0))
                    onActivated: HyprDisplayConfigState.setField(modelData, "vrr", parseInt(model[index]))
                  }

                  Label { text: "Mirror"; color: Config.color.on_surface_variant }
                  TextField {
                    Layout.fillWidth: true
                    text: output && output.mirror ? String(output.mirror) : ""
                    onEditingFinished: HyprDisplayConfigState.setField(modelData, "mirror", text.trim())
                  }
                  Label { text: "Bitdepth"; color: Config.color.on_surface_variant }
                  ComboBox {
                    Layout.fillWidth: true
                    model: ["8", "10"]
                    currentIndex: output && Number(output.bitdepth) === 10 ? 1 : 0
                    onActivated: HyprDisplayConfigState.setField(modelData, "bitdepth", parseInt(model[index]))
                  }

                  Label { text: "CM"; color: Config.color.on_surface_variant }
                  ComboBox {
                    Layout.fillWidth: true
                    model: ["auto", "wide", "dcip3", "dp3", "adobe", "edid", "hdr", "hdredid"]
                    currentIndex: {
                      const value = output && output.cm ? String(output.cm) : "auto";
                      const idx = model.indexOf(value);
                      return idx >= 0 ? idx : 0;
                    }
                    onActivated: HyprDisplayConfigState.setField(modelData, "cm", model[index])
                  }
                  Label { text: "SDR Br."; color: Config.color.on_surface_variant }
                  TextField {
                    Layout.fillWidth: true
                    text: output ? String(output.sdrbrightness || 1.0) : "1.0"
                    onEditingFinished: {
                      const n = parseFloat(text);
                      if (isFinite(n))
                        HyprDisplayConfigState.setField(modelData, "sdrbrightness", Math.max(0.1, Math.min(5.0, n)));
                    }
                  }

                  Label { text: "SDR Sat."; color: Config.color.on_surface_variant }
                  TextField {
                    Layout.fillWidth: true
                    text: output ? String(output.sdrsaturation || 1.0) : "1.0"
                    onEditingFinished: {
                      const n = parseFloat(text);
                      if (isFinite(n))
                        HyprDisplayConfigState.setField(modelData, "sdrsaturation", Math.max(0.0, Math.min(3.0, n)));
                    }
                  }
                }
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.sm

        Text {
          Layout.fillWidth: true
          text: HyprDisplayConfigState.waitingConfirm
            ? "Applied. Confirm within " + HyprDisplayConfigState.confirmSeconds + "s or changes will revert."
            : (HyprDisplayConfigState.hasPending ? "Pending changes" : "No pending changes")
          color: Config.color.on_surface_variant
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodySmall.size
        }

        ActionChip {
          text: "Discard"
          onClicked: HyprDisplayConfigState.clearPending()
          visible: !HyprDisplayConfigState.waitingConfirm
        }
        ActionChip {
          text: "Apply"
          onClicked: HyprDisplayConfigState.apply()
          visible: !HyprDisplayConfigState.waitingConfirm
        }
        ActionChip {
          text: "Confirm"
          onClicked: HyprDisplayConfigState.confirm()
          visible: HyprDisplayConfigState.waitingConfirm
        }
        ActionChip {
          text: "Revert"
          onClicked: HyprDisplayConfigState.revert()
          visible: HyprDisplayConfigState.waitingConfirm
        }
      }
    }
  }
}
