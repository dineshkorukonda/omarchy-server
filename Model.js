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
