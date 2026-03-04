pragma Singleton

import QtQuick

QtObject {
  function corners(r) {
    const radius = Math.max(0, Number(r) || 0);
    return {
      radius: radius,
      topLeft: radius,
      topRight: radius,
      bottomLeft: radius,
      bottomRight: radius
    };
  }
}
