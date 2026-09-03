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
  property bool notificationsEnabled: setting("notificationsEnabled", true)
  property string terminalEmulator: setting("terminalEmulator", "auto")
  property int defaultLogLines: setting("logLines", 50)

  property var daemonStatus: Model.defaultStatus()
  property string selectedServerId: ""
  readonly property var activeServer: Model.findServer(daemonStatus.servers, selectedServerId)

  onActiveServerChanged: {
    if (root.selectedServerId !== "" && !root.activeServer) {
      root.selectedServerId = ""
    }
  }

  readonly property bool hasServers: daemonStatus.count > 0
  readonly property string worstStatusState: daemonStatus.worstState

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color dotColor: Model.statusColor(root.worstStatusState, {
    accent: root.accent,
    warning: "#facc15",
    urgent: root.urgent,
    dim: root.dim
  })

  readonly property string tipText: Model.tooltipText(root.daemonStatus)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  // Add Server Dialog state
  property bool addServerVisible: false

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

  function requestRemoveServer(serverId, serverName) {
    var cmd = Model.buildRemoveServerCmd(serverId)
    root.confirmMessage = "Remove server '" + (serverName || serverId) + "' from monitoring?"
    root.pendingActionCmd = cmd
    root.confirmVisible = true
  }

  // Log viewer state
  property bool logViewVisible: false
  property string logContent: ""
  property bool logBusy: false
  property int logLines: root.defaultLogLines
  property string logUnitFilter: ""

  // Process for fetching logs from the daemon
  Process {
    id: logSocket
    running: false

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (data && data.trim().length > 0) {
          try {
            var parsed = JSON.parse(data.trim())
            if (parsed && parsed.log !== undefined) {
              root.logContent = parsed.log || "(no output)"
            }
          } catch (e) {
            root.logContent = data.trim()
          }
          root.logBusy = false
        }
      }
    }

    onExited: function() {
      root.logBusy = false
    }
  }

  function requestLogs(serverId, lines, unit) {
    var cmd = Model.buildGetLogsCmd(serverId, lines || 50, unit || undefined)
    logSocket.command = ["sh", "-c",
      "echo '" + cmd.replace(/'/g, "'\\''") + "' | nc -U " + root.socketPath]
    root.logBusy = true
    root.logContent = ""
    logSocket.running = true
  }

  // Process for spawning a terminal emulator with SSH to the active server
  Process {
    id: sshTermProcess
    running: false
    onExited: { running = false }
  }

  function openSshTerminal(server) {
    if (!server) return

    var sshArgs = []

    if (server.proxy_jump) {
      sshArgs = sshArgs.concat(["-J", server.proxy_jump])
    }

    if (server.user) {
      sshArgs = sshArgs.concat(["-l", server.user])
    }

    if (server.port && server.port !== 22) {
      sshArgs = sshArgs.concat(["-p", String(server.port)])
    }

    sshArgs.push(server.host)

    var allTerminals = [
      { name: "foot", args: ["foot", "ssh"].concat(sshArgs) },
      { name: "kitty", args: ["kitty", "ssh"].concat(sshArgs) },
      { name: "xterm", args: ["xterm", "-e", "ssh"].concat(sshArgs) }
    ]

    // If a specific terminal is configured, try that first; otherwise use auto order
    var preferred = root.terminalEmulator
    var orderedTerminals = allTerminals

    if (preferred && preferred !== "auto") {
      var preferredList = allTerminals.filter(function(t) { return t.name === preferred })
      var rest = allTerminals.filter(function(t) { return t.name !== preferred })
      orderedTerminals = preferredList.concat(rest)
    }

    for (var i = 0; i < orderedTerminals.length; i++) {
      sshTermProcess.command = orderedTerminals[i].args
      sshTermProcess.running = true
      root.close()
      return
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
    if (socketReader.running) {
      socketReader.running = false
    }
    socketReader.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒋"
    tooltipText: root.tipText
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }

    Rectangle {
      id: statusDot
      width: 6
      height: 6
      radius: 3
      color: root.dotColor
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(4)
      anchors.rightMargin: Style.space(4)
      visible: true

      Behavior on color {
        ColorAnimation { duration: 180 }
      }
    }
  }

  // Popout Panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(
      root.addServerVisible
        ? Math.max(panelContent.implicitHeight + Style.space(24), Style.space(490))
        : (panelContent.implicitHeight + Style.space(24)),
      Style.space(620)
    )

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
              height: 28
              radius: 6
              implicitWidth: addServerLabel.implicitWidth + Style.space(16)
              color: addServerMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: "+"
                  color: root.foreground
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Text {
                  id: addServerLabel
                  text: "Add Server"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              MouseArea {
                id: addServerMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.addServerVisible = true
                }
              }
            }

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
                      font.pixelSize: Style.fontPx(10 / 12.0)
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
                      font.pixelSize: Style.fontPx(10 / 12.0)
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
                font.pixelSize: Style.fontPx(10 / 12.0)
                font.bold: true
              }
            }

            // Open SSH button
            Rectangle {
              width: sshLabel.implicitWidth + Style.space(12)
              height: 24
              radius: 4
              color: sshMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.14) : Qt.rgba(255, 255, 255, 0.06)

              Text {
                id: sshLabel
                anchors.centerIn: parent
                text: "Open SSH"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(10 / 12.0)
                font.bold: true
              }

              MouseArea {
                id: sshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openSshTerminal(root.activeServer)
              }
            }

            // Remove server button
            Rectangle {
              width: removeLabel.implicitWidth + Style.space(12)
              height: 24
              radius: 4
              color: removeMouse.containsMouse ? Qt.rgba(239, 68, 68, 0.25) : Qt.rgba(239, 68, 68, 0.12)

              Text {
                id: removeLabel
                anchors.centerIn: parent
                text: "Remove"
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(10 / 12.0)
                font.bold: true
              }

              MouseArea {
                id: removeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.activeServer) {
                    root.requestRemoveServer(root.activeServer.id, root.activeServer.name)
                  }
                }
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
              text: {
                if (!root.activeServer) return ""
                var s = root.activeServer
                var initStr = (s.status === "reconnecting" || s.status === "connecting")
                  ? "connecting..."
                  : (s.init_system && s.init_system !== "nil" ? s.init_system : "unknown")
                return s.host + " • Init: " + initStr
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Connection status alert banner
          Rectangle {
            visible: root.activeServer && (root.activeServer.status === "reconnecting" || root.activeServer.status === "error" || (root.activeServer.last_error && root.activeServer.last_error !== "null" && root.activeServer.last_error !== "nil"))
            Layout.fillWidth: true
            radius: 6
            color: Qt.rgba(239, 68, 68, 0.12)
            border.color: Qt.rgba(239, 68, 68, 0.35)
            border.width: 1
            implicitHeight: errCol.implicitHeight + Style.space(12)

            ColumnLayout {
              id: errCol
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(2)

              Text {
                text: "SSH connection failed" + (root.activeServer && root.activeServer.last_error && root.activeServer.last_error !== "null" && root.activeServer.last_error !== "nil" ? ": " + root.activeServer.last_error : "")
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(11 / 12.0)
                font.bold: true
                wrapMode: Text.Wrap
                Layout.fillWidth: true
              }

              Text {
                text: "Ensure your SSH key (~/.ssh/id_ed25519.pub) is authorized on the remote host."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(10 / 12.0)
                wrapMode: Text.Wrap
                Layout.fillWidth: true
              }
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
                font.pixelSize: Style.fontPx(10 / 12.0)
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
                    font.pixelSize: Style.fontPx(9 / 12.0)
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
                    font.pixelSize: Style.fontPx(9 / 12.0)
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
                    font.pixelSize: Style.fontPx(9 / 12.0)
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

          PanelSeparator { Layout.fillWidth: true }

          // Log viewer section
          RowLayout {
            Layout.fillWidth: true

            PanelSectionHeader {
              text: "LOGS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item { Layout.fillWidth: true }

            // Line count selector
            Repeater {
              model: [50, 100, 200]

              Rectangle {
                required property int modelData
                width: lineCountLabel.implicitWidth + Style.space(8)
                height: 20
                radius: 3
                color: root.logLines === modelData
                  ? Qt.rgba(255, 255, 255, 0.12)
                  : Qt.rgba(255, 255, 255, 0.04)

                Text {
                  id: lineCountLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: root.logLines === parent.modelData ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.fontPx(9 / 12.0)
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.logLines = parent.modelData
                }
              }
            }

            Rectangle {
              width: viewLogsLabel.implicitWidth + Style.space(12)
              height: 24
              radius: 4
              color: viewLogsMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.14) : Qt.rgba(255, 255, 255, 0.06)

              Text {
                id: viewLogsLabel
                anchors.centerIn: parent
                text: root.logBusy ? "loading..." : "load logs"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(10 / 12.0)
                font.bold: true
              }

              MouseArea {
                id: viewLogsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                enabled: !root.logBusy && root.activeServer !== null
                onClicked: {
                  root.requestLogs(root.selectedServerId, root.logLines)
                }
              }
            }
          }

          // Log output area
          Rectangle {
            visible: root.logContent !== "" || root.logBusy
            Layout.fillWidth: true
            implicitHeight: Math.min(logText.implicitHeight + Style.space(16), Style.space(200))
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.30)
            clip: true

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              contentWidth: width
              contentHeight: logText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Text {
                id: logText
                width: parent.width
                text: root.logBusy ? "Fetching logs..." : root.logContent
                color: root.logBusy ? root.dim : Qt.rgba(200, 255, 200, 0.85)
                font.family: "monospace"
                font.pixelSize: Style.fontPx(10 / 12.0)
                wrapMode: Text.WrapAnywhere
              }
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
          var cmdStr = root.pendingActionCmd
          root.sendAction(cmdStr)
          root.pendingActionCmd = ""
          try {
            var parsed = JSON.parse(cmdStr)
            if (parsed && parsed.command === "remove_server") {
              root.selectedServerId = ""
            }
          } catch (e) {}
          root.refresh()
          // Refresh server state after a short delay to pick up the new status
          Qt.callLater(function() {
            Qt.createQmlObject(
              'import QtQuick; Timer { interval: 800; running: true; repeat: false; onTriggered: { destroy(); root.refresh() } }',
              root
            )
          })
        }
      }
    }

    // Add Server Dialog Overlay
    Rectangle {
      id: addServerOverlay
      anchors.fill: parent
      visible: root.addServerVisible
      color: Qt.rgba(0, 0, 0, 0.75)
      z: 100

      // Click outside to dismiss
      MouseArea {
        anchors.fill: parent
        onClicked: {
          root.addServerVisible = false
        }
      }

      Rectangle {
        id: addServerCard
        width: Math.min(parent.width - Style.space(20), Style.space(400))
        height: Math.min(parent.height - Style.space(20), addServerLayout.implicitHeight + Style.space(28))
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.background
        border.color: Qt.rgba(255, 255, 255, 0.15)
        border.width: 1
        clip: true

        // Prevent clicks inside card from dismissing
        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        Flickable {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          contentWidth: width
          contentHeight: addServerLayout.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          ColumnLayout {
            id: addServerLayout
            width: parent.width
            spacing: Style.space(10)

          // Title
          RowLayout {
            Layout.fillWidth: true
            Text {
              text: "Add Server"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
              width: 20
              height: 20
              radius: 4
              color: closeMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.15) : "transparent"
              Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.dim
                font.pixelSize: Style.fontPx(10 / 12.0)
              }
              MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.addServerVisible = false }
              }
            }
          }

          Text {
            text: "Connects via SSH using keys in ~/.ssh."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          PanelSeparator { Layout.fillWidth: true }

          // Host / IP
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              text: "Server Host / IP *"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.fontPx(11 / 12.0)
              font.bold: true
            }
            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 6
              color: Qt.rgba(255, 255, 255, 0.06)
              border.color: hostInput.activeFocus ? root.accent : Qt.rgba(255, 255, 255, 0.12)
              border.width: 1

              TextInput {
                id: hostInput
                anchors.fill: parent
                anchors.margins: Style.space(6)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                Text {
                  text: "e.g. 192.168.1.100 or myserver.com"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  visible: !hostInput.text && !hostInput.activeFocus
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // Server Display Name
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              text: "Display Name (optional)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.fontPx(11 / 12.0)
              font.bold: true
            }
            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 6
              color: Qt.rgba(255, 255, 255, 0.06)
              border.color: nameInput.activeFocus ? root.accent : Qt.rgba(255, 255, 255, 0.12)
              border.width: 1

              TextInput {
                id: nameInput
                anchors.fill: parent
                anchors.margins: Style.space(6)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                Text {
                  text: "e.g. Production Web"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  visible: !nameInput.text && !nameInput.activeFocus
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // Row for User and Port
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                text: "SSH User"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(11 / 12.0)
                font.bold: true
              }
              Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: 6
                color: Qt.rgba(255, 255, 255, 0.06)
                border.color: userInput.activeFocus ? root.accent : Qt.rgba(255, 255, 255, 0.12)
                border.width: 1

                TextInput {
                  id: userInput
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  verticalAlignment: TextInput.AlignVCenter
                  clip: true
                  Text {
                    text: "root / deploy"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    visible: !userInput.text && !userInput.activeFocus
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
            }

            ColumnLayout {
              width: 80
              spacing: Style.space(2)
              Text {
                text: "Port"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(11 / 12.0)
                font.bold: true
              }
              Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: 6
                color: Qt.rgba(255, 255, 255, 0.06)
                border.color: portInput.activeFocus ? root.accent : Qt.rgba(255, 255, 255, 0.12)
                border.width: 1

                TextInput {
                  id: portInput
                  text: "22"
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  verticalAlignment: TextInput.AlignVCenter
                  clip: true
                }
              }
            }
          }

          // ProxyJump / Bastion (optional)
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              text: "ProxyJump / Bastion (optional)"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.fontPx(11 / 12.0)
              font.bold: true
            }
            Rectangle {
              Layout.fillWidth: true
              height: 32
              radius: 6
              color: Qt.rgba(255, 255, 255, 0.06)
              border.color: jumpInput.activeFocus ? root.accent : Qt.rgba(255, 255, 255, 0.12)
              border.width: 1

              TextInput {
                id: jumpInput
                anchors.fill: parent
                anchors.margins: Style.space(6)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                Text {
                  text: "e.g. jump.example.com"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  visible: !jumpInput.text && !jumpInput.activeFocus
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // Action Buttons
          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(8)
            spacing: Style.space(8)

            Item { Layout.fillWidth: true }

            // Cancel
            Rectangle {
              width: cancelLabel.implicitWidth + Style.space(20)
              height: 32
              radius: 6
              color: cancelMouse.containsMouse ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)

              Text {
                id: cancelLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(11 / 12.0)
                font.bold: true
              }

              MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.addServerVisible = false }
              }
            }

            // Save & Connect
            Rectangle {
              width: saveLabel.implicitWidth + Style.space(24)
              height: 32
              radius: 6
              color: hostInput.text.trim() === ""
                ? Qt.rgba(255, 255, 255, 0.05)
                : (saveMouse.containsMouse ? Qt.lighter(root.accent, 1.1) : root.accent)

              Text {
                id: saveLabel
                anchors.centerIn: parent
                text: "Save & Connect"
                color: hostInput.text.trim() === "" ? root.dim : "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(11 / 12.0)
                font.bold: true
              }

              MouseArea {
                id: saveMouse
                anchors.fill: parent
                hoverEnabled: hostInput.text.trim() !== ""
                cursorShape: hostInput.text.trim() !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  var host = hostInput.text.trim()
                  if (host === "") return

                  var sData = {
                    host: host,
                    name: nameInput.text.trim() || host,
                    id: nameInput.text.trim() ? nameInput.text.trim().toLowerCase().replace(/[^a-z0-9_-]/g, "-") : host,
                    user: userInput.text.trim() || undefined,
                    port: parseInt(portInput.text.trim(), 10) || 22,
                    proxy_jump: jumpInput.text.trim() || undefined
                  }

                  var cmd = Model.buildAddServerCmd(sData)
                  root.sendAction(cmd)
                  root.addServerVisible = false

                  // Clear inputs
                  hostInput.text = ""
                  nameInput.text = ""
                  userInput.text = ""
                  jumpInput.text = ""
                  portInput.text = "22"

                  // Refresh after short delay
                  Qt.callLater(function() {
                    Qt.createQmlObject(
                      'import QtQuick; Timer { interval: 1500; running: true; repeat: false; onTriggered: { destroy(); root.refresh() } }',
                      root
                    )
                  })
                }
              }
            }
          }
        }
      }
    }
  }
}
}
