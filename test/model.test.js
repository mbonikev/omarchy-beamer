// Exercises Model.js against real `omarchy-displays state` captures.
// Run: node test/model.test.js <state.json> [...]
const assert = require("assert")
const M = require("../Model.js")
const fs = require("fs")

let checks = 0
function ok(cond, what) { assert.ok(cond, what); checks++ }
function eq(a, b, what) { assert.deepStrictEqual(a, b, what + ` (got ${JSON.stringify(a)})`); checks++ }

// --- malformed input must never throw -------------------------------------
for (const bad of ["", "null", "{}", "not json", '{"displays":"nope"}']) {
  const s = M.parseState(bad)
  ok(s.ok === false, "garbage rejected: " + bad)
  eq(M.statusLine(s), "No display data", "garbage status")
  eq(M.mapLayout(s, 300, 120, 4).items, [], "garbage map")
  eq(M.activePreset(s), "single", "garbage preset")
}

// --- real captures --------------------------------------------------------
for (const path of process.argv.slice(2)) {
  const label = path.split("/").pop()
  const s = M.parseState(fs.readFileSync(path, "utf8"))
  ok(s.ok, label + ": parsed")
  ok(s.displays.length === s.connectedCount, label + ": display count matches")

  // every display yields finite geometry and non-empty labels
  for (const d of s.displays) {
    const size = M.logicalSize(d)
    ok(size.width > 0 && size.height > 0, `${label}: ${d.name} has a size`)
    ok(M.modeLabel(d).length > 0, `${label}: ${d.name} has a mode label`)
    ok(M.modeOptions(d)[0].value === "preferred", `${label}: ${d.name} offers preferred`)
    ok(M.shortName(d).length > 0, `${label}: ${d.name} has a short name`)
  }

  // the map only ever contains enabled displays, inside the requested box
  const map = M.mapLayout(s, 300, 120, 4)
  eq(map.items.length, s.mode === "mirror" ? Math.min(1, s.enabledCount) : s.enabledCount,
     label + ": map covers the enabled displays")
  for (const it of map.items) {
    ok(it.px >= 0 && it.py >= 0, `${label}: ${it.name} is not off the left/top`)
    ok(it.px + it.pw <= 302 && it.py + it.ph <= 122, `${label}: ${it.name} fits the box`)
    ok(it.pw >= 2 && it.ph >= 2, `${label}: ${it.name} is visible`)
  }
  ok(M.statusLine(s).length > 0, label + ": has a status line")
  ok(M.presets(s).length >= 4, label + ": offers presets")

  // Every "only" mode names a real display and is labelled.
  const only = M.onlyOptions(s)
  eq(only.length, s.connectedCount >= 2 ? s.connectedCount : 0, label + ": one only-mode per display")
  for (const o of only) {
    ok(o.value.startsWith("only:"), `${label}: ${o.label} targets a display`)
    ok(!!M.findDisplay(s, o.value.substring(5)), `${label}: ${o.label} names a connected display`)
    ok(o.label.length > 0, `${label}: only-mode is labelled`)
  }
}

// --- preset detection round-trips with the engine's own layouts -----------
const base = {
  ok: true, displays: [
    { name: "A", wanted: { enabled: true, position: null }, live: {}, modes: [] },
    { name: "B", wanted: { enabled: true, position: null }, live: {}, modes: [] }
  ], enabledCount: 2, connectedCount: 2, profiles: []
}
eq(M.activePreset({ ...base, mode: "mirror", axis: "horizontal", order: ["A","B"], primary: "A" }), "mirror", "mirror detected")
eq(M.activePreset({ ...base, mode: "extend", axis: "horizontal", order: ["A","B"], primary: "A" }), "right", "extend right detected")
eq(M.activePreset({ ...base, mode: "extend", axis: "horizontal", order: ["B","A"], primary: "A" }), "left", "extend left detected")
eq(M.activePreset({ ...base, mode: "extend", axis: "vertical", order: ["A","B"], primary: "A" }), "down", "extend down detected")
eq(M.activePreset({ ...base, mode: "extend", axis: "vertical", order: ["B","A"], primary: "A" }), "up", "extend up detected")
eq(M.activePreset({ ...base, mode: "extend", axis: "horizontal", order: ["A","B"], primary: "A",
  displays: [{ name: "A", wanted: { enabled: true, position: "100x0" }, live: {}, modes: [] },
              { name: "B", wanted: { enabled: true, position: null }, live: {}, modes: [] }] }), "custom", "manual position detected")

