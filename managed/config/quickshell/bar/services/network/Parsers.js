.pragma library

function findStatusLines(lines) {
  let wifiLine = "";
  let ethernetLine = "";
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].indexOf(":wifi:") > 0)
      wifiLine = lines[i];
    else if (lines[i].indexOf(":ethernet:") > 0)
      ethernetLine = lines[i];
  }
  return { wifiLine, ethernetLine };
}

function parseWifiSignal(lines) {
  let signalValue = 0;
  let ssidValue = "";
  let frequencyValue = 0;
  for (let i = 0; i < lines.length; i++) {
    const parts = lines[i].split(":");
    if (parts[0] === "yes") {
      signalValue = parseInt(parts[1] || "0", 10);
      ssidValue = parts[2] || "";
      frequencyValue = parseInt(parts[3] || "0", 10);
      break;
    }
  }
  return {
    signalPercent: isNaN(signalValue) ? 0 : signalValue,
    ssid: ssidValue,
    frequencyMhz: isNaN(frequencyValue) ? 0 : frequencyValue
  };
}

function parseIpDetails(lines) {
  let ipValue = "";
  let gatewayValue = "";
  for (let i = 0; i < lines.length; i++) {
    const parts = lines[i].split(":");
    const key = parts[0];
    const value = parts.slice(1).join(":");
    if (key.indexOf("IP4.ADDRESS") === 0 && !ipValue)
      ipValue = value;
    else if (key === "IP4.GATEWAY")
      gatewayValue = value;
  }
  return { ipAddress: ipValue, gateway: gatewayValue };
}

function parseTrafficBytes(lines) {
  if (lines.length < 2)
    return { valid: false, rxBytes: NaN, txBytes: NaN };
  const rxBytes = parseFloat(lines[0]);
  const txBytes = parseFloat(lines[1]);
  if (!isFinite(rxBytes) || !isFinite(txBytes))
    return { valid: false, rxBytes: NaN, txBytes: NaN };
  return { valid: true, rxBytes, txBytes };
}
