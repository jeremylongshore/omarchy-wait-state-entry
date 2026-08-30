const test = require("node:test")
const assert = require("node:assert/strict")
const crypto = require("node:crypto")
const Model = require("../Model.js")

function point(at, values = {}) {
  return Object.assign({
    at, cpu: 1, cpuFull: 0, memory: 2, memoryFull: 0.1, io: 3, ioFull: 0.2
  }, values)
}

test("presentation helpers pin every severity, label, percentage, and age boundary", () => {
  assert.deepEqual(["normal", "warning", "critical", "other"].map(Model.severityRank), [0, 1, 2, 0])
  assert.deepEqual(["cpu", "memory", "io", "bad"].map(Model.resourceLabel), ["CPU", "MEM", "I/O", "PSI"])
  assert.deepEqual([0, 9.94, 10, 99.6, 100, 1000].map(Model.formatPercent),
    ["0.0%", "9.9%", "10%", "100%", "100%", "100%"])
  const now = 10 * 60 * 60 * 1000
  assert.deepEqual([now, now - 4000, now - 5000, now - 59000, now - 60000,
    now - 59 * 60000, now - 60 * 60000].map(at => Model.ageText(at, now)),
  ["just now", "just now", "5s ago", "59s ago", "1m ago", "59m ago", "1h ago"])
})

test("metric parsing refuses duplicate and missing field identities", () => {
  assert.equal(Model.parseMetric("some avg10=1 avg10=2 avg300=3 total=4"), null)
  assert.equal(Model.parseMetric("full avg10=1 avg60=2 avg300=3 total=4").kind, "full")
  assert.equal(Model.parseMetric("other avg10=1 avg60=2 avg300=3 total=4"), null)
})

test("snapshot parsing ignores unknown resources and full-only fragments", () => {
  const parsed = Model.parseSnapshot([
    "resource=network",
    "some avg10=99 avg60=99 avg300=99 total=99",
    "resource=cpu",
    "full avg10=1 avg60=1 avg300=1 total=1"
  ].join("\n"), 44)
  assert.equal(parsed.valid, false)
  assert.equal(parsed.availableCount, 0)
  assert.equal(parsed.capturedAt, 44)
})

test("resource selection and pills fail closed on absent rows", () => {
  assert.equal(Model.selectedResource(null, "Worst"), "")
  assert.equal(Model.selectedResource({ resources: {} }, "Memory"), "")
  assert.equal(Model.pillText({ valid: true, resources: {} }, "Worst"), "PSI ?")
})

test("diagnosis covers unavailable, CPU, memory, and IO warning paths", () => {
  const snapshot = Model.emptySnapshot(1)
  assert.equal(Model.diagnosis("cpu", snapshot, 5, 20), "This pressure source is unavailable.")
  for (const name of Model.RESOURCES) snapshot.resources[name].available = true
  snapshot.valid = true
  snapshot.resources.cpu.some.avg10 = 25
  assert.match(Model.diagnosis("cpu", snapshot, 5, 20), /frequently waiting/)
  snapshot.resources.cpu.some.avg10 = 7
  assert.match(Model.diagnosis("cpu", snapshot, 5, 20), /still making progress/)
  snapshot.resources.memory.some.avg10 = 7
  snapshot.resources.memory.full.avg10 = 6
  assert.match(Model.diagnosis("memory", snapshot, 5, 20), /All active work/)
  snapshot.resources.io.some.avg10 = 7
  snapshot.resources.io.full.avg10 = 6
  assert.match(Model.diagnosis("io", snapshot, 5, 20), /whole machine/)
  snapshot.resources.io.full.avg10 = 0
  assert.match(Model.diagnosis("io", snapshot, 5, 20), /Some work is waiting/)
})

test("history rejects empty state, invalid resources, and cadence edges", () => {
  assert.deepEqual(Model.normalizeHistory(null), [])
  assert.deepEqual(Model.addHistory([point(100)], null), [point(100)])
  assert.deepEqual(Model.historySeries([point(100)], "bad", "1 hour", 100, 48), [])
  assert.deepEqual(Model.addHistory([point(100)], { valid: false }), [point(100)])
})

