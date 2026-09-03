// Model.js - Helper functions and status parsing for omarchy-server

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()

  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return defaultStatus()

    var servers = Array.isArray(parsed.servers) ? parsed.servers : []
    var summary = aggregateHealth(servers)

    return {
      ok: parsed.status === "ok",
      connected: true,
      servers: servers,
      count: servers.length,
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

function overallHealth(statusObj) {
  if (!statusObj || !statusObj.connected || statusObj.count === 0) {
    return "offline"
  }
  if (statusObj.offlineCount > 0) {
    return "critical"
  }
  if (statusObj.degradedCount > 0) {
    return "degraded"
  }
  return "healthy"
}

function statusColor(status, colors) {
  var st = String(status || "").toLowerCase()
  if (st === "healthy" || st === "polling" || st === "ok" || st === "online") {
    return colors && colors.success ? colors.success : "#4ade80"
  }
  if (st === "degraded" || st === "warning") {
    return colors && colors.warning ? colors.warning : "#facc15"
  }
  return colors && colors.urgent ? colors.urgent : "#f87171"
}
