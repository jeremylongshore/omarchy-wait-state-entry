const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const read = name => fs.readFileSync(path.join(root, name), "utf8")
const Model = require("../Model.js")

test("every Model function called by production QML exists on the export surface", () => {
  const qml = ["BarWidget.qml", "Panel.qml", "Service.qml"].map(read).join("\n")
  const called = [...qml.matchAll(/Model\.([A-Za-z][A-Za-z0-9_]*)\s*\(/g)].map(match => match[1])
  assert.ok(called.length > 0)
  for (const name of new Set(called)) assert.equal(typeof Model[name], "function", name)
})

test("manifest, service, bar host, and panel use one module id", () => {
  const id = JSON.parse(read("manifest.json")).id
  const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  assert.match(read("Service.qml"), new RegExp(`moduleId: "${escaped}"`))
  for (const file of ["BarWidget.qml", "Panel.qml"])
    assert.match(read(file), new RegExp(`moduleName: "${escaped}"`))
})

test("manifest entry points exist inside the repository", () => {
  const manifest = JSON.parse(read("manifest.json"))
  for (const entry of Object.values(manifest.entryPoints)) {
    const resolved = path.resolve(root, entry)
    assert.ok(resolved.startsWith(root + path.sep))
    assert.equal(fs.statSync(resolved).isFile(), true)
  }
})

test("the service reads only fixed bounded PSI files and initializes private state before loading", () => {
  const service = read("Service.qml")
  assert.match(service, /for r in cpu memory io/)
  assert.match(service, /head -c 512 -- \\"\/proc\/pressure\/\$r\\"/)
  assert.doesNotMatch(service, /curl|wget|https?:\/\//)
  assert.match(service, /command:\s*\["install",\s*"-d",\s*"-m",\s*"700"/)
  assert.match(service, /root\.stateDirReady = code === 0/)
  assert.match(service, /path:\s*root\.stateDirReady\s*\?\s*root\.statePath\s*:\s*""/)
  assert.match(service, /if \(!root\.stateDirReady \|\| !root\.stateLoaded\) return/)
  assert.match(service, /if \(root\.stateDirReady\) root\.loadState/)
})

test("marketplace copy and authored Wait State banner are release artifacts", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.description.length, 500)
  assert.equal(manifest.barWidget.description.length, 500)
  assert.equal(manifest.description, manifest.barWidget.description)
  for (const claim of [
    "CPU, memory, and I/O pressure stalls", "worst current source", "pinned choice",
    "15-minute, 1-hour, or 6-hour history", "avg10, avg60, avg300",
    "full-stall data when available", "three fixed procfs files",
    "bounded local plugin history",
    "No network, credentials, telemetry, process control, or system configuration change"
  ]) assert.match(manifest.description, new RegExp(claim))
  const banner = read("assets/banner.svg")
  assert.match(banner, /<title>Wait State<\/title>/)
  assert.match(banner, /KERNEL PRESSURE \/ AVG10/)
  assert.match(banner, /CPU 24\.8% WAIT/)
  assert.match(banner, /<(?:path|circle)\b/)
})

test("render tooling requires focused provenance and an exact visual approval", () => {
  const render = read("scripts/rig-render.sh")
  assert.match(render, /OMARCHY_RIG_RESOLUTION:-1280x720/)
  assert.match(render, /OMARCHY_RIG_SCALE:-1\.25/)
  assert.match(render, /rig-only deterministic PSI/)
  assert.ok(render.includes("at:(\\$now - ((48 - \\$i) * 75000))"))
  assert.match(render, /\.history \| length\) == 49/)
  assert.ok(render.includes('exec /usr/bin/head "\\$@"'))
  assert.match(render, /rawShellLogSha256/)
  assert.match(render, /visualInspection:\{status:"pending"/)
  assert.match(render, /grim "\\\$SHOT"/)
  assert.doesNotMatch(render, /grim -g|pkill|\bcurl\b|\bwget\b/)

  const approval = read("scripts/approve-preview.sh")
  assert.match(approval, /product value is visible without reading the README/)
  assert.match(approval, /no primary content is clipped/)
  assert.match(approval, /plugin-specific visual identity/)
})

test("canonical freshness uses a shallow clone and never a downloader execution pattern", () => {
  const freshness = read("scripts/check-lane-freshness.sh")
  assert.match(freshness, /git clone --quiet --depth 1 --branch/)
  assert.match(freshness, /sha256sum "\$canonical"/)
  assert.doesNotMatch(freshness, /\bcurl\b|\bwget\b/)
})
