import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import "./Label.qml"
import "../theme"

Item {
  id: root
  property string icon: "󰖪"
  property string tooltip: "Disconnected"
  property string activeDevice: ""
  property string connectionName: ""
  property string connectionType: ""
  property string ip: ""
  property string gateway: ""
  property string ssid: ""
  property string freq: ""
  property string rate: ""
  property int signal: 0

  implicitHeight: label.implicitHeight
  implicitWidth: label.implicitWidth

  function wifiIcon(signal) {
    const icons = [ "󰤯", "󰤟", "󰤢", "󰤥", "󰤨" ];
    if (signal === null || signal === undefined)
      return icons[0];
    const idx = Math.min(icons.length - 1, Math.max(0, Math.round((signal / 100) * (icons.length - 1))));
    return icons[idx];
  }

  Timer {
    id: pollTimer
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusProc.running = true
  }

  Process {
    id: statusProc
    command: [ "sh", "-c",
               "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION,SIGNAL dev status || true" ]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = (this.text || "").trim().split(/\\n/).filter(l => l);
        const active = lines.find(l => l.split(':')[2] === "connected");
        if (!active) {
          root.icon = "󰖪";
          root.tooltip = "Disconnected";
          root.activeDevice = "";
          root.connectionName = "";
          root.connectionType = "";
          root.ssid = "";
          root.ip = "";
          root.gateway = "";
          detailProc.running = false;
          return;
        }
        const parts = active.split(':');
        const device = parts[0];
        const type = parts[1];
        const name = parts[3];
        const sig = parseInt(parts[4], 10);

        root.activeDevice = device;
        root.connectionType = type;
        root.connectionName = name || "";
        root.signal = isNaN(sig) ? 0 : sig;

        if (type === "wifi") {
          root.icon = wifiIcon(root.signal);
          root.tooltip = `${root.connectionName || "Wi-Fi"} (${root.signal || 0}%)`;
        } else {
          root.icon = "󰈀";
          root.tooltip = root.connectionName || "Ethernet";
        }
        detailProc.running = false;
        detailProc.running = !!root.activeDevice;
      }
    }
  }

  function tooltipText() {
    if (!root.activeDevice)
      return "Disconnected";
    const lines = [];
    const title = root.connectionName || root.ssid || (root.connectionType === "ethernet" ? "Ethernet" : "Wi-Fi");
    const gw = root.gateway || "";
    lines.push(gw ? `${title} (${gw})` : title);
    lines.push(`IP: ${root.ip || "Unknown"}`);
    if (root.connectionType === "wifi") {
      lines.push(`Signal strength: ${root.signal || 0}%`);
      if (root.freq) {
        const freqNum = parseFloat(root.freq);
        const freqGHz = isNaN(freqNum) ? "" : (freqNum / 1000).toFixed(1);
        if (freqGHz)
          lines.push(`Frequency: ${freqGHz} GHz`);
      }
      if (root.rate)
        lines.push(`Speed: ${root.rate}`);
    }
    return lines.join("\\n");
  }

  Process {
    id: detailProc
    running: false
    command: [ "sh", "-c", `iface="${root.activeDevice}"; if [ -z "$iface" ]; then exit 0; fi;
ip=$(nmcli -t -f IP4.ADDRESS dev show "$iface" 2>/dev/null | head -n1 | cut -d: -f2-);
gw=$(nmcli -t -f IP4.GATEWAY dev show "$iface" 2>/dev/null | head -n1 | cut -d: -f2-);
wifi=$(nmcli -t -f ACTIVE,SSID,DEVICE,FREQ,RATE,SIGNAL dev wifi list 2>/dev/null | grep "^yes:.*:$iface:" | head -n1);
ssid=$(printf "%s" "$wifi" | cut -d: -f2);
freq=$(printf "%s" "$wifi" | cut -d: -f4);
rate=$(printf "%s" "$wifi" | cut -d: -f5);
sig=$(printf "%s" "$wifi" | cut -d: -f6);
printf 'ip:%s\\ngateway:%s\\nssid:%s\\nfreq:%s\\nrate:%s\\nsignal:%s\\n' "$ip" "$gw" "$ssid" "$freq" "$rate" "$sig";
` ]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = (this.text || "").split(/\\n/).filter(Boolean);
        const parsed = {};
        lines.forEach(line => {
          const idx = line.indexOf(":");
          if (idx > -1)
            parsed[line.slice(0, idx)] = line.slice(idx + 1);
        });
        root.ip = parsed.ip || "";
        root.gateway = parsed.gateway || "";
        root.ssid = parsed.ssid || root.connectionName;
        root.freq = parsed.freq || "";
        root.rate = parsed.rate || "";
        const sig = parseInt(parsed.signal, 10);
        root.signal = isNaN(sig) ? 0 : sig;
        root.tooltip = tooltipText();
      }
    }
  }

  Label {
    id: label
    text: icon
    color: Theme.colors.flamingo
    ToolTip.visible: mouseArea.containsMouse
    ToolTip.text: tooltip
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    onClicked: Quickshell.execDetached({
      command: [ "runapp", "kitty", "-o", "tab_bar_style=hidden", "--class", "impala", "-e", "impala" ],
    })
  }
}
