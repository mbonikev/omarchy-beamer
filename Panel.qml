import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Project — put the desktop on a second screen: duplicate it, extend in any
// direction, or use one screen only.
//
// The panel holds no layout logic of its own. It renders whatever
// `omarchy-displays state` reports and turns every interaction into one
// subcommand, so the panel, a keybinding, and a script all drive the same
// engine and can never disagree about the current layout.
Panel {
  id: root
  moduleName: "beamer"
  ipcTarget: "beamer"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits — needed for the layout methods keybindings call below.
  manageIpc: false

  // Absolute path to the engine: the plugin ships it in bin/ and that
  // directory is not on PATH.
  readonly property string engine: {
    var url = Qt.resolvedUrl("bin/omarchy-displays").toString()
    return url.indexOf("file://") === 0 ? url.substring(7) : url
  }

  property var state: Model.parseState(null)
  property string selectedName: ""
  property string pendingLabel: ""

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  readonly property var selected: Model.findDisplay(state, selectedName)
  readonly property string activePreset: Model.activePreset(state)
  readonly property var presetOptions: Model.presets(state).concat(Model.onlyOptions(state))

  // The built-in omarchy.monitor widget already owns the plain monitor glyphs,
  // so this uses the cast pair: hollow on one screen, filled once a second one
  // is in use. Written as surrogate pairs because these sit above the BMP and
  // the literal characters do not survive every editor and patch pipeline.
  readonly property string modeIcon: {
    return state.enabledCount > 1
      ? "\uDB80\uDD19"   // nf-md-cast_connected
      : "\uDB80\uDD18"   // nf-md-cast
  }

  // ------------------------------------------------------------- keyboard
  //
  // One cursor over a list of single-row sections: j/k walks the sections,
  // h/l walks the controls inside the current one, Enter activates. Mouse
  // hover writes the same cursor so pointer and keyboard share a highlight.
  property string focusSection: "arrangement"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property bool multiHead: state.connectedCount > 1

  readonly property var visibleSections: {
    var list = []
    if (multiHead) list.push("arrangement")
    if (multiHead) list.push("map")
    if (selected) {
      list.push("actions")
      list.push("mode")
    }
    if (showProfiles) list.push("profiles")
    return list
  }

  readonly property var actionOptions: {
    if (!selected) return []
    var list = []
    var isEnabled = selected.wanted && selected.wanted.enabled === true
    // Never offer to switch off the last display left standing.
    if (isEnabled && state.enabledCount > 1) list.push({ value: "off", label: "Turn off" })
    else if (!isEnabled) list.push({ value: "on", label: "Turn on" })
    if (isEnabled && state.primary !== selected.name) list.push({ value: "primary", label: "Make primary" })
    if (isEnabled && state.connectedCount > 1) {
      var at = state.order.indexOf(selected.name)
      if (at > 0) list.push({ value: "back", label: "◀ Move" })
      if (at >= 0 && at < state.order.length - 1) list.push({ value: "forward", label: "Move ▶" })
    }
    return list
  }

  readonly property bool showProfiles: state.managed || state.profiles.length > 0

  readonly property var profileOptions: {
    var list = []
    for (var i = 0; i < state.profiles.length; i++)
      list.push({ value: "apply:" + state.profiles[i], label: state.profiles[i] })
    if (state.managed) list.push({ value: "save", label: "+ Save" })
    if (state.managed) list.push({ value: "reset", label: "Reset" })
    return list
  }

  function sectionCount(section) {
    if (section === "arrangement") return presetOptions.length
    if (section === "map") return state.order.length
    if (section === "actions") return actionOptions.length
    if (section === "mode") return 1
    if (section === "profiles") return profileOptions.length
    return 0
  }

  function moveCursor(delta) {
    var sections = visibleSections
    var at = sections.indexOf(focusSection)
    if (at < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var next = at + delta
    // Skip over sections that have nothing in them, so an empty profile list
    // doesn't swallow a keypress.
    while (next >= 0 && next < sections.length && sectionCount(sections[next]) === 0)
      next += delta
    if (next < 0 || next >= sections.length) return
    focusSection = sections[next]
    selectedIndex = Math.min(selectedIndex, Math.max(0, sectionCount(focusSection) - 1))
  }

  function moveCursorH(delta) {
    var max = sectionCount(focusSection) - 1
    selectedIndex = Math.max(0, Math.min(max, selectedIndex + delta))
  }

  function activate() {
    switch (focusSection) {
    case "arrangement":
      if (selectedIndex < presetOptions.length) applyPreset(presetOptions[selectedIndex].value)
      break
    case "map":
      if (selectedIndex < state.order.length) selectedName = state.order[selectedIndex]
      break
    case "actions":
      if (selectedIndex < actionOptions.length) runAction(actionOptions[selectedIndex].value)
      break
    case "mode":
      modeDropdown.toggle()
      break
    case "profiles":
      if (selectedIndex < profileOptions.length) runProfile(profileOptions[selectedIndex].value)
      break
    }
  }

  function cursorOn(section, index) {
    return cursorActive && focusSection === section && selectedIndex === index
  }

  function takeCursor(section, index, isHovered) {
    if (!isHovered) return
    cursorActive = true
    focusSection = section
    selectedIndex = index
  }

  // ---------------------------------------------------------------- engine

  function run(args, label) {
    if (actionProc.running) return
    pendingLabel = label || ""
    actionProc.command = [root.engine].concat(args)
    actionProc.running = true
  }

  function applyPreset(preset) {
    if (preset === "mirror") run(["mirror"], "Mirroring")
    else if (preset.indexOf("only:") === 0) {
      var name = preset.substring(5)
      run(["only", name], name + " only")
    }
    else if (preset === "custom" || preset === "single") refresh()
    else run(["extend", preset], "Extending")
  }

  function runAction(action) {
    if (!selected) return
    var name = selected.name
    switch (action) {
    case "on": run(["enable", name, "on"], "Turning on " + name); break
    case "off": run(["enable", name, "off"], "Turning off " + name); break
    case "primary": run(["primary", name], "Setting primary"); break
    case "back":
    case "forward":
      var order = Model.reorder(state.order, name, action === "back" ? -1 : 1)
      var args = ["arrange"]
      if (state.axis === "vertical") args.push("--vertical")
      run(args.concat(order), "Rearranging")
      break
    }
  }

  function runProfile(choice) {
    if (choice === "save") {
      profileName.text = ""
      savingProfile = true
      return
    }
    if (choice === "reset") { run(["reset"], "Resetting"); return }
    if (choice.indexOf("apply:") === 0)
      run(["profile", "apply", choice.substring(6)], "Applying profile")
  }

  property bool savingProfile: false

  function commitProfile() {
    var name = String(profileName.text || "").trim()
    savingProfile = false
    if (name.length === 0) return
    run(["profile", "save", name], "Saving profile")
  }

  function setMode(mode) {
    if (!selected) return
    run(["mode", selected.name, mode], "Changing mode")
  }



  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function updateState(raw) {
    var next = Model.parseState(raw)
    if (!next.ok) return
    state = next
    // Keep the selection pinned to a display that still exists, preferring
    // the focused one on first load.
    if (!Model.findDisplay(next, selectedName)) {
      var focused = ""
      for (var i = 0; i < next.displays.length; i++)
        if (next.displays[i].focused) focused = next.displays[i].name
      selectedName = focused || (next.order.length > 0 ? next.order[0] : "")
    }
    if (visibleSections.indexOf(focusSection) < 0) {
      focusSection = visibleSections.length > 0 ? visibleSections[0] : ""
      selectedIndex = 0
    }
  }

  IpcHandler {
    target: "beamer"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Exposed so a keybinding can switch layout without opening the panel.
    function mirror(): void { root.run(["mirror"], "Mirroring") }
    function extend(direction: string): void { root.run(["extend", direction || "right"], "Extending") }
    function profile(name: string): void { root.run(["profile", "apply", name], "Applying profile") }
    function reset(): void { root.run(["reset"], "Resetting") }
  }

  Process {
    id: stateProc
    command: [root.engine, "state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateState(text) }
  }

  Process {
    id: actionProc
    // The engine reloads Hyprland, which takes a moment to settle into the
    // monitor list; re-read once immediately and once after it has.
    onExited: {
      root.pendingLabel = ""
      root.refresh()
      settleTimer.restart()
    }
  }

  Timer { id: settleTimer; interval: 700; onTriggered: root.refresh() }
  Timer { interval: 4000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Monitor hotplug changes the screen list, which is the cue to re-read even
  // when the panel is shut.
  Connections {
    target: Quickshell
    function onScreensChanged() { hotplugTimer.restart() }
  }
  Timer { id: hotplugTimer; interval: 900; onTriggered: root.refresh() }

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      cursorActive = false
      savingProfile = false
      focusSection = visibleSections.length > 0 ? visibleSections[0] : ""
      selectedIndex = 0
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // 󰍹 one display, 󰍺 more than one.
    text: root.modeIcon
    // The open panel already states this in its hero, where the tooltip would
    // otherwise sit on top of it.
    tooltipText: root.opened ? "" : Model.statusLine(root.state)
    onPressed: function(b) {
      if (b === Qt.RightButton) root.run(["mirror"], "Mirroring")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.savingProfile
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------------------------------------------------- hero
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.modeIcon
            color: root.fg
            font.family: root.ff
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Project"
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: (root.pendingLabel !== "" ? root.pendingLabel + "…" : Model.statusLine(root.state)).toUpperCase()
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------------------------------------------- arrangement presets
        Column {
          visible: root.multiHead
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "ARRANGEMENT"; foreground: root.fg; fontFamily: root.ff }

          Flow {
            id: presetFlow
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.presetOptions
              Button {
                required property var modelData
                required property int index
                text: modelData.label
                tooltipText: modelData.tooltip || ""
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.ff
                bordered: true
                active: root.activePreset === modelData.value
                hasCursor: root.cursorOn("arrangement", index)
                onClicked: root.applyPreset(modelData.value)
                onHovered: function(h) { root.takeCursor("arrangement", index, h) }
              }
            }
          }
        }

        // -------------------------------------------------- arrangement map
        Column {
          visible: root.state.connectedCount > 1
          width: parent.width
          spacing: Style.space(8)

          Item {
            id: mapArea
            width: parent.width
            implicitHeight: Style.space(96)

            readonly property var layout: Model.mapLayout(root.state, width, implicitHeight, Style.space(4))

            Repeater {
              model: mapArea.layout.items
              Rectangle {
                required property var modelData
                required property int index
                // Centre the whole arrangement in the strip.
                x: modelData.px + (mapArea.width - mapArea.layout.width) / 2
                y: modelData.py + (mapArea.implicitHeight - mapArea.layout.height) / 2
                width: modelData.pw
                height: modelData.ph
                radius: Style.cornerRadius
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                               root.selectedName === modelData.name ? 0.20 : 0.07)
                border.width: Math.max(1, Style.normalBorderWidth)
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b,
                                      root.selectedName === modelData.name ? 0.9 : 0.3)
                Column {
                  anchors.centerIn: parent
                  spacing: 0
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: Model.shortName(Model.findDisplay(root.state, modelData.name))
                    color: root.fg
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                    font.bold: root.state.primary === modelData.name
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: parent.parent.height > Style.space(34)
                    textFormat: Text.PlainText
                    text: modelData.w + "×" + modelData.h
                    color: Qt.darker(root.fg, 1.5)
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: modelData.mirrors > 0
                    textFormat: Text.PlainText
                    text: "repeated on " + modelData.mirrors
                          + (modelData.mirrors === 1 ? " screen" : " screens")
                    color: Qt.darker(root.fg, 1.5)
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    root.selectedName = modelData.name
                    root.focusSection = "map"
                    root.selectedIndex = root.state.order.indexOf(modelData.name)
                  }
                  onContainsMouseChanged: {
                    if (containsMouse)
                      root.takeCursor("map", root.state.order.indexOf(modelData.name), true)
                  }
                }
              }
            }
          }

          // Picking a display to configure. The map is the pretty version of
          // this row; the row is what the keyboard drives.
          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.state.order
              Button {
                required property var modelData
                required property int index
                text: String(modelData)
                fontSize: Style.font.caption
                foreground: root.fg
                fontFamily: root.ff
                bordered: true
                selected: root.selectedName === modelData
                hasCursor: root.cursorOn("map", index)
                onClicked: root.selectedName = String(modelData)
                onHovered: function(h) { root.takeCursor("map", index, h) }
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg; visible: !!root.selected }

        // ------------------------------------------------ selected display
        Column {
          visible: !!root.selected
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: root.selected
              ? (root.selectedName + (root.state.primary === root.selectedName ? " · PRIMARY" : "")
                 + (root.selected.wanted && root.selected.wanted.enabled ? "" : " · OFF"))
              : ""
            foreground: root.fg
            fontFamily: root.ff
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actionOptions
              Button {
                required property var modelData
                required property int index
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.ff
                bordered: true
                hasCursor: root.cursorOn("actions", index)
                onClicked: root.runAction(modelData.value)
                onHovered: function(h) { root.takeCursor("actions", index, h) }
              }
            }
          }

          Dropdown {
            id: modeDropdown
            width: parent.width
            label: "Resolution"
            options: Model.modeOptions(root.selected)
            value: root.selected && root.selected.wanted ? String(root.selected.wanted.mode || "preferred") : "preferred"
            foreground: root.fg
            fontFamily: root.ff
            hasCursor: root.cursorOn("mode", 0)
            onChanged: function(v) { root.setMode(v) }
            onHovered: function(h) { root.takeCursor("mode", 0, h) }
          }

        }

        PanelSeparator { foreground: root.fg; visible: root.showProfiles }

        // ------------------------------------------------------- profiles
        Column {
          visible: root.showProfiles
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader { text: "PROFILES"; foreground: root.fg; fontFamily: root.ff }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.profileOptions
              Button {
                required property var modelData
                required property int index
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.ff
                bordered: true
                hasCursor: root.cursorOn("profiles", index)
                onClicked: root.runProfile(modelData.value)
                onHovered: function(h) { root.takeCursor("profiles", index, h) }
              }
            }
          }

          Row {
            visible: root.savingProfile
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: profileName
              width: parent.width - saveButton.implicitWidth - cancelButton.implicitWidth - parent.spacing * 2
              placeholderText: "Profile name"
              foreground: root.fg
              font.family: root.ff
              onAccepted: root.commitProfile()
            }

            Button {
              id: saveButton
              text: "Save"
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.ff
              bordered: true
              onClicked: root.commitProfile()
            }

            Button {
              id: cancelButton
              text: "Cancel"
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.ff
              bordered: true
              onClicked: root.savingProfile = false
            }
          }
        }
      }
    }
  }

  onSavingProfileChanged: if (savingProfile) profileName.forceActiveFocus()
}
