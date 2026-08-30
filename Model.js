// Pure Linux PSI model shared by Quickshell and the offline node suite.
// Keep this ES5-compatible: QML imports top-level functions and variables,
// while node sees the guarded module.exports at the bottom.

var RESOURCES = ["cpu", "memory", "io"]
var MAX_RAW_CHARS = 4096
var MAX_STATE_CHARS = 1000000
var MAX_HISTORY = 1440
var HISTORY_SAMPLE_MS = 15000

function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[<>]/g, "")
    .replace(/[\x00-\x1f\x7f]/g, "")
    .replace(/[\u202a-\u202e\u2066-\u2069]/g, "")
    .replace(/[\u{e0000}-\u{e007f}]/gu, "")
  var cap = max || 96
  return s.length > cap ? s.slice(0, cap) : s
}

function finiteNumber(value, fallback) {
  var n = Number(value)
  return isFinite(n) && n >= 0 ? n : fallback
}

function round(value, digits) {
  var scale = Math.pow(10, digits === undefined ? 1 : digits)
  return Math.round(finiteNumber(value, 0) * scale) / scale
}

function emptyMetric() {
  return { avg10: 0, avg60: 0, avg300: 0, total: 0 }
}

function emptyResource(name) {
  return { name: name, available: false, some: emptyMetric(), full: emptyMetric() }
}

function emptySnapshot(at) {
  return {
    valid: false,
    capturedAt: finiteNumber(at, 0),
    resources: {
      cpu: emptyResource("cpu"),
      memory: emptyResource("memory"),
      io: emptyResource("io")
    },
    availableCount: 0,
    truncated: false,
    error: "pressure data unavailable"
  }
}

function parseMetric(line) {
  var parts = String(line || "").trim().split(/\s+/)
  if (parts.length !== 5 || (parts[0] !== "some" && parts[0] !== "full")) return null
  var out = emptyMetric()
  var seen = {}
  for (var i = 1; i < parts.length; i++) {
    var pair = parts[i].split("=")
    if (pair.length !== 2 || !(pair[0] in out) || seen[pair[0]]) return null
    seen[pair[0]] = true
    var value = Number(pair[1])
    if (!isFinite(value) || value < 0) return null
    out[pair[0]] = pair[0] === "total" ? Math.floor(value) : round(value, 2)
  }
  return { kind: parts[0], value: out }
}

// Reader format is deliberately tiny and line-oriented:
//   resource=cpu
//   some avg10=... avg60=... avg300=... total=...
//   full ...
// The reader emits only three fixed procfs files and caps each read. The parser
// caps again so a broken helper cannot hand a long-lived shell a giant string.
function parseSnapshot(raw, capturedAt) {
  var text = String(raw || "")
  var snap = emptySnapshot(capturedAt)
  if (text.length === 0) return snap
  if (text.length > MAX_RAW_CHARS) {
    text = text.slice(0, MAX_RAW_CHARS)
    snap.truncated = true
  }
  var lines = text.split(/\r?\n/)
  var current = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.indexOf("resource=") === 0) {
      var candidate = line.slice(9)
      current = RESOURCES.indexOf(candidate) >= 0 ? candidate : ""
      continue
    }
    if (!current || !line) continue
    if (line === "unavailable") continue
    var parsed = parseMetric(line)
    if (!parsed) continue
    snap.resources[current][parsed.kind] = parsed.value
    if (parsed.kind === "some") snap.resources[current].available = true
  }
  for (var r = 0; r < RESOURCES.length; r++) {
    if (snap.resources[RESOURCES[r]].available) snap.availableCount++
  }
  snap.valid = snap.availableCount > 0
  snap.error = snap.valid
    ? (snap.availableCount < 3 ? "some pressure files unavailable" : "")
    : "pressure data unavailable"
  return snap
}

function clampThresholds(warning, critical) {
  var w = Math.max(1, Math.min(50, Math.round(finiteNumber(warning, 5))))
  var c = Math.max(2, Math.min(90, Math.round(finiteNumber(critical, 20))))
  if (c <= w) c = Math.min(90, w + 1)
  return { warning: w, critical: c }
}

function severity(value, warning, critical) {
  var t = clampThresholds(warning, critical)
  var n = finiteNumber(value, 0)
  if (n >= t.critical) return "critical"
  if (n >= t.warning) return "warning"
  return "normal"
}

function severityRank(level) {
  return level === "critical" ? 2 : level === "warning" ? 1 : 0
}

