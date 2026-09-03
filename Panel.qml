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
  property string selectedServerId: ""
  readonly property var activeServer: Model.findServer(daemonStatus.servers, selectedServerId)

  readonly property bool hasServers: daemonStatus.count > 0
  readonly property string worstStatusState: daemonStatus.worstState

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: bar ? bar.accent : Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color dotColor: Model.statusColor(root.worstStatusState, {
    accent: root.accent,
    warning: "#facc15",
    urgent: root.urgent,
    dim: root.dim
  })

  readonly property string tipText: Model.tooltipText(root.daemonStatus)

  // Daemon communication process
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

  // One-shot process for sending action commands to the daemon
  Process {
    id: actionSocket
    running: false

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (data && data.trim().length > 0) {
          root.actionResult = data.trim()
          root.actionBusy = false
        }
      }
    }

    onExited: function() {
      root.actionBusy = false
    }
  }

  // Confirm dialog state
  property bool confirmVisible: false
  property string confirmMessage: ""
  property string pendingActionCmd: ""
  property bool actionBusy: false
  property string actionResult: ""

  function sendAction(jsonCmd) {
    actionSocket.command = ["sh", "-c",
      "echo '" + jsonCmd.replace(/'/g, "'\\''") + "' | nc -U " + root.socketPath]
    root.actionBusy = true
    root.actionResult = ""
    actionSocket.running = true
  }

  function requestServiceAction(serverId, serviceName, serviceType, action) {
    var cmd = Model.buildServiceActionCmd(serverId, serviceName, serviceType, action)
    root.confirmMessage = "Are you sure you want to " + action + " " + serviceName + "?"
    root.pendingActionCmd = cmd
    root.confirmVisible = true
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

  // Bar Widget item representing the pill mounted in the Omarchy bar
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
        root.refresh()
        root.toggle()
      }
    }
  }

  // Popout Panel
  KeyboardPanel {
    id: panel
    anchorItem: barWidget
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelContent.implicitHeight + Style.space(24), Style.space(560))

    Flickable {
      id: panelFlick
      anchors.fill: parent
      anchors.margins: Style.space(12)
      contentWidth: width
      contentHeight: panelContent.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      ColumnLayout {
        id: panelContent
        width: parent.width
        spacing: Style.space(10)

        // ==========================================
        // VIEW 1: SERVER LIST VIEW
        // ==========================================
        ColumnLayout {
          id: listView
          visible: root.selectedServerId === ""
          Layout.fillWidth: true
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
              spacing: Style.space(2)

              Text {
                text: "Servers"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.daemonStatus.connected
                  ? (root.daemonStatus.count + " SERVERS MONITORED")
                  : "DAEMON DISCONNECTED"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
              width: 28
              height: 28
              radius: 6
              color: refreshMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : "transparent"

              Text {
                anchors.centerIn: parent
                text: "↻"
                color: root.foreground
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true }

          // Disconnected or empty warning
          Rectangle {
            visible: !root.daemonStatus.connected || root.daemonStatus.count === 0
            Layout.fillWidth: true
            implicitHeight: emptyText.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: Qt.rgba(255, 255, 255, 0.04)

            Text {
              id: emptyText
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              text: !root.daemonStatus.connected
                ? "Omarchy Server daemon is unreachable.\nEnsure the daemon is running and socket exists."
                : "No servers configured in servers.yaml."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          // Server rows list
          Repeater {
            model: root.daemonStatus.servers

            Rectangle {
              id: serverRowCard
              Layout.fillWidth: true
              implicitHeight: serverRowLayout.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: rowHover.containsMouse ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.03)

              Behavior on color { ColorAnimation { duration: 120 } }

              RowLayout {
                id: serverRowLayout
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(10)

                Rectangle {
                  width: 10
                  height: 10
                  radius: 5
                  color: Model.statusColor(modelData.status, {
                    accent: root.accent,
                    warning: "#facc15",
                    urgent: root.urgent,
                    dim: root.dim
                  })
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(2)

                  Text {
                    text: modelData.name || modelData.id
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    text: modelData.host + (modelData.init_system ? " • " + modelData.init_system : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                // Metric pills preview
                RowLayout {
                  spacing: Style.space(6)
                  visible: !!modelData.metrics && !!modelData.metrics.cpu

                  Rectangle {
                    radius: 4
                    color: Qt.rgba(255, 255, 255, 0.06)
                    implicitWidth: cpuPillText.implicitWidth + Style.space(8)
                    implicitHeight: cpuPillText.implicitHeight + Style.space(4)

                    Text {
                      id: cpuPillText
                      anchors.centerIn: parent
                      text: "CPU " + Model.formatCpu(modelData.metrics)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.fontSize(10)
                    }
                  }

                  Rectangle {
                    radius: 4
                    color: Qt.rgba(255, 255, 255, 0.06)
                    implicitWidth: memPillText.implicitWidth + Style.space(8)
                    implicitHeight: memPillText.implicitHeight + Style.space(4)

                    Text {
                      id: memPillText
                      anchors.centerIn: parent
                      text: "MEM " + (modelData.metrics && modelData.metrics.memory ? modelData.metrics.memory.used_percent + "%" : "–")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.fontSize(10)
                    }
                  }
                }

                Text {
                  text: "›"
                  color: root.dim
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedServerId = modelData.id
                }
              }
            }
          }
        }

        // ==========================================
        // VIEW 2: SERVER DETAIL VIEW
        // ==========================================
        ColumnLayout {
          id: detailView
          visible: root.selectedServerId !== "" && root.activeServer !== null
          Layout.fillWidth: true
          spacing: Style.space(12)

          // Back button and header
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Rectangle {
              width: backLabel.implicitWidth + Style.space(12)
              height: 26
              radius: 6
              color: backHover.containsMouse ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.04)

              Text {
                id: backLabel
                anchors.centerIn: parent
                text: "‹ All Servers"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                id: backHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedServerId = ""
                }
              }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
              radius: 4
              color: Qt.rgba(255, 255, 255, 0.08)
              implicitWidth: statusBadge.implicitWidth + Style.space(10)
              implicitHeight: statusBadge.implicitHeight + Style.space(4)

              Text {
                id: statusBadge
                anchors.centerIn: parent
                text: root.activeServer ? root.activeServer.status.toUpperCase() : ""
                color: root.activeServer ? Model.statusColor(root.activeServer.status, {
                  accent: root.accent,
                  warning: "#facc15",
                  urgent: root.urgent,
                  dim: root.dim
                }) : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.fontSize(10)
                font.bold: true
              }
            }
          }

          // Server Identity Hero
          ColumnLayout {
            spacing: Style.space(2)

            Text {
              text: root.activeServer ? (root.activeServer.name || root.activeServer.id) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.activeServer ? (root.activeServer.host + " • Init: " + (root.activeServer.init_system || "unknown")) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PanelSeparator { Layout.fillWidth: true }

          // Metrics Section
          PanelSectionHeader {
            text: "HOST METRICS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // CPU metric card
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: cpuCol.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: Qt.rgba(255, 255, 255, 0.04)

            ColumnLayout {
              id: cpuCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              RowLayout {
                Layout.fillWidth: true
                Text { text: "CPU Usage"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.activeServer ? Model.formatCpu(root.activeServer.metrics) : "–"
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
                }
              }

              // Load averages subtext
              Text {
                text: "Load averages (1m, 5m, 15m): " + (root.activeServer ? Model.formatLoad(root.activeServer.metrics) : "–")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.fontSize(10)
              }
            }
          }

          // Memory metric card
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: memCol.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: Qt.rgba(255, 255, 255, 0.04)

            ColumnLayout {
              id: memCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              RowLayout {
                Layout.fillWidth: true
                Text { text: "Memory (RAM)"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.activeServer ? Model.formatMem(root.activeServer.metrics) : "–"
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
                }
              }
            }
          }

          // Disk metric card
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: diskCol.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: Qt.rgba(255, 255, 255, 0.04)

            ColumnLayout {
              id: diskCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              RowLayout {
                Layout.fillWidth: true
                Text { text: "Disk Usage (Root /)"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                  text: root.activeServer ? Model.formatDisk(root.activeServer.metrics) : "–"
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
                }
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true }

          // Services Section
          PanelSectionHeader {
            text: "SERVICES & CHECKS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // Services list
          Repeater {
            model: root.activeServer ? Model.serviceList(root.activeServer.checks) : []

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: srvRow.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: Qt.rgba(255, 255, 255, 0.03)

              RowLayout {
                id: srvRow
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                Rectangle {
                  width: 8
                  height: 8
                  radius: 4
                  color: Model.serviceStatusColor(modelData.status, {
                    accent: root.accent,
                    warning: "#facc15",
                    urgent: root.urgent,
                    dim: root.dim
                  })
                }

                Text {
                  text: modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Rectangle {
                  radius: 3
                  color: Qt.rgba(255, 255, 255, 0.06)
                  implicitWidth: typeText.implicitWidth + Style.space(6)
                  implicitHeight: typeText.implicitHeight + Style.space(2)

                  Text {
                    id: typeText
                    anchors.centerIn: parent
                    text: modelData.type
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.fontSize(9)
                  }
                }

                Item { Layout.fillWidth: true }

                Text {
                  text: modelData.status
                  color: Model.serviceStatusColor(modelData.status, {
                    accent: root.accent,
                    warning: "#facc15",
                    urgent: root.urgent,
                    dim: root.dim
                  })
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                // Restart action button
                Rectangle {
                  width: restartLabel.implicitWidth + Style.space(10)
                  height: 22
                  radius: 4
                  color: restartMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                  visible: modelData.status !== "skipped" && root.activeServer !== null

                  Text {
                    id: restartLabel
                    anchors.centerIn: parent
                    text: "restart"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.fontSize(9)
                    font.bold: true
                  }

                  MouseArea {
                    id: restartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.requestServiceAction(
                        root.selectedServerId,
                        modelData.name,
                        modelData.type,
                        "restart"
                      )
                    }
                  }
                }

                // Stop action button
                Rectangle {
                  width: stopLabel.implicitWidth + Style.space(10)
                  height: 22
                  radius: 4
                  color: stopMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.20) : Qt.rgba(239, 68, 68, 0.06)
                  visible: modelData.status === "running" && root.activeServer !== null

                  Text {
                    id: stopLabel
                    anchors.centerIn: parent
                    text: "stop"
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.fontSize(9)
                    font.bold: true
                  }

                  MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.requestServiceAction(
                        root.selectedServerId,
                        modelData.name,
                        modelData.type,
                        "stop"
                      )
                    }
                  }
                }
              }
            }
          }

          // Empty state for checks
          Text {
            visible: !root.activeServer || Model.serviceList(root.activeServer.checks).length === 0
            text: "No service checks configured for this server."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // Confirm dialog overlay — sits above the KeyboardPanel popup
  ConfirmDialog {
    id: confirmDialog
    anchors.fill: parent
    opened: root.confirmVisible
    message: root.confirmMessage
    cancelText: "Cancel"
    confirmText: "Confirm"
    foreground: root.foreground
    fontFamily: root.fontFamily

    onCanceled: {
      root.confirmVisible = false
      root.pendingActionCmd = ""
    }

    onConfirmed: {
      root.confirmVisible = false
      if (root.pendingActionCmd !== "") {
        root.sendAction(root.pendingActionCmd)
        root.pendingActionCmd = ""
        // Refresh server state after a short delay to pick up the new status
        Qt.callLater(function() {
          Qt.createQmlObject(
            'import QtQuick; Timer { interval: 3000; running: true; repeat: false; onTriggered: { destroy(); root.refresh() } }',
            root
          )
        })
      }
    }
  }
}
