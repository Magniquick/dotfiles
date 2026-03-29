pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Bluetooth
import Quickshell.Networking
import "common" as Common
import "common/materialkit" as MK

WlSessionLockSurface {
  id: root

  required property LockContext context
  property var now: new Date()
  property bool startAnim: false
  readonly property string powermenuLauncher: Quickshell.shellPath("../tools/run-quickshell.sh")
  readonly property string currentUser: Quickshell.env("USER") || "user"
  readonly property string profileImagePath: Quickshell.shellPath("assets/pfp.png")
  readonly property string mondDisplayFontFamily: "Anurati"
  property string wallpaperPath: ""
  property bool powerMenuVisible: false
  property bool advancedPowerOptions: false
  readonly property int surfaceRadius: Common.Config.shape.corner.lg
  readonly property int panelPadding: 20

  readonly property var colors: Common.Config.color

  function clearPasswordField() {
    passField.clear();
    root.context.currentText = "";
    root.context.clearError();
    passField.forceActiveFocus();
  }

  function openPowermenu() {
    root.powerMenuVisible = true;
  }

  function togglePowerMenu(advancedRequested) {
    if (!root.powerMenuVisible) {
      root.advancedPowerOptions = !!advancedRequested;
      root.powerMenuVisible = true;
    } else if (advancedRequested) {
      root.advancedPowerOptions = true;
    } else {
      root.powerMenuVisible = false;
      root.advancedPowerOptions = false;
    }
    if (root.powerMenuVisible)
      passField.forceActiveFocus();
  }

  function runPowerAction(action) {
    let cmd = [];
    if (action === "suspend")
      cmd = ["systemctl", "suspend"];
    else if (action === "reboot")
      cmd = ["systemctl", "reboot"];
    else if (action === "poweroff")
      cmd = ["systemctl", "poweroff"];
    else if (action === "hibernate")
      cmd = ["systemctl", "hibernate"];
    else if (action === "windows")
      cmd = ["systemctl", "reboot", "--boot-loader-entry=auto-windows"];
    else if (action === "powermenu")
      cmd = [root.powermenuLauncher, "--standalone", "powermenu", "-n"];

    if (action === "logout") {
      root.powerMenuVisible = false;
      root.advancedPowerOptions = false;
      Hyprland.dispatch("exit");
      return;
    }

    if (cmd.length === 0)
      return;
    root.powerMenuVisible = false;
    root.advancedPowerOptions = false;
    Quickshell.execDetached(cmd);
  }

  QtObject {
    id: statusService
    readonly property bool nativeNetworkBackend: Networking.backend === NetworkBackendType.NetworkManager

    function modelAt(model, index) {
      if (!model || index < 0)
        return null;
      if (model.values && typeof model.values.length === "number")
        return model.values[index];
      if (typeof model.get === "function")
        return model.get(index);
      return model[index];
    }

    function modelCount(model) {
      if (!model)
        return 0;
      if (model.values && typeof model.values.length === "number")
        return model.values.length;
      if (typeof model.count === "number")
        return model.count;
      if (typeof model.length === "number")
        return model.length;
      return 0;
    }

    readonly property var connectedDevice: {
      if (!nativeNetworkBackend || !Networking.devices)
        return null;
      let fallbackEthernet = null;
      const deviceCount = modelCount(Networking.devices);
      for (let i = 0; i < deviceCount; i++) {
        const dev = modelAt(Networking.devices, i);
        if (!dev || !dev.connected)
          continue;
        if (dev.type === DeviceType.Wifi)
          return dev;
        if (!fallbackEthernet)
          fallbackEthernet = dev;
      }
      return fallbackEthernet;
    }

    readonly property var connectedWifiNetwork: {
      const dev = connectedDevice;
      if (!dev || dev.type !== DeviceType.Wifi || !dev.networks)
        return null;
      const networkCount = modelCount(dev.networks);
      for (let i = 0; i < networkCount; i++) {
        const network = modelAt(dev.networks, i);
        if (network && network.connected)
          return network;
      }
      return null;
    }

    property var adapter: Bluetooth.defaultAdapter
    property int bluetoothConnectedCount: {
      if (!adapter || !adapter.devices) return 0;
      let count = 0;
      for (let i = 0; i < adapter.devices.count; i++) {
        const dev = adapter.devices.get(i);
        if (dev && dev.connected) count++;
      }
      return count;
    }
  }

  component StatusTile: Rectangle {
    id: tile
    property string icon: ""
    property string text: ""
    property color accentColor: root.colors.on_surface_variant
    property bool active: false

    implicitWidth: statusLabel.implicitWidth + statusIcon.implicitWidth + 28
    implicitHeight: 32
    radius: 16
    color: active ? Qt.alpha(tile.accentColor, 0.15) : Qt.alpha(root.colors.surface_container_low, 0.6)
    border.width: 1
    border.color: active ? Qt.alpha(tile.accentColor, 0.3) : Qt.alpha(root.colors.outline_variant, 0.4)

    RowLayout {
      anchors.centerIn: parent
      spacing: 8
      Text {
        id: statusIcon
        text: tile.icon
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 14
        color: tile.active ? tile.accentColor : root.colors.on_surface_variant
      }
      Text {
        id: statusLabel
        text: tile.text
        font.family: Common.Config.fontFamily
        font.pixelSize: Common.Config.type.labelLarge.size
        font.weight: Font.Medium
        color: tile.active ? tile.accentColor : root.colors.on_surface_variant
        visible: text.length > 0
      }
    }
  }

  component LockButton: MK.ElevationRectangle {
    id: button

    signal clicked

    property string text: ""
    property bool filled: false
    property bool danger: false
    property bool iconOnly: false
    property bool hovered: buttonMouse.containsMouse
    property bool pressed: buttonMouse.pressed
    property bool buttonEnabled: true
    property int leftPadding: iconOnly ? 0 : 13
    property int rightPadding: iconOnly ? 0 : 13
    property string textFontFamily: iconOnly ? Common.Config.iconFontFamily : Common.Config.fontFamily
    property int textFontPixelSize: iconOnly ? 17 : Common.Config.type.labelLarge.size
    property int textFontWeight: Font.Medium
    readonly property bool dotState: text === "..." || text === "…"

    implicitHeight: 36
    implicitWidth: iconOnly ? 36 : Math.max(dotState ? 96 : 88, label.implicitWidth + leftPadding + rightPadding)

    color: {
      if (!button.buttonEnabled)
        return Qt.alpha(root.colors.surface_container_low, 0.45);
      if (button.pressed)
        return button.filled ? Qt.alpha(root.colors.primary, 0.84) : Qt.alpha(root.colors.surface_container_highest, 0.95);
      if (button.filled)
        return root.colors.primary;
      if (button.hovered)
        return Qt.alpha(root.colors.surface_container_highest, 0.95);
      return Qt.alpha(root.colors.surface_container_low, 0.85);
    }
    radius: Common.Config.shape.corner.md
    elevation: button.pressed ? 0 : (button.hovered ? 2 : 1)

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      radius: button.radius
      border.width: 1
      border.color: {
        if (!button.buttonEnabled)
          return Qt.alpha(root.colors.outline_variant, 0.4);
        if (button.filled)
          return Qt.alpha(root.colors.primary, 0.8);
        if (button.danger)
          return Qt.alpha(root.colors.error, 0.7);
        return Qt.alpha(root.colors.outline_variant, 0.85);
      }

      Behavior on border.color {
        ColorAnimation { duration: Common.Config.motion.duration.shortMs }
      }
    }

    Text {
      id: label

      anchors.centerIn: parent
      text: button.dotState ? "•••" : button.text
      color: {
        if (!button.buttonEnabled)
          return Qt.alpha(root.colors.on_surface, 0.5);
        if (button.filled)
          return root.colors.on_primary;
        if (button.danger)
          return root.colors.error;
        return root.colors.on_surface;
      }
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      font.family: button.textFontFamily
      font.pixelSize: button.textFontPixelSize
      font.weight: button.textFontWeight
      font.letterSpacing: button.dotState ? 2 : 0
    }

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      radius: button.radius
      clip: true

      MK.HybridRipple {
        anchors.fill: parent
        color: button.filled ? root.colors.on_primary : root.colors.on_surface
        pressX: buttonMouse.pressX
        pressY: buttonMouse.pressY
        pressed: buttonMouse.pressed
        radius: button.radius
        stateOpacity: 0
      }
    }

    Behavior on color {
      ColorAnimation { duration: Common.Config.motion.duration.shortMs }
    }
    Behavior on elevation {
      NumberAnimation { duration: Common.Config.motion.duration.shortMs }
    }

    MouseArea {
      id: buttonMouse

      property real pressX: width / 2
      property real pressY: height / 2

      anchors.fill: parent
      enabled: button.buttonEnabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

      onPressed: function(mouse) {
        pressX = mouse.x;
        pressY = mouse.y;
      }
      onClicked: button.clicked()
    }
  }

  color: "transparent"

  Rectangle {
    anchors.fill: parent
    color: root.colors.scrim
  }

  Image {
    id: background

    anchors.fill: parent
    source: root.wallpaperPath.length > 0 ? ("file://" + root.wallpaperPath) : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: false
    visible: root.wallpaperPath.length > 0
    scale: root.startAnim ? 1.06 : 1
    layer.enabled: true
    layer.effect: MultiEffect {
      autoPaddingEnabled: false
      blurEnabled: true
      blur: root.startAnim ? 1.0 : 0.0
      blurMax: 36
      saturation: root.startAnim ? 0.12 : 0.0
      brightness: root.startAnim ? -0.12 : 0.0

      Behavior on blur {
        NumberAnimation {
          duration: Common.Config.motion.duration.longMs
          easing.type: Easing.OutCubic
        }
      }
      Behavior on saturation {
        NumberAnimation {
          duration: Common.Config.motion.duration.longMs
          easing.type: Easing.OutCubic
        }
      }
      Behavior on brightness {
        NumberAnimation {
          duration: Common.Config.motion.duration.longMs
          easing.type: Easing.OutCubic
        }
      }
    }

    Behavior on scale {
      NumberAnimation {
        duration: Common.Config.motion.duration.longMs
        easing.type: Easing.OutCubic
      }
    }
  }

  ScreencopyView {
    id: screencopyFallback

    anchors.fill: parent
    captureSource: root.screen
    live: false
    visible: !background.visible
    scale: root.startAnim ? 1.06 : 1
    layer.enabled: true
    layer.effect: MultiEffect {
      autoPaddingEnabled: false
      blurEnabled: true
      blur: root.startAnim ? 1.0 : 0.0
      blurMax: 36
      saturation: root.startAnim ? 0.12 : 0.0
      brightness: root.startAnim ? -0.12 : 0.0

      Behavior on blur {
        NumberAnimation {
          duration: Common.Config.motion.duration.longMs
          easing.type: Easing.OutCubic
        }
      }
      Behavior on saturation {
        NumberAnimation {
          duration: Common.Config.motion.duration.longMs
          easing.type: Easing.OutCubic
        }
      }
      Behavior on brightness {
        NumberAnimation {
          duration: Common.Config.motion.duration.longMs
          easing.type: Easing.OutCubic
        }
      }
    }

    Behavior on scale {
      NumberAnimation {
        duration: Common.Config.motion.duration.longMs
        easing.type: Easing.OutCubic
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: root.colors.surface
    opacity: root.startAnim ? 0.58 : 0.42

    Behavior on opacity {
      NumberAnimation {
        duration: Common.Config.motion.duration.medium
      }
    }
  }

  Item {
    id: contentWrap

    anchors.centerIn: parent
    width: Math.min(parent.width - 64, 540)
    implicitHeight: mainColumn.implicitHeight
    opacity: root.startAnim ? 1 : 0
    scale: root.startAnim ? 1 : 0.96

    Behavior on opacity {
      NumberAnimation {
        duration: Common.Config.motion.duration.longMs
        easing.type: Easing.OutCubic
      }
    }
    Behavior on scale {
      NumberAnimation {
        duration: Common.Config.motion.duration.longMs
        easing.type: Easing.OutCubic
      }
    }

    ColumnLayout {
      id: mainColumn

      anchors.fill: parent
      spacing: 18

      ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 2

        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: 8

          Text {
            text: {
              const hours = root.now.getHours() % 12 || 12;
              const minutes = String(root.now.getMinutes()).padStart(2, "0");
              return hours + ":" + minutes;
            }
            color: root.colors.on_surface
            font.pixelSize: 90
            font.family: Common.Config.fontFamily
            font.weight: Font.DemiBold
          }

          Text {
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 18
            text: root.now.getHours() >= 12 ? "PM" : "AM"
            color: root.colors.on_surface_variant
            font.pixelSize: Common.Config.type.titleSmall.size
            font.family: Common.Config.fontFamily
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4
          }
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          color: root.colors.on_surface_variant
          font.pixelSize: Common.Config.type.titleLarge.size
          font.family: root.mondDisplayFontFamily
          font.letterSpacing: 3.2
          text: Qt.formatDateTime(root.now, "dddd, dd MMMM").toUpperCase()
          transform: Translate {
            y: -12
          }
        }

        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: 12
          Layout.topMargin: 6
          Layout.bottomMargin: 2

          // Battery Tile
          StatusTile {
            readonly property var device: UPower.displayDevice
            readonly property int percentage: device ? Math.round(device.percentage * 100) : 0
            readonly property bool charging: device && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)

            active: true
            icon: {
              if (charging) return "󰂄";
              if (percentage <= 10) return "󰁺";
              if (percentage <= 20) return "󰁻";
              if (percentage <= 30) return "󰁼";
              if (percentage <= 40) return "󰁽";
              if (percentage <= 50) return "󰁾";
              if (percentage <= 60) return "󰁿";
              if (percentage <= 70) return "󰂀";
              if (percentage <= 80) return "󰂁";
              if (percentage <= 90) return "󰂂";
              return "󰁹";
            }
            text: percentage + "%"
            accentColor: charging ? root.colors.tertiary : (percentage < 20 ? root.colors.error : root.colors.primary)
            visible: !!device
          }

          // WiFi/Network Tile
          StatusTile {
            readonly property var dev: statusService.connectedDevice
            readonly property var wifiNetwork: statusService.connectedWifiNetwork
            readonly property bool connected: !!dev
            readonly property bool isWifi: dev && dev.type === DeviceType.Wifi
            readonly property int signal: wifiNetwork && isFinite(wifiNetwork.signalStrength) ? Math.round(wifiNetwork.signalStrength * 100) : 0

            active: connected
            icon: {
              if (!connected) return "󰖪";
              if (!isWifi) return "󰈀";
              if (signal < 20) return "󰤯";
              if (signal < 40) return "󰤟";
              if (signal < 60) return "󰤢";
              if (signal < 80) return "󰤥";
              return "󰤨";
            }
            text: {
              if (!connected) return "Offline";
              if (isWifi) return (wifiNetwork ? wifiNetwork.name : "") || "Connected";
              return "Ethernet";
            }
            accentColor: connected ? root.colors.primary : root.colors.on_surface_variant
          }

          // Bluetooth Tile
          StatusTile {
            readonly property bool bluetoothEnabled: !!(statusService.adapter && statusService.adapter.enabled)
            readonly property int connectedCount: statusService.bluetoothConnectedCount

            active: bluetoothEnabled
            icon: !bluetoothEnabled ? "󰂲" : (connectedCount > 0 ? "󰂱" : "󰂯")
            text: {
              if (!bluetoothEnabled) return "";
              if (connectedCount > 0) return connectedCount;
              return "On";
            }
            accentColor: bluetoothEnabled ? root.colors.primary : root.colors.on_surface_variant
            visible: !!statusService.adapter
          }
        }
      }

      MK.Card {
        id: loginContainer

        property real shakeOffset: 0

        Layout.fillWidth: true
        type: 1
        radius: 22
        backgroundColor: Qt.alpha(root.colors.surface_container_highest, 0.88)
        borderColor: Qt.alpha(root.colors.outline_variant, 0.82)
        borderWidth: 1
        implicitHeight: loginContent.implicitHeight + 40

        transform: Translate {
          x: loginContainer.shakeOffset
        }

        Rectangle {
          anchors.fill: parent
          radius: loginContainer.radius
          color: Qt.alpha(root.colors.surface, 0.04)
        }

        SequentialAnimation {
          id: shakeAnim

          NumberAnimation { target: loginContainer; property: "shakeOffset"; to: -9; duration: 45 }
          NumberAnimation { target: loginContainer; property: "shakeOffset"; to: 9; duration: 45 }
          NumberAnimation { target: loginContainer; property: "shakeOffset"; to: -5; duration: 45 }
          NumberAnimation { target: loginContainer; property: "shakeOffset"; to: 5; duration: 45 }
          NumberAnimation { target: loginContainer; property: "shakeOffset"; to: 0; duration: 45 }
        }

        ColumnLayout {
          id: loginContent

          anchors.fill: parent
          anchors.margins: 20
          spacing: 14

          RowLayout {
            Layout.fillWidth: true
            spacing: 14

            ClippingWrapperRectangle {
              Layout.preferredWidth: 48
              Layout.preferredHeight: 48
              radius: 24
              color: Qt.alpha(root.colors.primary_container, 0.78)
              border.width: 1
              border.color: Qt.alpha(root.colors.outline_variant, 0.75)

              Image {
                source: "file://" + root.profileImagePath
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                width: 48
                height: 48
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 3

              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.currentUser.toUpperCase()
                color: root.colors.on_surface
                font.family: root.mondDisplayFontFamily
                font.pixelSize: Common.Config.type.titleMedium.size
                font.letterSpacing: 2.2
                font.weight: Font.DemiBold
              }

              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.context.unlockInProgress ? "Checking credentials" : (root.screen ? root.screen.name : "Session")
                color: root.colors.on_surface_variant
                font.family: Common.Config.fontFamily
                font.pixelSize: Common.Config.type.bodyMedium.size
              }
            }

            LockButton {
              text: root.context.showPassword ? "Hide" : "Show"
              enabled: !root.context.unlockInProgress
              onClicked: root.context.showPassword = !root.context.showPassword
            }

          }

          RowLayout {
            id: inputRow

            Layout.fillWidth: true
            spacing: 10

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 44
              radius: 12
              color: Qt.alpha(root.colors.surface_container_low, 0.92)
              border.width: 1
              border.color: Qt.alpha(root.context.showFailure ? root.colors.error : root.colors.outline_variant, root.context.showFailure ? 0.85 : 0.68)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                spacing: 6

                Rectangle {
                  Layout.preferredWidth: 28
                  Layout.preferredHeight: 28
                  radius: 9
                  color: Qt.alpha(root.colors.secondary_container, 0.9)

                  Text {
                    anchors.centerIn: parent
                    text: "\uf023"
                    color: root.colors.on_secondary_container
                    font.family: Common.Config.iconFontFamily
                    font.pixelSize: 14
                  }
                }

                MK.TextField {
                  id: passField

                  Layout.fillWidth: true
                  placeholderText: root.context.unlockInProgress ? "Authenticating..." : (root.context.showFailure ? "Incorrect password" : "Password")
                  echoMode: root.context.showPassword ? TextInput.Normal : TextInput.Password
                  enabled: !root.context.unlockInProgress
                  selectByMouse: false
                  font.family: Common.Config.fontFamily
                  font.pixelSize: Common.Config.type.bodyLarge.size
                  color: root.colors.on_surface
                  placeholderTextColor: root.colors.on_surface_variant
                  inputMethodHints: Qt.ImhSensitiveData

                  background: Item {}

                  onTextChanged: {
                    root.context.currentText = text;
                    if (text.length > 0)
                      root.context.clearError();
                  }
                  onAccepted: root.context.tryUnlock()

                  Component.onCompleted: forceActiveFocus()
                }
              }
            }

            LockButton {
              Layout.preferredHeight: 44
              text: root.context.unlockInProgress ? "..." : "Unlock"
              filled: true
              buttonEnabled: !root.context.unlockInProgress && root.context.currentText.length > 0
              onClicked: root.context.tryUnlock()
            }
          }

          Text {
            Layout.fillWidth: true
            color: root.colors.error
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.bodySmall.size
            text: root.context.lastMessage.length > 0 ? root.context.lastMessage : "Authentication failed"
            visible: root.context.showFailure
            wrapMode: Text.WordWrap
          }
        }
      }

    }
  }

  Item {
    id: powerDock

    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 24
    anchors.bottomMargin: 24
    z: 5

    MK.Card {
      id: powerMenu

      anchors.right: powerFab.right
      anchors.bottom: powerFab.top
      anchors.bottomMargin: 12
      width: 228
      visible: opacity > 0.01
      opacity: root.powerMenuVisible ? 1 : 0
      scale: root.powerMenuVisible ? 1 : 0.96
      type: 1
      radius: 22
      backgroundColor: Qt.alpha(root.colors.surface_container_highest, 0.9)
      borderColor: Qt.alpha(root.colors.outline_variant, 0.82)
      borderWidth: 1
      implicitHeight: submenuColumn.implicitHeight + 28

      Behavior on opacity {
        NumberAnimation {
          duration: Common.Config.motion.duration.medium
          easing.type: Easing.OutCubic
        }
      }
      Behavior on scale {
        NumberAnimation {
          duration: Common.Config.motion.duration.medium
          easing.type: Easing.OutCubic
        }
      }

      ColumnLayout {
        id: submenuColumn

        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: "Power"
            color: root.colors.on_surface
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.titleMedium.size
            font.weight: Font.DemiBold
          }

          Item { Layout.fillWidth: true }

          Text {
            text: root.advancedPowerOptions ? "Advanced" : "Quick"
            color: root.colors.on_surface_variant
            font.family: Common.Config.fontFamily
            font.pixelSize: Common.Config.type.labelMedium.size
          }
        }

        LockButton {
          Layout.fillWidth: true
          text: "Suspend"
          onClicked: root.runPowerAction("suspend")
        }
        LockButton {
          Layout.fillWidth: true
          text: "Reboot"
          onClicked: root.runPowerAction("reboot")
        }
        LockButton {
          Layout.fillWidth: true
          text: "Power Off"
          danger: true
          onClicked: root.runPowerAction("poweroff")
        }

        Item {
          Layout.fillWidth: true
          visible: root.advancedPowerOptions
          implicitHeight: root.advancedPowerOptions ? advancedColumn.implicitHeight : 0

          ColumnLayout {
            id: advancedColumn

            anchors.fill: parent
            spacing: 8

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 1
              color: Qt.alpha(root.colors.outline_variant, 0.55)
            }

            LockButton {
              Layout.fillWidth: true
              text: "Hibernate"
              onClicked: root.runPowerAction("hibernate")
            }
            LockButton {
              Layout.fillWidth: true
              text: "Reboot to Windows"
              onClicked: root.runPowerAction("windows")
            }
            LockButton {
              Layout.fillWidth: true
              text: "Logout Hyprland"
              danger: true
              onClicked: root.runPowerAction("logout")
            }
          }
        }
      }
    }

    Rectangle {
      id: powerFab

      width: 46
      height: 46
      radius: 16
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      color: powerFabMouse.pressed
        ? Qt.alpha(root.colors.surface_container_highest, 0.98)
        : (powerFabMouse.containsMouse
          ? Qt.alpha(root.colors.surface_container_high, 0.95)
          : Qt.alpha(root.colors.surface_container_highest, 0.88))
      border.width: 1
      border.color: Qt.alpha(root.colors.outline_variant, 0.8)

      Text {
        anchors.centerIn: parent
        text: "\uf011"
        color: root.colors.error
        font.family: Common.Config.iconFontFamily
        font.pixelSize: 18
      }

      Behavior on color {
        ColorAnimation {
          duration: Common.Config.motion.duration.shortMs
        }
      }
      Behavior on border.color {
        ColorAnimation {
          duration: Common.Config.motion.duration.shortMs
        }
      }

      Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: powerFab.radius
        clip: true

        MK.HybridRipple {
          anchors.fill: parent
          color: root.colors.error
          pressX: powerFabMouse.pressX
          pressY: powerFabMouse.pressY
          pressed: powerFabMouse.pressed
          radius: powerFab.radius
          stateOpacity: 0
        }
      }

      MouseArea {
        id: powerFabMouse

        property real pressX: width / 2
        property real pressY: height / 2

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) {
          pressX = mouse.x;
          pressY = mouse.y;
        }
        onClicked: function(mouse) {
          const advanced = (mouse.modifiers & Qt.ShiftModifier) !== 0;
          root.togglePowerMenu(advanced);
        }
      }
    }
  }

  Shortcut {
    context: Qt.ApplicationShortcut
    enabled: true
    sequence: "Escape"
    onActivated: {
      if (root.powerMenuVisible) {
        root.powerMenuVisible = false;
        root.advancedPowerOptions = false;
      } else {
        root.clearPasswordField();
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  Process {
    id: wallpaperProcess

    running: false
    command: ["sh", "-lc", "awww query | cut -d: -f6"]
    stdout: StdioCollector {
      id: wallpaperOutput

      waitForEnd: true
      onStreamFinished: {
        const lines = wallpaperOutput.text.split("\n").map(function(line) {
          return line.trim();
        }).filter(function(line) {
          return line.length > 0;
        });
        root.wallpaperPath = lines.length > 0 ? lines[0] : "";
      }
    }
  }

  Connections {
    target: root.context

    function onFailed() {
      shakeAnim.restart();
      passField.forceActiveFocus();
    }
  }

  Component.onCompleted: {
    wallpaperProcess.running = true;
    root.startAnim = true;
  }

  Component.onDestruction: {
  }
}
