import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

FocusScope {
  id: root

  property string socketPath: "/tmp/omarchy_server.sock"
  property color foreground: "#e5e7eb"
  property color background: "#0a0e14"
  property color accent: "#38bdf8"
  property color dim: "#6b7280"
  property string fontFamily: "monospace"

  // Active server targets and concurrent tabs
  property var activeTabs: []
  property int currentTabIndex: 0
  readonly property var currentTab: activeTabs.length > currentTabIndex ? activeTabs[currentTabIndex] : null

  signal tabClosed(string serverId)

  implicitWidth: 640
  implicitHeight: 380

  function openSession(server) {
    if (!server || !server.id) return

    // If tab already exists, switch to it
    for (var i = 0; i < activeTabs.length; i++) {
      if (activeTabs[i].id === server.id) {
        currentTabIndex = i
        termInputScope.forceActiveFocus()
        return
      }
    }

    var newTab = {
      id: server.id,
      name: server.name || server.id,
      host: server.host,
      lines: ["Connecting to " + (server.name || server.id) + " (" + server.host + ")..."],
      connected: false
    }

    var updated = []
    for (var j = 0; j < activeTabs.length; j++) {
      updated.push(activeTabs[j])
    }
    updated.push(newTab)
    activeTabs = updated
    currentTabIndex = activeTabs.length - 1

    startBridgeProcess(newTab.id)
    termInputScope.forceActiveFocus()
  }

  function closeTab(index) {
    if (index < 0 || index >= activeTabs.length) return
    var target = activeTabs[index]

    if (termProcess.running && currentTabIndex === index) {
      termProcess.running = false
    }

    var updated = []
    for (var i = 0; i < activeTabs.length; i++) {
      if (i !== index) updated.push(activeTabs[i])
    }
    activeTabs = updated
    if (currentTabIndex >= activeTabs.length) {
      currentTabIndex = Math.max(0, activeTabs.length - 1)
    }

    if (activeTabs.length > 0) {
      startBridgeProcess(activeTabs[currentTabIndex].id)
    }

    tabClosed(target.id)
  }

  function startBridgeProcess(serverId) {
    if (termProcess.running) {
      termProcess.running = false
    }

    termProcess.targetServerId = serverId
    termProcess.command = ["nc", "-U", root.socketPath]
    termProcess.running = true
  }

  function appendOutput(text) {
    if (!root.currentTab) return

    var formatted = Model.ansiToHtml(text)
    var split = formatted.split("\n")

    var lines = root.currentTab.lines.slice()
    for (var i = 0; i < split.length; i++) {
      var item = split[i]
      if (item.length > 0) {
        lines.push(item)
      }
    }

    // Keep last 500 lines for scrollback
    if (lines.length > 500) {
      lines = lines.slice(lines.length - 500)
    }

    root.currentTab.lines = lines
    linesModel.clear()
    for (var k = 0; k < lines.length; k++) {
      linesModel.append({ content: lines[k] })
    }

    terminalListView.positionViewAtEnd()
  }

  function sendInput(bytes) {
    if (termProcess.running) {
      termProcess.write(bytes)
    }
  }

  function notifyResize() {
    if (!termProcess.running) return
    var charW = 8
    var charH = 16
    var cols = Math.max(20, Math.floor((terminalArea.width - 20) / charW))
    var rows = Math.max(5, Math.floor((terminalArea.height - 20) / charH))
    sendInput(Model.buildResizePtyCmd(cols, rows) + "\n")
  }

  ListModel {
    id: linesModel
  }

  Process {
    id: termProcess
    property string targetServerId: ""
    stdinEnabled: true

    onStarted: {
      var charW = 8
      var charH = 16
      var cols = Math.max(20, Math.floor((terminalArea.width - 20) / charW))
      var rows = Math.max(5, Math.floor((terminalArea.height - 20) / charH))

      write(Model.buildOpenTerminalCmd(targetServerId, cols, rows) + "\n")
      if (root.currentTab) {
        root.currentTab.connected = true
      }
    }

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (data && data.length > 0) {
          root.appendOutput(data)
        }
      }
    }

    onExited: function(code) {
      if (root.currentTab) {
        root.appendOutput("[Session closed: code " + code + "]")
        root.currentTab.connected = false
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    // Tab Bar (Concurrent Sessions)
    Rectangle {
      Layout.fillWidth: true
      height: 32
      color: Qt.rgba(0, 0, 0, 0.35)

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 4

        Repeater {
          model: root.activeTabs

          Rectangle {
            id: tabRect
            width: tabLabel.implicitWidth + 36
            height: 26
            radius: 4
            color: index === root.currentTabIndex
              ? Qt.rgba(255, 255, 255, 0.12)
              : tabMouse.containsMouse
                ? Qt.rgba(255, 255, 255, 0.06)
                : "transparent"

            RowLayout {
              anchors.centerIn: parent
              spacing: 6

              Text {
                id: tabLabel
                text: modelData.name
                color: index === root.currentTabIndex ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(10 / 12.0)
                font.bold: index === root.currentTabIndex
              }

              // Close Tab Button
              Text {
                text: "x"
                color: closeMouse.containsMouse ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.fontPx(10 / 12.0)

                MouseArea {
                  id: closeMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.closeTab(index)
                }
              }
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.currentTabIndex = index
                root.startBridgeProcess(modelData.id)
                termInputScope.forceActiveFocus()
              }
            }
          }
        }

        Item { Layout.fillWidth: true }
      }
    }

    // Terminal Screen
    Rectangle {
      id: terminalArea
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: root.background
      clip: true

      onWidthChanged: root.notifyResize()
      onHeightChanged: root.notifyResize()

      FocusScope {
        id: termInputScope
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var input = ""

          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            input = "\r"
          } else if (event.key === Qt.Key_Backspace) {
            input = "\x7f"
          } else if (event.key === Qt.Key_Tab) {
            input = "\t"
          } else if (event.key === Qt.Key_Escape) {
            input = "\x1b"
          } else if (event.key === Qt.Key_Up) {
            input = "\x1b[A"
          } else if (event.key === Qt.Key_Down) {
            input = "\x1b[B"
          } else if (event.key === Qt.Key_Right) {
            input = "\x1b[C"
          } else if (event.key === Qt.Key_Left) {
            input = "\x1b[D"
          } else if (event.key === Qt.Key_Home) {
            input = "\x1b[H"
          } else if (event.key === Qt.Key_End) {
            input = "\x1b[F"
          } else if (event.modifiers & Qt.ControlModifier) {
            if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
              input = String.fromCharCode(event.key - Qt.Key_A + 1)
            }
          } else if (event.text && event.text.length > 0) {
            input = event.text
          }

          if (input.length > 0) {
            root.sendInput(input)
            event.accepted = true
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: termInputScope.forceActiveFocus()
        }

        ListView {
          id: terminalListView
          anchors.fill: parent
          anchors.margins: 8
          model: linesModel
          spacing: 2
          clip: true

          delegate: Text {
            width: terminalListView.width
            text: model.content
            textFormat: Text.RichText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.fontPx(11 / 12.0)
            wrapMode: Text.WrapAnywhere
          }

          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }
        }
      }
    }
  }
}
