const test = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

const RAW = [
  "resource=cpu",
  "some avg10=8.09 avg60=11.73 avg300=10.72 total=353547002275",
  "full avg10=0.00 avg60=0.00 avg300=0.00 total=0",
  "resource=memory",
  "some avg10=0.24 avg60=0.97 avg300=0.34 total=2636098969",
  "full avg10=0.10 avg60=0.20 avg300=0.30 total=1000",
  "resource=io",
  "some avg10=0.13 avg60=0.74 avg300=0.86 total=108092122460",
  "full avg10=0.01 avg60=0.02 avg300=0.03 total=500",
  ""
].join("\n")

function snapshot(at = 100000) {
  return Model.parseSnapshot(RAW, at)
}

test("clean strips markup, controls, bidi overrides, and tag characters", () => {
  assert.equal(Model.clean("<b>a\x00b\u202ec\u{e0001}</b>"), "babc/b")
})

test("clean caps pathological strings", () => {
  assert.equal(Model.clean("x".repeat(500), 64).length, 64)
})

test("parseMetric accepts the exact PSI shape", () => {
  assert.deepEqual(Model.parseMetric("some avg10=1.25 avg60=2 avg300=3 total=42"), {
    kind: "some",
    value: { avg10: 1.25, avg60: 2, avg300: 3, total: 42 }
  })
})

test("parseMetric refuses missing, extra, negative, and nonnumeric fields", () => {
  assert.equal(Model.parseMetric("some avg10=1 avg60=2 total=3"), null)
  assert.equal(Model.parseMetric("some avg10=1 avg60=2 avg300=3 total=4 extra=5"), null)
  assert.equal(Model.parseMetric("some avg10=-1 avg60=2 avg300=3 total=4"), null)
  assert.equal(Model.parseMetric("some avg10=x avg60=2 avg300=3 total=4"), null)
})

test("parseSnapshot maps all three kernel resources", () => {
  const parsed = snapshot(1234)
  assert.equal(parsed.valid, true)
  assert.equal(parsed.availableCount, 3)
  assert.equal(parsed.capturedAt, 1234)
  assert.equal(parsed.resources.cpu.some.avg10, 8.09)
  assert.equal(parsed.resources.memory.full.avg10, 0.1)
  assert.equal(parsed.resources.io.some.total, 108092122460)
})

test("parseSnapshot surfaces partial availability", () => {
  const parsed = Model.parseSnapshot("resource=cpu\n" + RAW.split("\n")[1] + "\nresource=io\nunavailable\n", 1)
  assert.equal(parsed.valid, true)
  assert.equal(parsed.availableCount, 1)
  assert.equal(parsed.error, "some pressure files unavailable")
  assert.equal(parsed.resources.io.available, false)
})

test("parseSnapshot returns a truthful unavailable state on empty or malformed input", () => {
  assert.equal(Model.parseSnapshot("", 1).valid, false)
  assert.equal(Model.parseSnapshot("resource=cpu\nnonsense", 1).valid, false)
  assert.equal(Model.parseSnapshot(null, 1).error, "pressure data unavailable")
})

test("parseSnapshot caps oversized reader output and surfaces truncation", () => {
  const parsed = Model.parseSnapshot(RAW + "x".repeat(Model.MAX_RAW_CHARS * 2), 1)
  assert.equal(parsed.truncated, true)
  assert.ok(parsed.availableCount > 0)
})

test("thresholds clamp and critical always exceeds warning", () => {
  assert.deepEqual(Model.clampThresholds(-10, 500), { warning: 5, critical: 90 })
  assert.deepEqual(Model.clampThresholds(20, 20), { warning: 20, critical: 21 })
  assert.deepEqual(Model.clampThresholds(50, 2), { warning: 50, critical: 51 })
})

test("severity classifies the exact warning and critical boundaries", () => {
  assert.equal(Model.severity(4.99, 5, 20), "normal")
  assert.equal(Model.severity(5, 5, 20), "warning")
  assert.equal(Model.severity(19.99, 5, 20), "warning")
  assert.equal(Model.severity(20, 5, 20), "critical")
})

test("worst resource follows avg10 partial stall, not utilization or full", () => {
  assert.equal(Model.selectedResource(snapshot(), "Worst"), "cpu")
  assert.equal(Model.selectedResource(snapshot(), "Memory"), "memory")
  assert.equal(Model.selectedResource(snapshot(), "I/O"), "io")
})

test("an unavailable preferred resource falls back to the worst available resource", () => {
  const parsed = Model.parseSnapshot("resource=cpu\n" + RAW.split("\n")[1], 1)
  assert.equal(Model.selectedResource(parsed, "Memory"), "cpu")
})

test("bar copy names the constrained resource and its stall percentage", () => {
  assert.equal(Model.pillText(snapshot(), "Worst"), "CPU 8.1% WAIT")
  assert.equal(Model.pillText(snapshot(), "Memory"), "MEM 0.2% WAIT")
  assert.equal(Model.pillText(Model.emptySnapshot(0), "Worst"), "PSI ?")
})

