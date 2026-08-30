const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const read = name => fs.readFileSync(path.join(__dirname, "..", name), "utf8")

test("the bar control exposes a dynamic named button role and pointer activation", () => {
  const qml = read("BarWidget.qml")
  assert.match(qml, /Accessible\.role:\s*Accessible\.Button/)
  assert.match(qml, /Accessible\.name:\s*root\.opened\s*\?\s*"Close Wait State"\s*:\s*"Open Wait State"/)
  assert.match(qml, /onPressed:\s*function\(mouseButton\)/)
})

test("the pressure panel exposes keyboard focus, close, navigation, selection, and refresh", () => {
  const qml = read("Panel.qml")
  assert.match(qml, /KeyboardPanel\s*{/)
  assert.match(qml, /focusTarget:\s*keyCatcher/)
  assert.match(qml, /PanelKeyCatcher\s*{/)
  assert.match(qml, /onCloseRequested:\s*root\.close\(\)/)
  assert.match(qml, /onTabRequested:/)
  assert.match(qml, /onMoveRequested:/)
  for (const key of ["r", "1", "2", "3"]) assert.match(qml, new RegExp(`key === "${key}"`))
})

test("the panel keeps its content clipped and keyboard-readable", () => {
  const qml = read("Panel.qml")
  assert.match(qml, /Flickable\s*{[\s\S]*clip:\s*true[\s\S]*interactive:\s*contentHeight\s*>\s*height/)
  assert.match(qml, /1\/2\/3 select/)
  assert.doesNotMatch(qml, /Text\.StyledText/)
})
