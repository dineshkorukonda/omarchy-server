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
  readonly property string worstStatusState: daemonStatus.worstState

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color dotColor: Model.statusColor(root.worstStatusState, {
    accent: bar ? bar.accent : Color.accent,
    warning: "#facc15",
    urgent: root.urgent,
    dim: root.dim
  })

  readonly property string tipText: Model.tooltipText(root.daemonStatus)

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

  // Bar Widget item representing the pill on the bar
  Item {
    id: barWidget
    implicitWidth: pillLayout.implicitWidth + Style.space(8)
    implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

    RowLayout {
      id: pillLayout
      anchors.centerIn: parent
      spacing: Style.space(4)

      Rectangle {
        id: statusDot
        width: 8
        height: 8
        radius: 4
        color: root.dotColor

        Behavior on color {
          ColorAnimation { duration: 180 }
        }
      }

      Text {
        id: serverCountText
        text: Model.pillLabel(root.daemonStatus)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.fontSize(12)
        font.bold: true
      }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onEntered: {
        if (root.bar && typeof root.bar.showTooltip === "function") {
          root.bar.showTooltip(barWidget, root.tipText)
        }
      }

      onExited: {
        if (root.bar && typeof root.bar.hideTooltip === "function") {
          root.bar.hideTooltip(barWidget)
        }
      }

      onClicked: {
        if (root.controller && typeof root.controller.toggle === "function") {
          root.controller.toggle()
        }
      }
    }
  }
}
