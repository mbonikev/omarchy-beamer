// Pure helpers for the Displays panel. Everything here is side-effect free so
// it can be exercised outside Quickshell (see test/model.test.js).

function parseState(raw) {
  var state
  try {
    state = raw ? JSON.parse(String(raw)) : null
  } catch (e) {
    state = null
  }
  if (!state || typeof state !== "object" || !Array.isArray(state.displays)) {
    return {
      ok: false, managed: false, mode: "extend", axis: "horizontal", align: "top",
      primary: "", mirrorSource: "", order: [], profiles: [], displays: [],
      enabledCount: 0, connectedCount: 0
    }
  }
  state.ok = true
  state.profiles = Array.isArray(state.profiles) ? state.profiles : []
  state.order = Array.isArray(state.order) ? state.order : []
  return state
}

function findDisplay(state, name) {
  for (var i = 0; i < state.displays.length; i++)
    if (state.displays[i].name === name) return state.displays[i]
  return null
}

// The arrangement preset the current layout corresponds to, so the button row
// can show which one is active. An explicit per-output position means the
// layout no longer matches any preset.
function activePreset(state) {
  if (state.mode === "mirror") return "mirror"
  // One screen left standing is a "<name> only" mode, whatever its position.
  if (state.enabledCount === 1) {
    for (var j = 0; j < state.displays.length; j++)
      if (state.displays[j].wanted && state.displays[j].wanted.enabled)
        return "only:" + state.displays[j].name
    return "single"
  }
  for (var i = 0; i < state.displays.length; i++) {
    var d = state.displays[i]
    if (d.wanted && d.wanted.enabled && d.wanted.position) return "custom"
  }
  if (state.enabledCount === 0) return "single"

  var primaryFirst = state.order.length > 0 && state.order[0] === state.primary
  if (state.axis === "vertical") return primaryFirst ? "down" : "up"
  return primaryFirst ? "right" : "left"
}

// The "only this screen" modes, named the way everyone else names them. With
// one external the pair reads PC / Second screen; with several, each external
// is named, because "second" would be a guess.
function onlyOptions(state) {
  if (state.connectedCount < 2) return []

  var externals = 0
  var i
  for (i = 0; i < state.displays.length; i++)
    if (!state.displays[i].internal) externals++

  var list = []
  for (i = 0; i < state.displays.length; i++) {
    var display = state.displays[i]
    var label
    if (display.internal) label = "PC screen only"
    else if (externals === 1) label = "Second screen only"
    else label = shortName(display) + " only"
    list.push({
      value: "only:" + display.name,
      label: label,
      tooltip: "Show the desktop on " + display.name + " alone"
    })
  }
  return list
}

function presets(state) {
  var anchor = state.primary || "the primary display"
  var list = [
    { value: "right", label: "Right →", tooltip: "Extend: other displays to the right of " + anchor },
    { value: "left", label: "← Left", tooltip: "Extend: other displays to the left of " + anchor },
    { value: "down", label: "Down ↓", tooltip: "Extend: other displays below " + anchor },
    { value: "up", label: "Up ↑", tooltip: "Extend: other displays above " + anchor }
  ]
  // Mirroring needs something to mirror onto.
  if (state.connectedCount >= 2)
    list.unshift({ value: "mirror", label: "Mirror", tooltip: "Show the same picture on every display" })
  return list
}

function modeLabel(display) {
  if (!display) return ""
  var wanted = display.wanted || {}
  if (wanted.mode && wanted.mode !== "preferred") {
    for (var i = 0; i < (display.modes || []).length; i++)
      if (display.modes[i].value === wanted.mode) return display.modes[i].label
    return wanted.mode
  }
  var live = display.live || {}
  if (live.width > 0)
    return "Preferred (" + live.width + "×" + live.height + " @ " + Math.round(live.refresh) + "Hz)"
  return "Preferred"
}

function modeOptions(display) {
  var options = [{ value: "preferred", label: "Preferred" }]
  var modes = (display && display.modes) || []
  for (var i = 0; i < modes.length; i++)
    options.push({ value: modes[i].value, label: modes[i].label })
  return options
}

// Logical size of an output under its wanted mode/scale/transform. Mirrors
// the engine's own measurement so the map matches what gets applied.
function logicalSize(display) {
  if (!display) return { width: 0, height: 0 }
  var wanted = display.wanted || {}
  var live = display.live || {}
  var w = 0, h = 0

  var match = /^([0-9]+)x([0-9]+)/.exec(String(wanted.mode || ""))
  if (match) {
    w = Number(match[1]); h = Number(match[2])
  } else if (live.width > 0) {
    w = live.width; h = live.height
  } else if ((display.modes || []).length > 0) {
    w = display.modes[0].width; h = display.modes[0].height
  }
  if (!(w > 0)) { w = 1920; h = 1080 }

  var scale = Number(wanted.scale)
  if (!isFinite(scale) || scale <= 0) scale = 1

  var t = Number(wanted.transform)
  if (!isFinite(t)) t = 0
  if (t === 1 || t === 3 || t === 5 || t === 7) { var swap = w; w = h; h = swap }

  return { width: Math.round(w / scale), height: Math.round(h / scale) }
}

