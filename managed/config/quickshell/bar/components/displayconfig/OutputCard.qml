pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.bar
import ".."
import "."

Rectangle {
  id: root

  required property string outputName

  readonly property var output: HyprDisplayConfigState.getOutput(outputName)
  readonly property var mirrorChoices: {
    const items = ["None"];
    const names = HyprDisplayConfigState.outputNames;
    for (const name of names) {
      if (name !== root.outputName)
        items.push(name);
    }
    return items;
  }

  radius: Config.shape.corner.md
  color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container, 0.52))
  border.width: 1
  border.color: Qt.alpha(Config.color.outline_variant, 0.55)
  implicitHeight: body.implicitHeight + Config.space.lg * 2

  ColumnLayout {
    id: body

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
          font.pixelSize: Config.type.titleSmall.size
          font.weight: Config.type.titleSmall.weight
          renderType: Text.NativeRendering
          text: root.outputName
        }

        Text {
          color: Config.color.on_surface_variant
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodySmall.size
          renderType: Text.NativeRendering
          text: HyprDisplayConfigState.outputLabel(root.outputName).replace(root.outputName + " • ", "")
          visible: text.length > 0
        }
      }

      CheckBox {
        checked: !!root.output.disabled
        text: "Disabled"
        onToggled: HyprDisplayConfigState.setField(root.outputName, "disabled", checked)
      }
    }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      rowSpacing: Config.space.sm
      columnSpacing: Config.space.md

      Label {
        text: "Resolution & Refresh"
        color: Config.color.on_surface_variant
      }
      StyledComboBox {
        Layout.fillWidth: true
        model: {
          const options = (root.output && root.output.availableModes && root.output.availableModes.length > 0)
            ? root.output.availableModes.slice()
            : [root.output && root.output.mode ? String(root.output.mode) : "preferred"];
          if (options.indexOf(root.output.mode) < 0)
            options.unshift(root.output.mode);
          return options;
        }
        currentIndex: Math.max(0, model.indexOf(root.output && root.output.mode ? String(root.output.mode) : "preferred"))
        textRole: ""
        delegate: ItemDelegate {
          required property string modelData
          width: parent ? parent.width : 240
          text: HyprDisplayConfigState.modeLabel(modelData)
        }
        contentItem: Text {
          color: Config.color.on_surface
          elide: Text.ElideRight
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodyMedium.size
          text: {
            const idx = parent.currentIndex;
            if (idx < 0 || idx >= parent.model.length)
              return "Preferred";
            return HyprDisplayConfigState.modeLabel(parent.model[idx]);
          }
          verticalAlignment: Text.AlignVCenter
        }
        onActivated: index => HyprDisplayConfigState.setField(root.outputName, "mode", model[index])
      }

      Label { text: "Scale"; color: Config.color.on_surface_variant }
      StyledComboBox {
        Layout.fillWidth: true
        model: ["0.75", "1.00", "1.25", "1.50", "1.75", "2.00", "2.50", "3.00"]
        currentIndex: {
          const current = Number(root.output && root.output.scale ? root.output.scale : 1).toFixed(2);
          const idx = model.indexOf(current);
          return idx >= 0 ? idx : 1;
        }
        onActivated: index => HyprDisplayConfigState.setField(root.outputName, "scale", parseFloat(model[index]))
      }

      Label { text: "Rotation"; color: Config.color.on_surface_variant }
      StyledComboBox {
        Layout.fillWidth: true
        model: [0, 1, 2, 3, 4, 5, 6, 7]
        currentIndex: Math.max(0, Math.min(7, Number(root.output && root.output.transform ? root.output.transform : 0)))
        delegate: ItemDelegate {
          required property int modelData
          width: parent ? parent.width : 220
          text: HyprDisplayConfigState.transformLabel(modelData)
        }
        contentItem: Text {
          color: Config.color.on_surface
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodyMedium.size
          text: HyprDisplayConfigState.transformLabel(parent.model[parent.currentIndex] || 0)
          verticalAlignment: Text.AlignVCenter
        }
        onActivated: index => HyprDisplayConfigState.setField(root.outputName, "transform", model[index])
      }

      Label { text: "Variable Refresh"; color: Config.color.on_surface_variant }
      StyledComboBox {
        Layout.fillWidth: true
        model: [0, 1, 2]
        currentIndex: Math.max(0, Math.min(2, Number(root.output && root.output.vrr ? root.output.vrr : 0)))
        delegate: ItemDelegate {
          required property int modelData
          width: parent ? parent.width : 220
          text: HyprDisplayConfigState.vrrLabel(modelData)
        }
        contentItem: Text {
          color: Config.color.on_surface
          font.family: Config.fontFamily
          font.pixelSize: Config.type.bodyMedium.size
          text: HyprDisplayConfigState.vrrLabel(parent.model[parent.currentIndex] || 0)
          verticalAlignment: Text.AlignVCenter
        }
        onActivated: index => HyprDisplayConfigState.setField(root.outputName, "vrr", model[index])
      }

      Label { text: "Mirror Display"; color: Config.color.on_surface_variant }
      StyledComboBox {
        Layout.fillWidth: true
        model: root.mirrorChoices
        currentIndex: {
          const current = root.output && root.output.mirror ? String(root.output.mirror) : "None";
          const idx = model.indexOf(current === "" ? "None" : current);
          return idx >= 0 ? idx : 0;
        }
        onActivated: index => HyprDisplayConfigState.setField(root.outputName, "mirror", model[index] === "None" ? "" : model[index])
      }

      Label { text: "Position"; color: Config.color.on_surface_variant }
      RowLayout {
        Layout.fillWidth: true
        spacing: Config.space.sm

        StyledSpinBox {
          Layout.fillWidth: true
          from: -20000
          to: 20000
          value: Number(root.output && root.output.x ? root.output.x : 0)
          onValueModified: HyprDisplayConfigState.setField(root.outputName, "x", value)
        }
        StyledSpinBox {
          Layout.fillWidth: true
          from: -20000
          to: 20000
          value: Number(root.output && root.output.y ? root.output.y : 0)
          onValueModified: HyprDisplayConfigState.setField(root.outputName, "y", value)
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: hdrSection.implicitHeight + Config.space.md * 2
      radius: Config.shape.corner.sm
      color: Qt.tint(Config.barPopupSurface, Qt.alpha(Config.color.surface_container_high, 0.4))
      border.width: 1
      border.color: Qt.alpha(Config.color.outline_variant, 0.45)

      ColumnLayout {
        id: hdrSection

        anchors.fill: parent
        anchors.margins: Config.space.md
        spacing: Config.space.sm

        Text {
          color: Config.color.on_surface
          font.family: Config.fontFamily
          font.pixelSize: Config.type.labelLarge.size
          font.weight: Config.type.labelLarge.weight
          renderType: Text.NativeRendering
          text: "Compositor Settings"
        }

        GridLayout {
          Layout.fillWidth: true
          columns: 2
          rowSpacing: Config.space.sm
          columnSpacing: Config.space.md

          Label { text: "10-bit Color"; color: Config.color.on_surface_variant }
          StyledComboBox {
            Layout.fillWidth: true
            model: [8, 10]
            currentIndex: Number(root.output && root.output.bitdepth ? root.output.bitdepth : 8) === 10 ? 1 : 0
            delegate: ItemDelegate {
              required property int modelData
              width: parent ? parent.width : 200
              text: modelData === 10 ? "Enabled" : "Disabled"
            }
            contentItem: Text {
              color: Config.color.on_surface
              font.family: Config.fontFamily
              font.pixelSize: Config.type.bodyMedium.size
              text: parent.currentIndex === 1 ? "Enabled" : "Disabled"
              verticalAlignment: Text.AlignVCenter
            }
            onActivated: index => HyprDisplayConfigState.setField(root.outputName, "bitdepth", model[index])
          }

          Label { text: "Color Gamut"; color: Config.color.on_surface_variant }
          StyledComboBox {
            Layout.fillWidth: true
            model: ["auto", "wide", "dcip3", "dp3", "adobe", "edid", "hdr", "hdredid"]
            currentIndex: {
              const current = root.output && root.output.cm ? String(root.output.cm) : "auto";
              const idx = model.indexOf(current);
              return idx >= 0 ? idx : 0;
            }
            delegate: ItemDelegate {
              required property string modelData
              width: parent ? parent.width : 240
              text: HyprDisplayConfigState.colorModeLabel(modelData)
            }
            contentItem: Text {
              color: Config.color.on_surface
              font.family: Config.fontFamily
              font.pixelSize: Config.type.bodyMedium.size
              text: HyprDisplayConfigState.colorModeLabel(parent.model[parent.currentIndex] || "auto")
              verticalAlignment: Text.AlignVCenter
            }
            onActivated: index => HyprDisplayConfigState.setField(root.outputName, "cm", model[index])
          }

          Label { text: "SDR Brightness"; color: Config.color.on_surface_variant }
          StyledField {
            Layout.fillWidth: true
            text: Number(root.output && root.output.sdrbrightness ? root.output.sdrbrightness : 1).toFixed(2)
            onEditingFinished: {
              const next = parseFloat(text);
              if (isFinite(next))
                HyprDisplayConfigState.setField(root.outputName, "sdrbrightness", Math.max(0.1, Math.min(5.0, next)));
            }
          }

          Label { text: "SDR Saturation"; color: Config.color.on_surface_variant }
          StyledField {
            Layout.fillWidth: true
            text: Number(root.output && root.output.sdrsaturation ? root.output.sdrsaturation : 1).toFixed(2)
            onEditingFinished: {
              const next = parseFloat(text);
              if (isFinite(next))
                HyprDisplayConfigState.setField(root.outputName, "sdrsaturation", Math.max(0.0, Math.min(3.0, next)));
            }
          }
        }
      }
    }
  }
}
