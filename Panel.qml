import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy-server"
  ipcTarget: "omarchy-server"
  manageIpc: false

  property string socketPath: setting("socketPath", "/tmp/omarchy_server.sock")
  property int refreshIntervalSec: setting("refreshIntervalSec", 5)

  property var daemonStatus: Model.defaultStatus()
  readonly property bool hasServers: daemonStatus.count > 0
  readonly property string overallState: Model.overallHealth(daemonStatus)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Process {
    id: socketReader
    command: ["nc", "-U", root.socketPath]
    running: false

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (data && data.trim().length > 0) {
          root.daemonStatus = Model.parseStatus(data)
        }
      }
    }

    onExited: function(exitCode) {
      if (exitCode !== 0 && !root.daemonStatus.connected) {
        root.daemonStatus = Model.defaultStatus()
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!socketReader.running) {
        socketReader.running = true
      }
    }
  }

  function refresh() {
    if (!socketReader.running) {
      socketReader.running = true
    }
  }

  Item {
    id: barWidget
    implicitWidth: pillLayout.implicitWidth
    implicitHeight: pillLayout.implicitHeight

    RowLayout {
      id: pillLayout
      anchors.fill: parent
      spacing: Style.space(2)

      Rectangle {
        id: statusDot
        width: 8
        height: 8
        radius: 4
        color: Model.statusColor(root.overallState, {
          success: Color.accent || "#4ade80",
          warning: "#facc15",
          urgent: root.urgent
        })
      }

      Text {
        id: serverCountText
        text: root.daemonStatus.count > 0 ? root.daemonStatus.count.toString() : "–"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.fontSize(12)
        font.bold: true
      }
    }
  }
}
