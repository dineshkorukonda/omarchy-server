// Model.js - Helper functions and status parsing for omarchy-server

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()

  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()

    var servers = Array.isArray(parsed.servers) ? parsed.servers : []
    var summary = aggregateHealth(servers)
    var worst = worstState(servers)

    return {
      ok: parsed.status === "ok",
      connected: true,
      servers: servers,
      count: servers.length,
      worstState: worst,
      healthyCount: summary.healthy,
      degradedCount: summary.degraded,
      offlineCount: summary.offline,
      lastError: null,
      timestamp: parsed.timestamp || new Date().toISOString()
    }
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse server daemon status: " + e.message
    return failed
  }
}

function defaultStatus() {
  return {
    ok: false,
    connected: false,
    servers: [],
    count: 0,
    worstState: "disconnected",
    healthyCount: 0,
    degradedCount: 0,
    offlineCount: 0,
    lastError: null,
    timestamp: null
  }
}

function aggregateHealth(servers) {
  var healthy = 0
  var degraded = 0
  var offline = 0

  for (var i = 0; i < servers.length; i++) {
    var s = servers[i]
    var st = s ? String(s.status || "").toLowerCase() : ""

    if (st === "polling" || st === "ok" || st === "online") {
      healthy++
    } else if (st === "degraded" || st === "warning") {
      degraded++
    } else {
      offline++
    }
  }

  return {
    healthy: healthy,
    degraded: degraded,
    offline: offline
  }
}

function worstState(servers) {
  if (!Array.isArray(servers) || servers.length === 0) {
    return "empty"
  }

  var hasDegraded = false

  for (var i = 0; i < servers.length; i++) {
    var s = servers[i]
    var st = s ? String(s.status || "").toLowerCase() : ""

    if (
      st === "reconnecting" ||
      st === "offline" ||
      st === "error" ||
      st === "failed" ||
      st === "disconnected"
    ) {
      return "offline"
    }
    if (st === "degraded" || st === "warning") {
      hasDegraded = true
    }
  }

  if (hasDegraded) {
    return "degraded"
  }

  return "polling"
}

function statusColor(state, colors) {
  colors = colors || {}
  var st = String(state || "").toLowerCase()

  if (st === "polling" || st === "healthy" || st === "ok") {
    return colors.accent || colors.success || "#22c55e"
  }
  if (st === "degraded" || st === "warning") {
    return colors.warning || "#f59e0b"
  }
  if (
    st === "offline" ||
    st === "critical" ||
    st === "error" ||
    st === "reconnecting" ||
    st === "disconnected"
  ) {
    return colors.urgent || colors.danger || "#ef4444"
  }
  return colors.dim || "#9ca3af"
}

function pillLabel(statusObj) {
  if (!statusObj || !statusObj.connected) return "–"
  return String(statusObj.count || 0)
}

function tooltipText(statusObj) {
  if (!statusObj || !statusObj.connected) {
    return "Omarchy Server: Daemon unreachable"
  }
  if (statusObj.count === 0) {
    return "Omarchy Server: No servers configured"
  }

  if (statusObj.worstState === "polling") {
    return "Omarchy Server: All " + statusObj.count + " servers healthy"
  }

  var details = []
  if (statusObj.healthyCount > 0) details.push(statusObj.healthyCount + " healthy")
  if (statusObj.degradedCount > 0) details.push(statusObj.degradedCount + " degraded")
  if (statusObj.offlineCount > 0) details.push(statusObj.offlineCount + " offline")

  return "Omarchy Server: " + statusObj.count + " servers (" + details.join(", ") + ")"
}

function findServer(servers, serverId) {
  if (!Array.isArray(servers) || !serverId) return null
  for (var i = 0; i < servers.length; i++) {
    if (servers[i] && servers[i].id === serverId) {
      return servers[i]
    }
  }
  return null
}

function formatCpu(metrics, status) {
  if (!metrics || !metrics.cpu || typeof metrics.cpu.used_percent !== "number") {
    return status === "polling" ? "polling..." : "–"
  }
  return metrics.cpu.used_percent + "%"
}