test("state parsing refuses JSON primitives and normalizes unknown selections", () => {
  for (const raw of ["null", "[]", "1", '"x"']) assert.equal(Model.parseState(raw).valid, false)
  const parsed = Model.parseState(JSON.stringify({ selected: "network", history: [point(1)] }))
  assert.equal(parsed.valid, true)
  assert.equal(parsed.selected, "cpu")
  assert.equal(parsed.history.length, 1)
})

test("window and polling choices retain exact defaults", () => {
  assert.deepEqual(["15 minutes", "1 hour", "6 hours", "bad"].map(Model.windowMs),
    [900000, 3600000, 21600000, 3600000])
  assert.deepEqual(["2 seconds", "5 seconds", "10 seconds", "30 seconds", "bad"].map(Model.pollSeconds),
    [2, 5, 10, 30, 5])
})

test("series keeps eligible points and clamps requested sample bounds", () => {
  const rows = Array.from({ length: 20 }, (_, index) => point(1000 + index * 1000, { cpu: index }))
  assert.equal(Model.historySeries(rows, "cpu", "1 hour", 30000, 2).length, 8)
  assert.equal(Model.historySeries(rows, "cpu", "1 hour", 30000, 200).length, 20)
  assert.deepEqual(Model.seriesStats([{ value: -1 }, { value: "bad" }, { value: 3 }]),
    { current: 3, average: 1, peak: 3, samples: 3 })
})