function resourceLabel(name) {
  if (name === "cpu") return "CPU"
  if (name === "memory") return "MEM"
  if (name === "io") return "I/O"
  return "PSI"
}

function selectedResource(snapshot, preference) {
  var requested = String(preference || "Worst").toLowerCase()
  if (requested === "memory") requested = "memory"
  else if (requested === "i/o" || requested === "io") requested = "io"
  else if (requested === "cpu") requested = "cpu"
  else requested = ""
  if (requested && snapshot && snapshot.resources[requested]
      && snapshot.resources[requested].available) return requested
  var best = ""
  var value = -1
  for (var i = 0; i < RESOURCES.length; i++) {
    var name = RESOURCES[i]
    var row = snapshot && snapshot.resources ? snapshot.resources[name] : null
    if (row && row.available && row.some.avg10 > value) {
      best = name
      value = row.some.avg10
    }
  }
  return best
}

function formatPercent(value) {
  var n = finiteNumber(value, 0)
  if (n >= 100) return "100%"
  if (n >= 10) return Math.round(n) + "%"
  return round(n, 1).toFixed(1) + "%"
}

function pillText(snapshot, preference) {
  if (!snapshot || !snapshot.valid) return "PSI ?"
  var name = selectedResource(snapshot, preference)
  if (!name) return "PSI ?"
  return resourceLabel(name) + " " + formatPercent(snapshot.resources[name].some.avg10) + " WAIT"
}

function ageText(timestamp, now) {
  var seconds = Math.max(0, Math.floor((finiteNumber(now, Date.now()) - finiteNumber(timestamp, 0)) / 1000))
  if (seconds < 5) return "just now"
  if (seconds < 60) return seconds + "s ago"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  return Math.floor(minutes / 60) + "h ago"
}

function tooltipText(snapshot, preference, warning, critical, now, error) {
  if (!snapshot || !snapshot.valid) return "Wait State: " + clean(error || "pressure data unavailable", 96)
  var name = selectedResource(snapshot, preference)
  var metric = snapshot.resources[name].some
  var level = severity(metric.avg10, warning, critical)
  return "Wait State: " + resourceLabel(name) + " " + formatPercent(metric.avg10)
    + " stalled (10s), " + level + " · sampled " + ageText(snapshot.capturedAt, now)
}

function diagnosis(name, snapshot, warning, critical) {
  if (!snapshot || !snapshot.resources || !snapshot.resources[name]
      || !snapshot.resources[name].available) return "This pressure source is unavailable."
  var row = snapshot.resources[name]
  var level = severity(row.some.avg10, warning, critical)
  if (level === "normal") {
    if (name === "cpu") return "Runnable work is not spending meaningful time waiting for CPU."
    if (name === "memory") return "Memory reclaim is not measurably stalling current work."
    return "Storage is not measurably delaying current work."
  }
  if (name === "cpu") {
    return level === "critical"
      ? "Runnable work is frequently waiting for CPU. Reduce competing work or inspect the process list."
      : "Some runnable work is waiting for CPU, but the machine is still making progress."
  }
  if (name === "memory") {
    if (row.full.avg10 >= finiteNumber(warning, 5))
      return "All active work is sometimes blocked on memory. This is consistent with reclaim or thrashing."
    return "Some work is blocked on memory reclaim. Check swap and memory-heavy processes before it worsens."
  }
  if (row.full.avg10 >= finiteNumber(warning, 5))
    return "All active work is sometimes waiting on I/O. Storage contention is affecting the whole machine."
  return "Some work is waiting on storage. Large writes, syncs, or a slow device may be competing."
}

function historyPoint(snapshot) {
  var point = { at: finiteNumber(snapshot && snapshot.capturedAt, 0) }
  for (var i = 0; i < RESOURCES.length; i++) {
    var name = RESOURCES[i]
    var row = snapshot && snapshot.resources ? snapshot.resources[name] : null
    point[name] = row && row.available ? round(row.some.avg10, 2) : null
    point[name + "Full"] = row && row.available ? round(row.full.avg10, 2) : null
  }
  return point
}

function validPoint(point) {
  if (!point || !isFinite(Number(point.at)) || Number(point.at) <= 0) return null
  var out = { at: Number(point.at) }
  var any = false
  for (var i = 0; i < RESOURCES.length; i++) {
    var name = RESOURCES[i]
    var value = point[name]
    var full = point[name + "Full"]
    out[name] = value === null || value === undefined ? null : round(finiteNumber(value, 0), 2)
    out[name + "Full"] = full === null || full === undefined ? null : round(finiteNumber(full, 0), 2)
    if (out[name] !== null) any = true
  }
  return any ? out : null
}