// Lay the enabled displays out in miniature for the arrangement map, scaled to
// fit `boxWidth` x `boxHeight`.
//
// Mirrored displays all occupy the same desktop space, so drawing one card per
// display would just pile unreadable labels on one spot. The map shows the
// source alone, carrying a count of the screens repeating it.
function mapLayout(state, boxWidth, boxHeight, gap) {
  var mirrored = state.mode === "mirror"
  var items = []
  var cursor = 0, crossMax = 0, i, size

  for (i = 0; i < state.order.length; i++) {
    var display = findDisplay(state, state.order[i])
    if (!display || !display.wanted || !display.wanted.enabled) continue
    size = logicalSize(display)
    items.push({ name: display.name, w: size.width, h: size.height, mirrors: 0 })
  }
  if (items.length === 0) return { items: [], scale: 1, width: 0, height: 0 }

  if (mirrored) {
    var sourceIndex = 0
    for (i = 0; i < items.length; i++)
      if (items[i].name === state.mirrorSource) { sourceIndex = i; break }
    var source = items[sourceIndex]
    source.mirrors = items.length - 1
    items = [source]
  }

  var vertical = state.axis === "vertical" && !mirrored
  for (i = 0; i < items.length; i++) {
    if (mirrored) {
      items[i].x = 0; items[i].y = 0
      crossMax = Math.max(crossMax, vertical ? items[i].w : items[i].h)
      cursor = Math.max(cursor, vertical ? items[i].h : items[i].w)
      continue
    }
    if (vertical) {
      items[i].x = 0; items[i].y = cursor; cursor += items[i].h
      crossMax = Math.max(crossMax, items[i].w)
    } else {
      items[i].x = cursor; items[i].y = 0; cursor += items[i].w
      crossMax = Math.max(crossMax, items[i].h)
    }
  }

  var totalW = vertical ? crossMax : cursor
  var totalH = vertical ? cursor : crossMax
  // Leave room for the inter-box gaps the view draws between neighbours.
  // Mirrored displays occupy one spot, so they get no gaps at all.
  var gaps = mirrored ? 0 : Math.max(0, items.length - 1) * (gap || 0)
  var usableW = Math.max(1, boxWidth - (vertical ? 0 : gaps))
  var usableH = Math.max(1, boxHeight - (vertical ? gaps : 0))
  var scale = Math.min(usableW / totalW, usableH / totalH)

  for (i = 0; i < items.length; i++) {
    var lead = mirrored ? 0 : (gap || 0) * i
    items[i].px = Math.round(items[i].x * scale + (vertical ? 0 : lead))
    items[i].py = Math.round(items[i].y * scale + (vertical ? lead : 0))
    items[i].pw = Math.max(2, Math.round(items[i].w * scale))
    items[i].ph = Math.max(2, Math.round(items[i].h * scale))
  }

  return {
    items: items,
    scale: scale,
    width: Math.round(totalW * scale) + (vertical ? 0 : gaps),
    height: Math.round(totalH * scale) + (vertical ? gaps : 0)
  }
}

function statusLine(state) {
  if (!state.ok) return "No display data"
  if (state.connectedCount === 0) return "No displays"
  if (state.mode === "mirror") {
    var source = state.mirrorSource || (state.order.length ? state.order[0] : "")
    return "Mirroring from " + source
  }
  if (state.enabledCount <= 1) {
    for (var i = 0; i < state.displays.length; i++)
      if (state.displays[i].wanted && state.displays[i].wanted.enabled)
        return state.displays[i].name + " only"
    return "No active display"
  }
  var axis = state.axis === "vertical" ? "stacked" : "side by side"
  return state.enabledCount + " displays " + axis
}

function shortName(display) {
  if (!display) return ""
  if (display.internal) return "Built-in"
  var description = String(display.description || "")
  // Hyprland descriptions are "<make> <model> <serial>"; the make alone reads
  // better in a box two centimetres wide.
  var words = description.split(/\s+/).filter(function(w) { return w.length > 0 })
  return words.length > 0 ? words[0] : display.name
}

// Move `name` by `delta` places in the order, returning the new order. Used by
// the reorder buttons; the engine takes the result as an `arrange` call.
function reorder(order, name, delta) {
  var next = order.slice()
  var from = next.indexOf(name)
  if (from < 0) return next
  var to = from + delta
  if (to < 0 || to >= next.length) return next
  next.splice(from, 1)
  next.splice(to, 0, name)
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    parseState: parseState,
    findDisplay: findDisplay,
    activePreset: activePreset,
    presets: presets,
    onlyOptions: onlyOptions,
    modeLabel: modeLabel,
    modeOptions: modeOptions,
    logicalSize: logicalSize,
    mapLayout: mapLayout,
    statusLine: statusLine,
    shortName: shortName,
    reorder: reorder
  }
}