// --- the four display modes ----------------------------------------------
const twoHeads = {
  ok: true, mode: "extend", axis: "horizontal", order: ["eDP-1","HDMI-A-1"], primary: "eDP-1",
  profiles: [], enabledCount: 2, connectedCount: 2,
  displays: [
    { name: "eDP-1", internal: true, description: "Laptop panel", wanted: { enabled: true, position: null }, live: {}, modes: [] },
    { name: "HDMI-A-1", internal: false, description: "Acme Projector", wanted: { enabled: true, position: null }, live: {}, modes: [] }
  ]
}
eq(M.onlyOptions(twoHeads).map(o => o.label), ["PC screen only", "Second screen only"], "two heads get the familiar names")
eq(M.onlyOptions(twoHeads).map(o => o.value), ["only:eDP-1", "only:HDMI-A-1"], "only-modes target each display")
eq(M.onlyOptions({ ...twoHeads, connectedCount: 1, displays: [twoHeads.displays[0]] }), [], "a lone display has no only-mode")

// With several externals, "second" would be a guess, so each is named.
const threeHeads = {
  ...twoHeads, order: ["eDP-1","HDMI-A-1","DP-1"], enabledCount: 3, connectedCount: 3,
  displays: twoHeads.displays.concat([
    { name: "DP-1", internal: false, description: "Dell U2720Q", wanted: { enabled: true, position: null }, live: {}, modes: [] }])
}
eq(M.onlyOptions(threeHeads).map(o => o.label), ["PC screen only", "Acme only", "Dell only"], "several externals are named")

// A single enabled display reports which only-mode it is in.
const pcOnly = {
  ...twoHeads, enabledCount: 1,
  displays: [{ ...twoHeads.displays[0] }, { ...twoHeads.displays[1], wanted: { enabled: false, position: null } }]
}
eq(M.activePreset(pcOnly), "only:eDP-1", "PC-screen-only is detected")
eq(M.statusLine(pcOnly), "eDP-1 only", "PC-screen-only reads back")

// mirror shows the source alone, counting the screens repeating it
const mirrorMap = M.mapLayout({ ...base, mode: "mirror", axis: "horizontal", order: ["A","B"], primary: "A", mirrorSource: "B" }, 300, 120, 4)
eq(mirrorMap.items.map(i => i.name), ["B"], "mirror draws only the source")
eq(mirrorMap.items[0].mirrors, 1, "mirror counts the repeats")
eq([mirrorMap.items[0].px, mirrorMap.items[0].py], [0, 0], "mirror sits at the origin")
// falling back to the first enabled display when no source is recorded
const mirrorNoSource = M.mapLayout({ ...base, mode: "mirror", axis: "horizontal", order: ["A","B"], primary: "A" }, 300, 120, 4)
eq(mirrorNoSource.items.map(i => i.name), ["A"], "mirror without a source uses the first display")

// --- reorder --------------------------------------------------------------
eq(M.reorder(["A","B","C"], "C", -1), ["A","C","B"], "move left")
eq(M.reorder(["A","B","C"], "A", 1), ["B","A","C"], "move right")
eq(M.reorder(["A","B","C"], "A", -1), ["A","B","C"], "already leftmost")
eq(M.reorder(["A","B","C"], "C", 1), ["A","B","C"], "already rightmost")
eq(M.reorder(["A","B","C"], "Z", 1), ["A","B","C"], "unknown display")

console.log(`${checks} checks passed`)