test("tooltip states measurement, window, severity, and age", () => {
  const text = Model.tooltipText(snapshot(1000), "Worst", 5, 20, 2000, "")
  assert.match(text, /CPU 8\.1% stalled \(10s\), warning/)
  assert.match(text, /sampled just now/)
})

test("diagnosis distinguishes partial from full memory stalls", () => {
  const parsed = snapshot()
  parsed.resources.memory.some.avg10 = 25
  parsed.resources.memory.full.avg10 = 0
  assert.match(Model.diagnosis("memory", parsed, 5, 20), /Some work is blocked/)
  parsed.resources.memory.full.avg10 = 8
  assert.match(Model.diagnosis("memory", parsed, 5, 20), /All active work/)
})

test("normal diagnoses do not claim a problem", () => {
  assert.match(Model.diagnosis("io", snapshot(), 5, 20), /not measurably/)
  assert.match(Model.diagnosis("cpu", snapshot(), 10, 20), /not spending meaningful time/)
})

test("history records a bounded projection rather than the full snapshot", () => {
  const point = Model.historyPoint(snapshot(1234))
  assert.deepEqual(Object.keys(point).sort(), ["at", "cpu", "cpuFull", "io", "ioFull", "memory", "memoryFull"].sort())
  assert.equal(point.cpu, 8.09)
  assert.equal(point.memoryFull, 0.1)
})

test("history sampling refuses points inside the 15-second cadence", () => {
  let rows = Model.addHistory([], snapshot(100000))
  rows = Model.addHistory(rows, snapshot(100000 + Model.HISTORY_SAMPLE_MS - 1))
  assert.equal(rows.length, 1)
  rows = Model.addHistory(rows, snapshot(100000 + Model.HISTORY_SAMPLE_MS))
  assert.equal(rows.length, 2)
})

test("history is hard-capped even when input exceeds the persistence bound", () => {
  const rows = []
  for (let i = 0; i < Model.MAX_HISTORY + 50; i++) {
    rows.push({ at: i + 1, cpu: 1, cpuFull: 0, memory: 2, memoryFull: 0, io: 3, ioFull: 0 })
  }
  const normalized = Model.normalizeHistory(rows)
  assert.equal(normalized.length, Model.MAX_HISTORY)
  assert.equal(normalized[0].at, 51)
})

test("history rejects malformed, empty, and out-of-order points", () => {
  const rows = Model.normalizeHistory([
    null,
    { at: 10, cpu: 1 },
    { at: 9, cpu: 2 },
    { at: "bad", cpu: 3 },
    { at: 20, cpu: null, memory: null, io: null }
  ])
  assert.equal(rows.length, 1)
  assert.equal(rows[0].at, 10)
})

test("state parser restores only bounded history and a known selection", () => {
  const parsed = Model.parseState(JSON.stringify({
    selected: "io",
    history: [{ at: 1, cpu: 1, memory: 2, io: 3 }]
  }))
  assert.equal(parsed.valid, true)
  assert.equal(parsed.selected, "io")
  assert.equal(parsed.history.length, 1)
  assert.equal(Model.parseState("not json").valid, false)
})

test("state parser refuses oversized persistence rather than parsing it", () => {
  assert.equal(Model.parseState("x".repeat(Model.MAX_STATE_CHARS + 1)).valid, false)
})

test("history windows map to the promised durations", () => {
  assert.equal(Model.windowMs("15 minutes"), 900000)
  assert.equal(Model.windowMs("1 hour"), 3600000)
  assert.equal(Model.windowMs("6 hours"), 21600000)
})

test("historySeries filters by window and downsamples with peak preservation", () => {
  const now = 1000000
  const rows = []
  for (let i = 0; i < 120; i++) {
    rows.push({ at: now - (119 - i) * 1000, cpu: i === 60 ? 80 : i % 10, cpuFull: 0, memory: 0, memoryFull: 0, io: 0, ioFull: 0 })
  }
  const series = Model.historySeries(rows, "cpu", "15 minutes", now, 24)
  assert.equal(series.length, 24)
  assert.equal(Math.max(...series.map((row) => row.value)), 80)
})

test("seriesStats reports current, average, peak, and denominator", () => {
  assert.deepEqual(Model.seriesStats([{ value: 1 }, { value: 2 }, { value: 9 }]), {
    current: 9,
    average: 4,
    peak: 9,
    samples: 3
  })
  assert.equal(Model.seriesStats([]).samples, 0)
})

test("poll interval accepts only the manifest choices", () => {
  assert.equal(Model.pollSeconds("2 seconds"), 2)
  assert.equal(Model.pollSeconds("5 seconds"), 5)
  assert.equal(Model.pollSeconds("10 seconds"), 10)
  assert.equal(Model.pollSeconds("30 seconds"), 30)
  assert.equal(Model.pollSeconds("surprise"), 5)
})