function formatLoad(metrics, status) {
  if (!metrics || !metrics.cpu || typeof metrics.cpu.load_1 !== "number") {
    return status === "polling" ? "polling..." : "–"
  }
  return metrics.cpu.load_1 + ", " + metrics.cpu.load_5 + ", " + metrics.cpu.load_15
}

function formatMem(metrics, status) {
  if (!metrics || !metrics.memory || typeof metrics.memory.total_mb !== "number") {
    return status === "polling" ? "polling..." : "–"
  }
  var used = metrics.memory.used_mb
  var total = metrics.memory.total_mb
  var pct = metrics.memory.used_percent || Math.round((used / total) * 100)
  return used + " / " + total + " MB (" + pct + "%)"
}

function formatDisk(metrics, status) {
  if (!metrics || !metrics.disk || !metrics.disk.root) {
    return status === "polling" ? "polling..." : "–"
  }
  var root = metrics.disk.root
  return root.used + " / " + root.size + " (" + root.use_percent + "%)"
}

function serviceList(checksMap) {
  if (!checksMap || typeof checksMap !== "object") return []
  var list = []
  for (var key in checksMap) {
    if (Object.prototype.hasOwnProperty.call(checksMap, key)) {
      var item = checksMap[key]
      if (item) {
        list.push({
          name: item.name || key,
          type: item.type || "systemctl",
          status: item.status || "unknown"
        })
      }
    }
  }
  return list
}

function serviceStatusColor(status, colors) {
  colors = colors || {}
  var st = String(status || "").toLowerCase()

  if (st === "running" || st === "active") {
    return colors.accent || colors.success || "#22c55e"
  }
  if (st === "stopped" || st === "inactive" || st === "failed") {
    return colors.urgent || colors.danger || "#ef4444"
  }
  if (st === "skipped") {
    return colors.dim || "#9ca3af"
  }
  return colors.warning || "#f59e0b"
}

function buildServiceActionCmd(serverId, serviceName, serviceType, action) {
  return JSON.stringify({
    command: "service_action",
    server_id: serverId,
    service: serviceName,
    type: serviceType,
    action: action
  })
}

function buildGetLogsCmd(serverId, lines, unit) {
  var cmd = { command: "get_logs", server_id: serverId, lines: lines || 50 }
  if (unit) cmd.unit = unit
  return JSON.stringify(cmd)
}

function buildSshCommand(server) {
  if (!server) return []

  var args = ["ssh"]

  if (server.proxy_jump) {
    args.push("-J")
    args.push(server.proxy_jump)
  }

  if (server.user) {
    args.push("-l")
    args.push(server.user)
  }

  if (server.port && server.port !== 22) {
    args.push("-p")
    args.push(String(server.port))
  }

  args.push(server.host)
  return args
}

function buildAddServerCmd(serverData) {
  var payload = {
    id: serverData.id || serverData.host,
    name: serverData.name || serverData.id || serverData.host,
    host: serverData.host,
    port: parseInt(serverData.port, 10) || 22
  }

  if (serverData.user && serverData.user.trim().length > 0) {
    payload.user = serverData.user.trim()
  }

  if (serverData.proxy_jump && serverData.proxy_jump.trim().length > 0) {
    payload.proxy_jump = serverData.proxy_jump.trim()
  }

  if (Array.isArray(serverData.checks)) {
    payload.checks = serverData.checks
  }

  return JSON.stringify({
    command: "add_server",
    server: payload
  })
}

function buildRemoveServerCmd(serverId) {
  return JSON.stringify({
    command: "remove_server",
    server_id: serverId
  })
}

function buildPollNowCmd(serverId) {
  return JSON.stringify({
    command: "poll_now",
    server_id: serverId
  })
}

function buildPollAllCmd() {
  return JSON.stringify({
    command: "poll_all"
  })
}

function formatRelativeTime(isoString) {
  if (!isoString) return ""
  try {
    var diffMs = Date.now() - new Date(isoString).getTime()
    if (isNaN(diffMs) || diffMs < 0) return "just now"
    var secs = Math.floor(diffMs / 1000)
    if (secs < 5) return "just now"
    if (secs < 60) return secs + "s ago"
    var mins = Math.floor(secs / 60)
    if (mins < 60) return mins + "m ago"
    var hours = Math.floor(mins / 60)
    return hours + "h ago"
  } catch (e) {
    return ""
  }
}