test("the complete exported model contract has a deterministic mutation signature", () => {
  const now = 10_000_000
  const complete = Model.parseSnapshot([
    "resource=cpu", "some avg10=24.80 avg60=12.40 avg300=8.10 total=2400000",
    "full avg10=0 avg60=0 avg300=0 total=0",
    "resource=memory", "some avg10=4.20 avg60=3.10 avg300=2.70 total=420000",
    "full avg10=5 avg60=0.4 avg300=0.3 total=60000",
    "resource=io", "some avg10=7 avg60=2.10 avg300=1.40 total=180000",
    "full avg10=5 avg60=0.3 avg300=0.2 total=20000"
  ].join("\n"), now)
  const fullHistory = Array.from({ length: Model.MAX_HISTORY }, (_, index) =>
    point(index * Model.HISTORY_SAMPLE_MS + 1, { cpu: index % 31, memory: index % 17, io: index % 11 }))
  const seriesRows = Array.from({ length: 120 }, (_, index) =>
    point(now - (119 - index) * 1000, {
      cpu: index === 60 ? 80 : index % 10,
      cpuFull: index % 3 === 0 ? null : index % 4
    }))
  const cases = {
    constants: [Model.RESOURCES, Model.MAX_RAW_CHARS, Model.MAX_STATE_CHARS,
      Model.MAX_HISTORY, Model.HISTORY_SAMPLE_MS],
    clean: [undefined, null, "", "x", "xxxx", "xxxxx", "<x>\u0000\u202e"]
      .flatMap(value => [Model.clean(value, 4), Model.clean(value)]),
    empty: [undefined, null, -1, 0, now].map(Model.emptySnapshot),
    metric: ["", " some avg10=1 avg60=2 avg300=3 total=4 ",
      "some avg10=0 avg60=0 avg300=0 total=0",
      "full avg10=1.234 avg60=2.345 avg300=3.456 total=4.9",
      "some avg10=1 avg60=2 avg300=3 total=-1",
      "some avg10=1 avg60=2 avg300=3 nope=4",
      "some avg10=1 avg60=2 avg300=3 total=4=5"].map(Model.parseMetric),
    snapshots: [Model.parseSnapshot("", now), Model.parseSnapshot(null, now), complete,
      Model.parseSnapshot("resource=cpu\nunavailable\n", now),
      Model.parseSnapshot("resource=bad\nsome avg10=1 avg60=2 avg300=3 total=4", now),
      Model.parseSnapshot("x".repeat(Model.MAX_RAW_CHARS), now),
      Model.parseSnapshot("x".repeat(Model.MAX_RAW_CHARS + 1), now)],
    thresholds: [[undefined, undefined], [0, 0], [1, 2], [20, 20], [50, 90], [90, 2]]
      .map(values => Model.clampThresholds(...values)),
    severity: [[0, 5, 20], [5, 5, 20], [20, 5, 20], [undefined, 5, 20]]
      .map(values => Model.severity(...values)),
    rank: ["normal", "warning", "critical", ""].map(Model.severityRank),
    labels: ["cpu", "memory", "io", "bad", ""].map(Model.resourceLabel),
    selected: ["Worst", "worst", "CPU", "Memory", "I/O", "io", "bad", ""]
      .map(preference => Model.selectedResource(complete, preference)),
    selectedEmpty: [Model.selectedResource(null, "Worst"),
      Model.selectedResource(Model.emptySnapshot(now), "CPU")],
    percents: [-1, 0, 9.94, 9.95, 10, 99.4, 99.6, 100, 101]
      .map(Model.formatPercent),
    pills: [Model.pillText(null, "Worst"), Model.pillText(Model.emptySnapshot(now), "Worst"),
      ...["Worst", "CPU", "Memory", "I/O"].map(value => Model.pillText(complete, value))],
    ages: [now, now - 4000, now - 5000, now - 59000, now - 60000,
      now - 3599000, now - 3600000].map(at => Model.ageText(at, now)),
    tips: [Model.tooltipText(null, "Worst", 5, 20, now, "<bad>"),
      Model.tooltipText(Model.emptySnapshot(now), "Worst", 5, 20, now, ""),
      Model.tooltipText(complete, "Worst", 5, 20, now + 5000, "")],
    diagnoses: ["cpu", "memory", "io", "bad"].flatMap(name => [
      Model.diagnosis(name, Model.emptySnapshot(now), 5, 20),
      Model.diagnosis(name, complete, 5, 20), Model.diagnosis(name, complete, 30, 40)
    ]),
    points: [Model.historyPoint(null), Model.historyPoint(Model.emptySnapshot(now)),
      Model.historyPoint(complete)],
    normalized: [Model.normalizeHistory(null), Model.normalizeHistory([]),
      Model.normalizeHistory([null, point(0), point(1), point(1), point(2, { cpu: null }),
        point(3, { cpu: undefined, cpuFull: undefined })])],
    added: [Model.addHistory([], null), Model.addHistory([], Model.emptySnapshot(now)),
      Model.addHistory(fullHistory, complete).slice(-3)],
    states: ["", "{", "null", "[]", "1", JSON.stringify({}),
      JSON.stringify({ selected: "memory", history: [point(1)] }),
      JSON.stringify({ selected: "bad", history: [point(1)] }),
      "x".repeat(Model.MAX_STATE_CHARS), "x".repeat(Model.MAX_STATE_CHARS + 1)]
      .map(Model.parseState),
    windows: ["15 minutes", "1 hour", "6 hours", "bad"].map(Model.windowMs),
    series: [Model.historySeries(seriesRows, "bad", "1 hour", now, 48),
      Model.historySeries(seriesRows, "cpu", "15 minutes", now, 8),
      Model.historySeries(seriesRows, "cpu", "1 hour", now, 48),
      Model.historySeries([point(now - 3600000), point(now, { cpu: null })], "cpu", "1 hour", now, 48)],
    stats: [Model.seriesStats(null), Model.seriesStats([]),
      Model.seriesStats([{ value: 0 }, { value: 2 }, { value: 9 }])],
    polls: ["2 seconds", "5 seconds", "10 seconds", "30 seconds", "bad"].map(Model.pollSeconds)
  }
  const signature = crypto.createHash("sha256").update(JSON.stringify(cases)).digest("hex")
  assert.equal(signature, "ec829201117afc1df8447d3375efcf943389eda32336113d32865167ff1c4492")
})