function normalizeHistory(rows) {
  if (!rows || !rows.length) return []
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var point = validPoint(rows[i])
    if (!point) continue
    if (out.length && point.at <= out[out.length - 1].at) continue
    out.push(point)
    if (out.length > MAX_HISTORY) out.shift()
  }
  return out
}

function addHistory(rows, snapshot) {
  var out = normalizeHistory(rows)
  if (!snapshot || !snapshot.valid) return out
  var point = historyPoint(snapshot)
  if (out.length && point.at - out[out.length - 1].at < HISTORY_SAMPLE_MS) return out
  out.push(point)
  return out.length > MAX_HISTORY ? out.slice(out.length - MAX_HISTORY) : out
}

function parseState(raw) {
  var text = String(raw || "")
  if (!text || text.length > MAX_STATE_CHARS) return { valid: false, history: [], selected: "cpu" }
  var data
  try { data = JSON.parse(text) } catch (e) { return { valid: false, history: [], selected: "cpu" } }
  if (!data || typeof data !== "object" || Array.isArray(data))
    return { valid: false, history: [], selected: "cpu" }
  var selected = RESOURCES.indexOf(data.selected) >= 0 ? data.selected : "cpu"
  return { valid: true, history: normalizeHistory(data.history), selected: selected }
}

function windowMs(label) {
  if (label === "15 minutes") return 15 * 60 * 1000
  if (label === "6 hours") return 6 * 60 * 60 * 1000
  return 60 * 60 * 1000
}

function historySeries(rows, name, label, now, maxPoints) {
  if (RESOURCES.indexOf(name) < 0) return []
  var history = normalizeHistory(rows)
  var cutoff = finiteNumber(now, Date.now()) - windowMs(label)
  var selected = []
  for (var i = 0; i < history.length; i++) {
    if (history[i].at >= cutoff && history[i][name] !== null)
      selected.push({ at: history[i].at, value: history[i][name], full: history[i][name + "Full"] })
  }
  var cap = Math.max(8, Math.min(96, Math.floor(finiteNumber(maxPoints, 48))))
  if (selected.length <= cap) return selected
  var out = []
  var step = selected.length / cap
  for (var p = 0; p < cap; p++) {
    var start = Math.floor(p * step)
    var end = Math.max(start + 1, Math.floor((p + 1) * step))
    var max = selected[start]
    for (var j = start + 1; j < end && j < selected.length; j++)
      if (selected[j].value > max.value) max = selected[j]
    out.push(max)
  }
  return out
}

function seriesStats(series) {
  if (!series || !series.length) return { current: 0, average: 0, peak: 0, samples: 0 }
  var total = 0
  var peak = 0
  for (var i = 0; i < series.length; i++) {
    total += finiteNumber(series[i].value, 0)
    peak = Math.max(peak, finiteNumber(series[i].value, 0))
  }
  return {
    current: round(series[series.length - 1].value, 2),
    average: round(total / series.length, 2),
    peak: round(peak, 2),
    samples: series.length
  }
}

function pollSeconds(label) {
  if (label === "2 seconds") return 2
  if (label === "10 seconds") return 10
  if (label === "30 seconds") return 30
  return 5
}

if (typeof module !== "undefined") {
  module.exports = {
    RESOURCES: RESOURCES,
    MAX_RAW_CHARS: MAX_RAW_CHARS,
    MAX_STATE_CHARS: MAX_STATE_CHARS,
    MAX_HISTORY: MAX_HISTORY,
    HISTORY_SAMPLE_MS: HISTORY_SAMPLE_MS,
    clean: clean,
    emptySnapshot: emptySnapshot,
    parseMetric: parseMetric,
    parseSnapshot: parseSnapshot,
    clampThresholds: clampThresholds,
    severity: severity,
    severityRank: severityRank,
    resourceLabel: resourceLabel,
    selectedResource: selectedResource,
    formatPercent: formatPercent,
    pillText: pillText,
    ageText: ageText,
    tooltipText: tooltipText,
    diagnosis: diagnosis,
    historyPoint: historyPoint,
    normalizeHistory: normalizeHistory,
    addHistory: addHistory,
    parseState: parseState,
    windowMs: windowMs,
    historySeries: historySeries,
    seriesStats: seriesStats,
    pollSeconds: pollSeconds
  }
}
