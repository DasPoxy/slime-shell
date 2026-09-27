import QtQuick
import Quickshell
import Quickshell.Io
import "../ui"

// Slime-Tasks: the command centre's todo suite, in a tavern the slime has
// swallowed whole. Three signs hang from the beam:
//
//   Todo      top-level todos (grouped and coloured) and each one's sub-todos
//   Task Log  what's being worked on, shifting across to do / doing / done,
//             and each todo's log (agents write to it with `slime-tasks`)
//   Progress  how far along every group and todo is; archive and restore
//
// Everything is plain markdown in ~/Documents/Slime-Notes (slime_tasks.py),
// so Envy or any notes app can open it too. Fully keyboard driven: press ?
// for the keys.
Item {
  id: tasks

  property var cc: null
  readonly property var bar: cc ? cc.bar : null
  // set when shown somewhere other than the command centre (the pop-out)
  property var closeRequest: null
  readonly property string script: Qt.resolvedUrl("slime_tasks.py").toString().replace("file://", "")

  // ---- data -------------------------------------------------------------------
  property string folder: ""
  property var groupColors: ({})
  property var todos: []
  property var archivedTodos: []
  property var logEntries: []
  property string error: ""

  // ---- ui state -----------------------------------------------------------------
  property string tab: "todo"                 // todo | log | progress
  property string selectedId: ""
  property string pane: "list"                // todo tab: list | subs
  property int subIndex: 0
  property bool showDone: true
  property bool showHelp: false
  property string armedDelete: ""             // press delete twice
  property var expanded: ({})                 // progress tab: "g:<group>" / "t:<id>"
  property int progressIndex: 0
  property string archiveQuery: ""
  property bool showNotes: false
  property string logPane: "list"             // log tab: list | lanes
  property int logSub: 0                      // which sub-todo, in the lanes

  implicitHeight: 620
  focus: true
  Component.onCompleted: forceActiveFocus()

  readonly property var selected: {
    for (var i = 0; i < todos.length; i++) if (todos[i].id === selectedId) return todos[i]
    return null
  }
  function colorOf(group) {
    return group && groupColors[group] ? groupColors[group].color : "transparent"
  }
  function pct(t) {
    if (t.done) return 1
    var n = t.subs.length
    return n === 0 ? 0 : t.counts.done / n
  }

  // Todo tab: rows grouped by group (alphabetical), ungrouped last.
  readonly property var todoRows: {
    var byGroup = {}, names = [], loose = []
    for (var i = 0; i < todos.length; i++) {
      var t = todos[i]
      if (t.done && !showDone) continue
      if (t.group) {
        if (!byGroup[t.group]) { byGroup[t.group] = []; names.push(t.group) }
        byGroup[t.group].push(t)
      } else loose.push(t)
    }
    names.sort()
    var rows = []
    names.forEach(function(n) {
      rows.push({ kind: "group", name: n })
      byGroup[n].forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    })
    if (loose.length && names.length) rows.push({ kind: "group", name: "" })
    loose.forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    return rows
  }
  readonly property var todoOrder: todoRows.filter(function(r) { return r.kind === "todo" }).map(function(r) { return r.t.id })

  // Task Log tab: most recently active first
  readonly property var logOrder: {
    var a = todos.slice()
    a.sort(function(x, y) { return (y.counts.doing > 0) - (x.counts.doing > 0) || y.logMtime - x.logMtime || y.mtime - x.mtime })
    return a
  }

  // Progress tab rows (collapsible)
  readonly property var progressRows: {
    var byGroup = {}, names = []
    for (var i = 0; i < todos.length; i++) {
      var g = todos[i].group || ""
      if (!(g in byGroup)) { byGroup[g] = []; names.push(g) }
      byGroup[g].push(todos[i])
    }
    names.sort(function(a, b) { return (a === "") - (b === "") || a.localeCompare(b) })
    var rows = []
    names.forEach(function(n) {
      var list = byGroup[n], units = 0, done = 0
      list.forEach(function(t) {
        var u = Math.max(1, t.subs.length)
        units += u
        done += t.done ? u : t.counts.done
      })
      rows.push({ kind: "group", name: n, pct: units ? done / units : 0, count: list.length })
      if (tasks.expanded["g:" + n] === false) return
      list.forEach(function(t) {
        rows.push({ kind: "todo", t: t })
        if (tasks.expanded["t:" + t.id]) t.subs.forEach(function(s) { rows.push({ kind: "sub", t: t, s: s }) })
      })
    })
    return rows
  }

  // ---- backend ------------------------------------------------------------------
  property var queue: []
  Process {
    id: runner
    stdout: StdioCollector { id: runOut }
    stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") tasks.error = text.trim() }
    onExited: {
      var after = tasks.pendingThen
      tasks.pendingThen = null
      if (after) { try { after(JSON.parse(runOut.text)) } catch (e) {} }
      tasks.next()
      tasks.refresh()
    }
  }
  property var pendingThen: null
  // run slime_tasks.py with args, then (optionally) `then` with its JSON
  function act(args, then) {
    queue = queue.concat([{ args: args, then: then || null }])
    next()
  }
  function next() {
    if (runner.running || queue.length === 0) return
    var job = queue[0]
    queue = queue.slice(1)
    error = ""
    pendingThen = job.then
    runner.command = ["python3", script].concat(job.args)
    runner.running = true
  }

  Process {
    id: lister
    command: ["python3", tasks.script, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var r = JSON.parse(text)
          tasks.folder = r.folder
          tasks.groupColors = r.groups
          tasks.todos = r.todos
          if (tasks.selectedId === "" || !tasks.selected) tasks.selectedId = tasks.todoOrder.length ? tasks.todoOrder[0] : ""
        } catch (e) { tasks.error = "couldn't read the notes folder" }
      }
    }
  }
  Process {
    id: archiveLister
    command: ["python3", tasks.script, "search", tasks.archiveQuery, "--archived"]
    stdout: StdioCollector {
      onStreamFinished: { try { tasks.archivedTodos = JSON.parse(text).todos.filter(function(t) { return t.archived }) } catch (e) {} }
    }
  }
  Process {
    id: logReader
    stdout: StdioCollector {
      onStreamFinished: { try { tasks.logEntries = JSON.parse(text).entries.slice().reverse() } catch (e) { tasks.logEntries = [] } }
    }
  }
  function refresh() {
    if (!lister.running) lister.running = true
    if (tab === "log" && selectedId !== "" && !logReader.running) {
      logReader.command = ["python3", script, "log-show", selectedId]
      logReader.running = true
    }
    if (tab === "progress" && !archiveLister.running) archiveLister.running = true
  }
  onTabChanged: refresh()
  onSelectedIdChanged: { logEntries = []; subIndex = 0; logSub = 0; if (tab === "log") refresh() }
  onArchiveQueryChanged: refresh()
  // agents edit the files while you watch: keep polling while the tab is up
  Timer { interval: 2000; repeat: true; running: tasks.visible; triggeredOnStart: true; onTriggered: tasks.refresh() }

  // ---- actions --------------------------------------------------------------------
  function select(delta, order) {
    if (order.length === 0) return
    var i = order.indexOf(selectedId)
    selectedId = order[Math.max(0, Math.min(order.length - 1, (i < 0 ? 0 : i + delta)))]
  }
  // ---- reordering -------------------------------------------------------------
  // every active todo's id, in stored order (what `order` rewrites)
  readonly property var storedOrder: todos.map(function(t) { return t.id })
  // put `id` before (after=false) or after `targetId`, joining targetId's group
  function placeTodo(id, targetId, after, group) {
    if (id === targetId) return
    var ids = storedOrder.filter(function(x) { return x !== id })
    var at = ids.indexOf(targetId)
    if (at < 0) return
    ids.splice(after ? at + 1 : at, 0, id)
    var moving = null
    for (var i = 0; i < todos.length; i++) if (todos[i].id === id) moving = todos[i]
    if (moving && group !== undefined && (moving.group || "") !== group) act(["group", id, group])
    act(["order"].concat(ids))
  }
  // keyboard: swap with the neighbour in the same group (shown order)
  function nudgeTodo(dir) {
    var t = selected
    if (!t) return
    var same = todoOrder.filter(function(id) {
      for (var i = 0; i < todos.length; i++) if (todos[i].id === id) return (todos[i].group || "") === (t.group || "")
      return false
    })
    var i = same.indexOf(t.id), j = i + dir
    if (i < 0 || j < 0 || j >= same.length) return
    placeTodo(t.id, same[j], dir > 0, t.group || "")
  }
  // drag state (todos: list rows; subs: sub rows)
  property string dragTodo: ""
  property int dragSub: -1
  property real dropY: -1                      // marker, in the list's coordinates

  // move a sub-todo one lane on (+1) or back (-1)
  function shift(t, i, dir) {
    var order = ["todo", "doing", "done"]
    var s = t.subs[i]
    var n = order[Math.max(0, Math.min(2, order.indexOf(s.state) + dir))]
    if (n !== s.state) act(["sub-set", t.id, String(i), n, "--expect", s.text])
  }
  function cycle(t, i) {
    var s = t.subs[i]
    var next = s.state === "todo" ? "doing" : s.state === "doing" ? "done" : "todo"
    act(["sub-set", t.id, String(i), next, "--expect", s.text])
  }
  function remove(id) {
    if (armedDelete !== id) { armedDelete = id; disarm.restart(); return }
    armedDelete = ""
    act(["delete", id])
  }
  Timer { id: disarm; interval: 2500; onTriggered: tasks.armedDelete = "" }
  function openMenu(t, x, y) {
    menu.todo = t
    menu.x = Math.max(0, Math.min(tasks.width - menu.width, x))
    menu.y = Math.max(50, Math.min(tasks.height - menu.height, y))
    menu.index = 0
    menu.visible = true
    menu.forceActiveFocus()
  }

  // ---- keyboard --------------------------------------------------------------------
  Keys.onPressed: event => {
    var k = event.key, txt = event.text
    if (txt === "?") { showHelp = !showHelp; event.accepted = true; return }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      var order = ["todo", "log", "progress"]
      tab = order[(order.indexOf(tab) + (k === Qt.Key_Backtab ? 2 : 1)) % 3]
      event.accepted = true; return
    }
    if (txt === "1" || txt === "2" || txt === "3") { tab = ["todo", "log", "progress"][Number(txt) - 1]; event.accepted = true; return }
    var up = k === Qt.Key_Up || txt === "k", down = k === Qt.Key_Down || txt === "j"
    // Esc with nothing to back out of closes the command centre
    if (k === Qt.Key_Escape && !(tab === "todo" && pane === "subs") && !(tab === "log" && logPane === "lanes") && !showHelp) {
      if (closeRequest) closeRequest()
      else if (bar) bar.commandCenterOpen = false
      event.accepted = true; return
    }
    if (k === Qt.Key_Escape && showHelp) { showHelp = false; event.accepted = true; return }
    if (tab === "todo") {
      var t = selected
      if (pane === "list") {
        if ((up || down) && (event.modifiers & Qt.ShiftModifier)) nudgeTodo(up ? -1 : 1)
        else if (up || down) select(up ? -1 : 1, todoOrder)
        else if (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter || txt === "l") {
          if (t && t.subs.length) { pane = "subs"; subIndex = Math.min(subIndex, t.subs.length - 1) } else if (t) subInput.forceActiveFocus()
        }
        else if (k === Qt.Key_Space && t) act(["done", t.id, t.done ? "false" : "true"])
        else if (txt === "n") newInput.forceActiveFocus()
        else if (txt === "a" && t) subInput.forceActiveFocus()
        else if ((txt === "e" || k === Qt.Key_F2) && t) { renameInput.text = t.title; renameInput.forceActiveFocus() }
        else if (txt === "g" && t) openMenu(t, tasks.width * 0.2, 120)
        else if (txt === "A" && t) act(["archive", t.id])
        else if ((txt === "d" || k === Qt.Key_Delete) && t) remove(t.id)
        else if (txt === "f") showDone = !showDone
        else if (txt === "J" || (k === Qt.Key_Down && (event.modifiers & Qt.ShiftModifier))) nudgeTodo(1)
        else if (txt === "K" || (k === Qt.Key_Up && (event.modifiers & Qt.ShiftModifier))) nudgeTodo(-1)
        else return
      } else {
        var n = t ? t.subs.length : 0
        if ((up || down) && (event.modifiers & Qt.ShiftModifier) && t) {
          var to = subIndex + (up ? -1 : 1)
          if (to >= 0 && to < n) { act(["sub-move", t.id, String(subIndex), String(to)]); subIndex = to }
        }
        else if (up) subIndex = Math.max(0, subIndex - 1)
        else if (down) subIndex = Math.min(n - 1, subIndex + 1)
        else if (k === Qt.Key_Left || k === Qt.Key_Escape || txt === "h") pane = "list"
        else if ((k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) && t && n) cycle(t, subIndex)
        else if (txt === "a" && t) subInput.forceActiveFocus()
        else if ((txt === "e" || k === Qt.Key_F2) && t && n) { subEdit.index = subIndex; subEdit.text = t.subs[subIndex].text; subEdit.forceActiveFocus() }
        else if ((txt === "d" || k === Qt.Key_Delete) && t && n) { act(["sub-delete", t.id, String(subIndex)]); subIndex = Math.max(0, subIndex - 1) }
        else if (txt === "K" && t && subIndex > 0) { act(["sub-move", t.id, String(subIndex), String(subIndex - 1)]); subIndex-- }
        else if (txt === "J" && t && subIndex < n - 1) { act(["sub-move", t.id, String(subIndex), String(subIndex + 1)]); subIndex++ }
        else return
      }
    } else if (tab === "log") {
      var lt = selected, ln = lt ? lt.subs.length : 0
      if (txt === "w" && lt) logInput.forceActiveFocus()
      else if (k === Qt.Key_PageDown) logList.flick(0, -1600)
      else if (k === Qt.Key_PageUp) logList.flick(0, 1600)
      else if (logPane === "list") {
        if (up || down) select(up ? -1 : 1, logOrder.map(function(x) { return x.id }))
        else if ((k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter || txt === "l") && ln) { logPane = "lanes"; logSub = Math.min(logSub, ln - 1) }
        else return
      } else {
        if (up) logSub = Math.max(0, logSub - 1)
        else if (down) logSub = Math.min(ln - 1, logSub + 1)
        else if ((k === Qt.Key_Right || txt === "l" || k === Qt.Key_Space) && ln) shift(lt, logSub, 1)
        else if ((k === Qt.Key_Left || txt === "h") && ln) {
          if (lt.subs[logSub].state === "todo") logPane = "list"
          else shift(lt, logSub, -1)
        }
        else if (k === Qt.Key_Escape) logPane = "list"
        else return
      }
    } else {
      var rows = progressRows.filter(function(r) { return r.kind !== "sub" })
      var r = rows[Math.min(progressIndex, rows.length - 1)]
      if (up) progressIndex = Math.max(0, progressIndex - 1)
      else if (down) progressIndex = Math.min(rows.length - 1, progressIndex + 1)
      else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && r) toggleExpand(r)
      else if (txt === "A" && r && r.kind === "todo") act(["archive", r.t.id])
      else if (txt === "/") archiveInput.forceActiveFocus()
      else return
    }
    event.accepted = true
  }
  function toggleExpand(r) {
    var key = r.kind === "group" ? "g:" + r.name : "t:" + r.t.id
    var e = Object.assign({}, expanded)
    e[key] = r.kind === "group" ? (expanded[key] === false) : !expanded[key]
    expanded = e
  }

  // ---- the tavern ----------------------------------------------------------------------
  readonly property color wood: Qt.darker(Qt.tint("#8a5a2e", Qt.rgba(cc.slime.r, cc.slime.g, cc.slime.b, 0.15)), 1.05)
  readonly property color woodLight: Qt.lighter(wood, 1.35)

  // the swallowed tavern's back wall: planks showing faintly through the goo
  Repeater {
    model: Math.ceil(tasks.width / 64)
    Item {
      required property int index
      x: index * 64
      y: 12
      width: 64
      height: tasks.height - 12
      opacity: 0.1
      Rectangle { width: 1.5; height: parent.height; color: tasks.cc.ink }
      Rectangle { x: 20; y: 30 + (parent.index * 37) % 120; width: 3; height: 3; radius: 1.5; color: tasks.cc.ink }
      Rectangle { x: 38; y: 200 + (parent.index * 53) % 180; width: 14; height: 6; radius: 3; color: "transparent"; border.color: tasks.cc.ink; border.width: 1 }
    }
  }
  // lanterns swinging from the beam
  Repeater {
    model: [0.52, 0.94]
    Item {
      required property var modelData
      required property int index
      readonly property real sw: Math.sin((tasks.bar ? tasks.bar.animTime : 0) * 1.3 + index * 2) * 6
      x: modelData * tasks.width - 10
      y: 10
      width: 20; height: 50
      transformOrigin: Item.Top
      rotation: sw
      opacity: 0.7
      Rectangle { x: 9; width: 2; height: 16; color: tasks.cc.ink }
      SlimeGear { y: 14; width: 22; height: 22; size: 22; x: -1; bar: tasks.bar; kind: "candle" }
    }
  }
  // a barrel and a stool, sunk in the corner
  Item {
    x: tasks.width - 70; y: tasks.height - 64
    width: 52; height: 58
    opacity: 0.4
    Rectangle { anchors.fill: parent; radius: 16; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.6 }
    Rectangle { y: 12; width: parent.width; height: 4; color: tasks.cc.ink; opacity: 0.8 }
    Rectangle { y: parent.height - 16; width: parent.width; height: 4; color: tasks.cc.ink; opacity: 0.8 }
    Rectangle { x: 15; width: 1.5; height: parent.height; color: tasks.cc.ink; opacity: 0.4 }
    Rectangle { x: 34; width: 1.5; height: parent.height; color: tasks.cc.ink; opacity: 0.4 }
  }
  Item {
    x: tasks.width - 128; y: tasks.height - 40
    width: 44; height: 36
    opacity: 0.35
    Rectangle { width: parent.width; height: 8; radius: 4; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.4 }
    Rectangle { x: 6; y: 8; width: 5; height: 28; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.2 }
    Rectangle { x: parent.width - 11; y: 8; width: 5; height: 28; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.2 }
  }
  // the bard hasn't stopped playing: notes rising through the goo
  Repeater {
    model: 5
    Text {
      required property int index
      readonly property real rise: ((tasks.bar ? tasks.bar.animTime : 0) * 0.09 + index / 5) % 1
      x: 0.08 * tasks.width + 30 + Math.sin(rise * 9 + index) * 14 + index * 6
      y: 0.30 * tasks.height - rise * 150
      text: index % 2 ? "♪" : "♫"
      color: tasks.cc.ink
      opacity: 0.35 * (1 - rise)
      font.pixelSize: 14 + index % 3 * 3
    }
  }

  // the swallowed tavern's regulars, drifting through the goo behind it all
  Repeater {
    model: [["bard", 0.08, 0.30], ["knight", 0.86, 0.22], ["rogue", 0.55, 0.70], ["orc", 0.30, 0.86],
            ["goblin", 0.93, 0.62], ["wizard", 0.66, 0.42], ["priest", 0.18, 0.60]]
    SlimeCaptive {
      required property var modelData
      required property int index
      readonly property real tt: tasks.bar ? tasks.bar.animTime * 0.18 + index * 1.7 : 0
      x: modelData[1] * (tasks.width - width) + Math.sin(tt) * 14
      y: modelData[2] * (tasks.height - height) + Math.cos(tt * 0.8) * 10
      size: 30
      opacity: 0.32
      kind: modelData[0]
      time: tasks.bar ? tasks.bar.animTime * 0.4 : 0
      ink: tasks.cc.ink
      paper: tasks.cc.paper
      goo: tasks.cc.slime
      pal: tasks.bar && tasks.bar.palette ? tasks.bar.palette : ({})
    }
  }
  Repeater {   // a couple of tankards and a lute's worth of flotsam
    model: [["mug", 0.42, 0.18], ["mug", 0.76, 0.84], ["sword", 0.04, 0.9]]
    SlimeGear {
      required property var modelData
      required property int index
      readonly property real tt: tasks.bar ? tasks.bar.animTime * 0.22 + index * 2.3 : 0
      x: modelData[1] * (tasks.width - width)
      y: modelData[2] * (tasks.height - height) + Math.sin(tt) * 8
      rotation: Math.sin(tt * 0.7) * 25
      width: 26; height: 26; size: 26
      opacity: 0.35
      bar: tasks.bar
      kind: modelData[0]
    }
  }

  // the beam the signs hang from
  Rectangle {
    id: beam
    width: parent.width
    height: 12
    radius: 3
    color: tasks.wood
    border.color: tasks.cc.ink
    border.width: 1.5
    Repeater {
      model: 6
      Rectangle {
        required property int index
        x: 12 + index * (beam.width - 24) / 5 - 2; y: 4
        width: 4; height: 4; radius: 2
        color: tasks.cc.ink; opacity: 0.6
      }
    }
  }

  component TavernSign: Item {
    id: sign
    property string key: ""
    property string label: ""
    property string glyph: ""
    readonly property bool on: tasks.tab === key
    width: signBoard.width
    height: 46
    transformOrigin: Item.Top
    rotation: on ? Math.sin((tasks.bar ? tasks.bar.animTime : 0) * 2.2) * 2.5 : 0
    // chains
    Rectangle { x: 10; y: 0; width: 2; height: 10; color: tasks.cc.ink; opacity: 0.8 }
    Rectangle { x: parent.width - 12; y: 0; width: 2; height: 10; color: tasks.cc.ink; opacity: 0.8 }
    Rectangle {
      id: signBoard
      y: 9
      width: signText.implicitWidth + 30
      height: 32
      radius: 7
      color: sign.on ? tasks.woodLight : tasks.wood
      border.color: tasks.cc.ink
      border.width: sign.on ? 2.4 : 1.5
      // grain
      Rectangle { x: 6; y: 9; width: parent.width - 12; height: 1; color: tasks.cc.ink; opacity: 0.18 }
      Rectangle { x: 10; y: 21; width: parent.width - 24; height: 1; color: tasks.cc.ink; opacity: 0.14 }
      Text {
        id: signText
        anchors.centerIn: parent
        text: sign.glyph + "  " + sign.label
        color: sign.on ? tasks.cc.ink : Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.75)
        font.family: tasks.cc.displayFont
        font.weight: tasks.cc.displayWeight
        font.pixelSize: 15
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { tasks.tab = sign.key; tasks.forceActiveFocus() } }
  }

  Row {
    id: signs
    x: 6
    spacing: 16
    TavernSign { key: "todo"; label: "Todo"; glyph: "" }
    TavernSign { key: "log"; label: "Task Log"; glyph: "" }
    TavernSign { key: "progress"; label: "Progress"; glyph: "" }
  }
  Text {
    anchors.right: parent.right
    y: 18
    text: tasks.error !== "" ? "  " + tasks.error : "? keys"
    color: tasks.cc.ink
    opacity: tasks.error !== "" ? 1 : 0.55
    font.family: tasks.cc.font
    font.pixelSize: 11
    width: Math.min(implicitWidth, parent.width - signs.width - 20)
    elide: Text.ElideRight
    MouseArea { anchors.fill: parent; onClicked: tasks.showHelp = !tasks.showHelp }
  }

  // ---- shared bits ----------------------------------------------------------------------
  component Field: Rectangle {
    id: field
    property alias input: fieldInput
    property string placeholder: ""
    // stay in the box after Enter (for typing several in a row)
    property bool keepFocus: false
    signal accepted(string text)
    height: 30
    radius: 15
    color: Qt.rgba(1, 1, 1, fieldInput.activeFocus ? 0.72 : 0.5)
    border.color: tasks.cc.ink
    border.width: fieldInput.activeFocus ? 2 : 1.2
    TextInput {
      id: fieldInput
      x: 12
      width: parent.width - 24
      anchors.verticalCenter: parent.verticalCenter
      color: tasks.cc.ink
      font.family: tasks.cc.font
      font.pixelSize: 12
      clip: true
      Keys.onReturnPressed: {
        var t = text.trim()
        text = ""
        if (t !== "") field.accepted(t)
        if (!field.keepFocus) tasks.forceActiveFocus()
      }
      Keys.onEscapePressed: { text = ""; tasks.forceActiveFocus() }
      Text {
        visible: fieldInput.text === "" && !fieldInput.activeFocus
        text: field.placeholder
        color: tasks.cc.ink
        opacity: 0.5
        font: fieldInput.font
      }
    }
  }

  component StateBox: Rectangle {
    property string state3: "todo"
    width: 16; height: 16; radius: 5
    color: state3 === "done" ? tasks.cc.ink : state3 === "doing" ? Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.35) : "transparent"
    border.color: tasks.cc.ink
    border.width: 2
    Text {
      anchors.centerIn: parent
      text: parent.state3 === "done" ? "" : parent.state3 === "doing" ? "" : ""
      color: parent.state3 === "done" ? tasks.cc.slime : tasks.cc.ink
      font.family: tasks.cc.font
      font.pixelSize: 8
    }
  }

  component Meter: Rectangle {
    property real value: 0
    property color fill: tasks.cc.ink
    height: 8
    radius: 4
    color: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.15)
    Rectangle { width: parent.width * Math.max(0, Math.min(1, parent.value)); height: parent.height; radius: 4; color: parent.fill }
  }

  readonly property real contentTop: 58

  // ======================================================================== TODO
  Item {
    id: todoTab
    visible: tasks.tab === "todo"
    y: tasks.contentTop
    width: parent.width
    height: parent.height - y

    // left: the todos
    Column {
      id: todoLeft
      width: parent.width * 0.46
      spacing: 8
      Row {
        width: parent.width
        spacing: 6
        Field {
          id: newField
          width: parent.width - hideDone.width - 6
          placeholder: "new todo…  (n)"
          onAccepted: t => tasks.act(["add", t], function(r) { tasks.selectedId = r.id })
        }
        CcButton {
          id: hideDone
          cc: tasks.cc
          anchors.verticalCenter: parent.verticalCenter
          icon: tasks.showDone ? "" : ""
          text: "finished"
          fontSize: 11
          on: tasks.showDone
          onClicked: tasks.showDone = !tasks.showDone
        }
      }
      ListView {
        id: todoList
        width: parent.width
        height: todoTab.height - newField.height - 8 - notesToggle.height - 8 - (tasks.showNotes ? notes.height + 8 : 0)
        clip: true
        spacing: 5
        boundsBehavior: Flickable.StopAtBounds
        model: tasks.todoRows
        currentIndex: {
          for (var i = 0; i < tasks.todoRows.length; i++)
            if (tasks.todoRows[i].kind === "todo" && tasks.todoRows[i].t.id === tasks.selectedId) return i
          return -1
        }
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        Rectangle {
          z: 10
          visible: tasks.dragTodo !== "" && tasks.dropY >= 0
          y: tasks.dropY - 1.5
          width: parent.width; height: 3; radius: 1.5
          color: tasks.cc.ink
        }
        delegate: Item {
          id: row
          required property var modelData
          required property int index
          width: todoList.width
          height: modelData.kind === "group" ? 24 : 38
          // group header
          Row {
            visible: row.modelData.kind === "group"
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(row.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: row.modelData.name !== "" }
            CcHeading { cc: tasks.cc; text: !row.modelData.name ? "NO GROUP" : row.modelData.name.toUpperCase() }
          }
          // a todo
          Rectangle {
            visible: row.modelData.kind === "todo"
            anchors.fill: parent
            readonly property var t: row.modelData.t
            readonly property bool sel: t && t.id === tasks.selectedId
            opacity: t && tasks.dragTodo === t.id ? 0.45 : 1
            radius: 12
            color: tasks.armedDelete !== "" && t && tasks.armedDelete === t.id ? Qt.rgba(1, 0.4, 0.4, 0.6) : sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
            border.color: tasks.cc.ink
            border.width: sel ? (tasks.pane === "list" ? 2.4 : 1.4) : 0
            Rectangle { x: 0; width: 6; height: parent.height; radius: 3; color: parent.t ? tasks.colorOf(parent.t.group) : "transparent" }
            Rectangle {
              id: doneBox
              x: 14; anchors.verticalCenter: parent.verticalCenter
              width: 16; height: 16; radius: 8
              color: parent.t && parent.t.done ? tasks.cc.ink : "transparent"
              border.color: tasks.cc.ink; border.width: 2
              MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                onClicked: tasks.act(["done", parent.parent.t.id, parent.parent.t.done ? "false" : "true"]) }
            }
            Text {
              x: 40; width: parent.width - x - countText.width - 14
              anchors.verticalCenter: parent.verticalCenter
              text: parent.t ? parent.t.title : ""
              elide: Text.ElideRight
              color: tasks.cc.ink
              opacity: parent.t && parent.t.done ? 0.5 : 1
              font.strikeout: parent.t ? parent.t.done : false
              font.family: tasks.cc.font
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              id: countText
              anchors.right: parent.right; anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: parent.t && parent.t.subs.length ? parent.t.counts.done + "/" + parent.t.subs.length : ""
              color: tasks.cc.ink; opacity: 0.7
              font.family: tasks.cc.font; font.pixelSize: 11
            }
            MouseArea {
              id: todoMouse
              anchors.fill: parent
              anchors.leftMargin: 34
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: tasks.dragTodo !== "" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
              preventStealing: true
              property real pressY: 0
              property bool dragging: false
              onPressed: mouse => { pressY = mouse.y; dragging = false }
              onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton)) return
                if (!dragging && Math.abs(mouse.y - pressY) > 6) { dragging = true; tasks.dragTodo = parent.t.id; tasks.selectedId = parent.t.id }
                if (dragging) {
                  var p = mapToItem(todoList.contentItem, mouse.x, mouse.y)
                  var i = todoList.indexAt(20, p.y)
                  var it = i >= 0 ? todoList.itemAtIndex(i) : null
                  tasks.dropY = it ? (tasks.todoRows[i].kind === "group" || p.y < it.y + it.height / 2 ? it.y - 3 : it.y + it.height + 2) - todoList.contentY : -1
                }
              }
              onReleased: mouse => {
                if (!dragging) return
                dragging = false
                var p = mapToItem(todoList.contentItem, mouse.x, mouse.y)
                var i = todoList.indexAt(20, p.y)
                var rows = tasks.todoRows
                if (i >= 0) {
                  var r = rows[i], it = todoList.itemAtIndex(i)
                  if (r.kind === "group") {
                    // on a group's heading: to the top of that group
                    var first = rows[i + 1]
                    if (first && first.kind === "todo") tasks.placeTodo(tasks.dragTodo, first.t.id, false, r.name)
                  } else {
                    tasks.placeTodo(tasks.dragTodo, r.t.id, p.y > it.y + it.height / 2, r.t.group || "")
                  }
                }
                tasks.dragTodo = ""
                tasks.dropY = -1
              }
              onClicked: mouse => {
                tasks.selectedId = parent.t.id
                tasks.pane = "list"
                tasks.forceActiveFocus()
                if (mouse.button === Qt.RightButton) {
                  var p = mapToItem(tasks, mouse.x, mouse.y)
                  tasks.openMenu(parent.t, p.x, p.y)
                }
              }
              onDoubleClicked: { renameInput.text = parent.t.title; renameInput.forceActiveFocus() }
            }
          }
        }
      }
      // your own notes' checkboxes (Envy, ~/Notes …), as before
      CcButton {
        id: notesToggle
        cc: tasks.cc
        icon: tasks.showNotes ? "" : ""
        text: "From your notes"
        fontSize: 11
        on: tasks.showNotes
        onClicked: tasks.showNotes = !tasks.showNotes
      }
      NotesChecklist {
        id: notes
        visible: tasks.showNotes
        width: parent.width
        cc: tasks.cc
        listHeight: 160
      }
    }

    // right: the selected todo's sub-todos
    Rectangle {
      x: todoLeft.width + 14
      width: parent.width - x
      height: parent.height
      radius: 18
      color: Qt.rgba(tasks.cc.paper.r, tasks.cc.paper.g, tasks.cc.paper.b, 0.55)
      border.color: tasks.cc.ink
      border.width: tasks.pane === "subs" ? 2 : 1
      visible: tasks.selected !== null

      Column {
        x: 14; y: 12
        width: parent.width - 28
        spacing: 8
        Item {
          width: parent.width
          height: 26
          Text {
            visible: !renameInput.activeFocus
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            text: tasks.selected ? tasks.selected.title : ""
            elide: Text.ElideRight
            color: tasks.cc.ink
            font.family: tasks.cc.displayFont
            font.weight: tasks.cc.displayWeight
            font.pixelSize: 18
          }
          TextInput {
            id: renameInput
            visible: activeFocus
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            color: tasks.cc.ink
            font.family: tasks.cc.font
            font.pixelSize: 16
            font.bold: true
            Keys.onReturnPressed: { if (tasks.selected && text.trim() !== "") tasks.act(["rename", tasks.selected.id, text.trim()]); tasks.forceActiveFocus() }
            Keys.onEscapePressed: tasks.forceActiveFocus()
          }
        }
        Row {
          spacing: 8
          visible: tasks.selected !== null
          Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: tasks.selected ? tasks.colorOf(tasks.selected.group) : "transparent"; visible: tasks.selected && tasks.selected.group !== "" }
          Text {
            text: tasks.selected ? (tasks.selected.group || "no group") + "  ·  " + tasks.selected.counts.done + " of " + tasks.selected.subs.length + " done" + (tasks.selected.counts.doing ? "  ·  " + tasks.selected.counts.doing + " in progress" : "") : ""
            color: tasks.cc.ink; opacity: 0.7
            font.family: tasks.cc.font; font.pixelSize: 11
          }
        }
        Field {
          id: subField
          width: parent.width
          placeholder: "add a sub-todo…  (a)"
          keepFocus: true
          onAccepted: t => { if (tasks.selected) tasks.act(["sub-add", tasks.selected.id, t]) }
          Component.onCompleted: subInput = subField.input
        }
      }
      ListView {
        id: subList
        x: 14; y: 104
        width: parent.width - 28
        height: parent.height - y - 10
        clip: true
        spacing: 4
        boundsBehavior: Flickable.StopAtBounds
        model: tasks.selected ? tasks.selected.subs : []
        currentIndex: tasks.subIndex
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        Rectangle {
          z: 10
          visible: tasks.dragSub >= 0 && tasks.dropY >= 0
          y: tasks.dropY - 1.5
          width: parent.width; height: 3; radius: 1.5
          color: tasks.cc.ink
        }
        delegate: Rectangle {
          id: subRow
          required property var modelData
          required property int index
          readonly property bool sel: tasks.pane === "subs" && index === tasks.subIndex
          width: subList.width
          height: Math.max(30, subText.implicitHeight + 12)
          radius: 10
          color: sel ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.3)
          border.color: tasks.cc.ink
          border.width: sel ? 2 : 0
          StateBox {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            state3: subRow.modelData.state
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
              onClicked: tasks.cycle(tasks.selected, subRow.index) }
          }
          Text {
            id: subText
            visible: !(subEdit.activeFocus && subEdit.index === subRow.index)
            x: 32; width: parent.width - x - 8
            anchors.verticalCenter: parent.verticalCenter
            text: subRow.modelData.text
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: tasks.cc.ink
            opacity: subRow.modelData.state === "done" ? 0.5 : 1
            font.strikeout: subRow.modelData.state === "done"
            font.italic: subRow.modelData.state === "doing"
            font.family: tasks.cc.font
            font.pixelSize: 12
          }
          opacity: tasks.dragSub === index ? 0.45 : 1
          MouseArea {
            anchors.fill: parent; anchors.leftMargin: 28
            preventStealing: true
            cursorShape: tasks.dragSub >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            property real pressY: 0
            property bool dragging: false
            function target(mouse) {
              var p = mapToItem(subList.contentItem, mouse.x, mouse.y)
              var i = subList.indexAt(20, p.y)
              if (i < 0) i = p.y < 0 ? 0 : subList.count - 1
              return i
            }
            onPressed: mouse => { pressY = mouse.y; dragging = false }
            onPositionChanged: mouse => {
              if (!(mouse.buttons & Qt.LeftButton)) return
              if (!dragging && Math.abs(mouse.y - pressY) > 6) { dragging = true; tasks.dragSub = subRow.index; tasks.pane = "subs" }
              if (dragging) {
                var it = subList.itemAtIndex(target(mouse))
                var down = target(mouse) > subRow.index
                tasks.dropY = it ? (down ? it.y + it.height + 2 : it.y - 3) - subList.contentY : -1
              }
            }
            onReleased: mouse => {
              if (!dragging) return
              dragging = false
              var to = target(mouse)
              if (to !== subRow.index && tasks.selected) {
                tasks.act(["sub-move", tasks.selected.id, String(subRow.index), String(to)])
                tasks.subIndex = to
              }
              tasks.dragSub = -1
              tasks.dropY = -1
            }
            onClicked: { tasks.pane = "subs"; tasks.subIndex = subRow.index; tasks.forceActiveFocus() }
            onDoubleClicked: { subEdit.index = subRow.index; subEdit.text = subRow.modelData.text; subEdit.forceActiveFocus() }
          }
        }
      }
      // inline editor for a sub-todo (e / F2 / double-click)
      TextInput {
        id: subEdit
        property int index: -1
        visible: activeFocus
        x: subList.x + 32
        y: subList.y + (subList.itemAtIndex(index) ? subList.itemAtIndex(index).y - subList.contentY + 7 : 0)
        width: subList.width - 40
        color: tasks.cc.ink
        font.family: tasks.cc.font
        font.pixelSize: 12
        Rectangle { anchors.fill: parent; anchors.margins: -4; z: -1; radius: 6; color: Qt.rgba(1, 1, 1, 0.9); border.color: tasks.cc.ink }
        Keys.onReturnPressed: { if (tasks.selected && text.trim() !== "") tasks.act(["sub-edit", tasks.selected.id, String(index), text.trim()]); tasks.forceActiveFocus() }
        Keys.onEscapePressed: tasks.forceActiveFocus()
      }
    }
    Text {
      visible: tasks.selected === null
      x: todoLeft.width + 24; y: 30
      width: parent.width - x
      wrapMode: Text.Wrap
      text: "No todos yet. Type one on the left and press Enter — each opens into its own list of sub-todos."
      color: tasks.cc.ink; opacity: 0.7
      font.family: tasks.cc.font; font.pixelSize: 12
    }
  }
  property var subInput: null
  property var logInput: null
  property alias newInput: newField.input

  // ===================================================================== TASK LOG
  Item {
    id: logTab
    visible: tasks.tab === "log"
    y: tasks.contentTop
    width: parent.width
    height: parent.height - y

    ListView {
      id: logTodoList
      width: parent.width * 0.3
      height: parent.height
      clip: true
      spacing: 5
      model: tasks.logOrder
      delegate: Rectangle {
        required property var modelData
        readonly property bool sel: modelData.id === tasks.selectedId
        width: logTodoList.width
        height: 44
        radius: 12
        color: sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
        border.color: tasks.cc.ink
        border.width: sel ? 2.2 : 0
        Rectangle { width: 6; height: parent.height; radius: 3; color: tasks.colorOf(parent.modelData.group) }
        Column {
          x: 14; anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 22
          Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.title; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 12; font.bold: true }
          Text {
            width: parent.width; elide: Text.ElideRight
            text: (parent.parent.modelData.counts.doing ? " " + parent.parent.modelData.counts.doing + " in progress · " : "") + parent.parent.modelData.logCount + " log entries"
            color: tasks.cc.ink; opacity: 0.65; font.family: tasks.cc.font; font.pixelSize: 10
          }
        }
        MouseArea { anchors.fill: parent; onClicked: { tasks.selectedId = parent.modelData.id; tasks.forceActiveFocus() } }
      }
    }

    Item {
      x: logTodoList.width + 14
      width: parent.width - x
      height: parent.height
      visible: tasks.selected !== null

      // the sub-todos, shifting across as they're worked on
      Row {
        id: lanes
        width: parent.width
        height: 150
        spacing: 8
        Repeater {
          model: [["todo", "To do", ""], ["doing", "In progress", ""], ["done", "Done", ""]]
          Rectangle {
            required property var modelData
            width: (lanes.width - 16) / 3
            height: lanes.height
            radius: 14
            color: Qt.rgba(tasks.cc.paper.r, tasks.cc.paper.g, tasks.cc.paper.b, modelData[0] === "doing" ? 0.7 : 0.45)
            border.color: tasks.cc.ink
            border.width: modelData[0] === "doing" ? 1.8 : 1
            CcHeading { x: 10; y: 7; cc: tasks.cc; text: parent.modelData[2] + "  " + parent.modelData[1].toUpperCase() }
            ListView {
              x: 8; y: 26
              width: parent.width - 16
              height: parent.height - 32
              clip: true
              spacing: 3
              model: tasks.selected ? tasks.selected.subs.filter(function(s) { return s.state === parent.modelData[0] }) : []
              // click moves it a lane on, right-click a lane back
              delegate: Rectangle {
                id: laneItem
                required property var modelData
                readonly property bool sel: tasks.logPane === "lanes" && tasks.logSub === modelData.i
                width: ListView.view.width
                height: laneText.implicitHeight + 6
                radius: 6
                color: sel ? Qt.rgba(1, 1, 1, 0.8) : laneMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.45) : "transparent"
                border.color: tasks.cc.ink
                border.width: sel ? 1.6 : 0
                Text {
                  id: laneText
                  x: 4; y: 3
                  width: parent.width - 8
                  text: "• " + laneItem.modelData.text
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  color: tasks.cc.ink
                  font.family: tasks.cc.font
                  font.pixelSize: 11
                }
                MouseArea {
                  id: laneMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onClicked: mouse => {
                    tasks.logPane = "lanes"
                    tasks.logSub = laneItem.modelData.i
                    tasks.shift(tasks.selected, laneItem.modelData.i, mouse.button === Qt.RightButton ? -1 : 1)
                    tasks.forceActiveFocus()
                  }
                }
              }
            }
          }
        }
      }

      Field {
        id: logField
        y: lanes.height + 10
        width: parent.width
        placeholder: "write in the log…  (w)"
        onAccepted: t => { if (tasks.selected) tasks.act(["log", tasks.selected.id, t, "--by", "you"]) }
        Component.onCompleted: logInput = logField.input
      }
      CcHeading { y: lanes.height + 50; cc: tasks.cc; text: "  LOG" + (tasks.logEntries.length ? " — " + tasks.logEntries.length + " ENTRIES, NEWEST FIRST" : "") }
      ListView {
        id: logList
        y: lanes.height + 70
        width: parent.width
        height: parent.height - y
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: tasks.logEntries
        delegate: Rectangle {
          required property var modelData
          width: logList.width
          height: entryText.implicitHeight + 34
          radius: 12
          color: Qt.rgba(1, 1, 1, 0.5)
          Text {
            x: 10; y: 6
            text: parent.modelData.time + (parent.modelData.by ? "  ·  " + parent.modelData.by : "")
            color: tasks.cc.ink; opacity: 0.7
            font.family: tasks.cc.font; font.pixelSize: 10; font.bold: true
          }
          Text {
            id: entryText
            x: 10; y: 22
            width: parent.width - 20
            text: parent.modelData.text
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            color: tasks.cc.ink
            font.family: tasks.cc.font
            font.pixelSize: 12
          }
        }
        Text {
          visible: tasks.logEntries.length === 0
          width: parent.width
          wrapMode: Text.Wrap
          text: "Nothing logged yet. Agents and scripts add entries with\n  slime-tasks log <id> \"…\"   and move sub-todos with   slime-tasks start/finish <id> <n>."
          color: tasks.cc.ink; opacity: 0.65
          font.family: tasks.cc.font; font.pixelSize: 11
        }
      }
    }
  }

  // ===================================================================== PROGRESS
  Item {
    id: progressTab
    visible: tasks.tab === "progress"
    y: tasks.contentTop
    width: parent.width
    height: parent.height - y

    ListView {
      id: progressList
      width: parent.width
      height: parent.height - archiveBox.height - 10
      clip: true
      spacing: 4
      boundsBehavior: Flickable.StopAtBounds
      model: tasks.progressRows
      delegate: Rectangle {
        id: prow
        required property var modelData
        required property int index
        readonly property int navIndex: {
          var n = 0
          for (var i = 0; i < index; i++) if (tasks.progressRows[i].kind !== "sub") n++
          return n
        }
        readonly property bool sel: modelData.kind !== "sub" && navIndex === tasks.progressIndex
        readonly property real indent: modelData.kind === "group" ? 0 : modelData.kind === "todo" ? 18 : 44
        x: indent
        width: progressList.width - indent
        height: modelData.kind === "sub" ? 24 : 36
        radius: 12
        color: modelData.kind === "sub" ? "transparent" : sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
        border.color: tasks.cc.ink
        border.width: sel ? 2 : 0

        // group
        Row {
          visible: prow.modelData.kind === "group"
          x: 10; anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text { text: tasks.expanded["g:" + prow.modelData.name] === false ? "" : ""; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
          Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(prow.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: prow.modelData.name !== "" }
          Text { text: !prow.modelData.name ? "No group" : prow.modelData.name; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: 15; anchors.verticalCenter: parent.verticalCenter }
          Text { text: prow.modelData.kind !== "group" ? "" : prow.modelData.count + (prow.modelData.count === 1 ? " todo" : " todos"); color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        }
        // todo
        Row {
          visible: prow.modelData.kind === "todo"
          x: 10; anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text { text: prow.modelData.kind === "todo" && prow.modelData.t.subs.length ? (tasks.expanded["t:" + prow.modelData.t.id] ? "" : "") : " "; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 9; anchors.verticalCenter: parent.verticalCenter }
          Text {
            width: prow.width * 0.4
            elide: Text.ElideRight
            text: prow.modelData.kind === "todo" ? prow.modelData.t.title : ""
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 12; font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        // sub
        Row {
          visible: prow.modelData.kind === "sub"
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          StateBox { state3: prow.modelData.kind === "sub" ? prow.modelData.s.state : "todo"; anchors.verticalCenter: parent.verticalCenter; scale: 0.8 }
          Text {
            text: prow.modelData.kind === "sub" ? prow.modelData.s.text : ""
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 11
            opacity: prow.modelData.kind === "sub" && prow.modelData.s.state === "done" ? 0.55 : 1
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        // progress bar and percentage (groups and todos)
        Meter {
          visible: prow.modelData.kind !== "sub"
          anchors.right: pctText.left; anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width * 0.3
          value: prow.modelData.kind === "group" ? prow.modelData.pct : prow.modelData.kind === "todo" ? tasks.pct(prow.modelData.t) : 0
          fill: prow.modelData.kind === "group" && prow.modelData.name !== "" ? tasks.colorOf(prow.modelData.name) : tasks.cc.ink
        }
        Text {
          id: pctText
          visible: prow.modelData.kind !== "sub"
          anchors.right: archiveBtn.visible ? archiveBtn.left : parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          width: 38
          horizontalAlignment: Text.AlignRight
          text: Math.round(100 * (prow.modelData.kind === "group" ? prow.modelData.pct : prow.modelData.kind === "todo" ? tasks.pct(prow.modelData.t) : 0)) + "%"
          color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 12; font.bold: true
        }
        CcButton {
          id: archiveBtn
          visible: prow.modelData.kind === "todo" && tasks.pct(prow.modelData.t) >= 1
          cc: tasks.cc
          anchors.right: parent.right; anchors.rightMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          icon: ""; text: "archive"; fontSize: 10
          onClicked: tasks.act(["archive", prow.modelData.t.id])
        }
        MouseArea {
          anchors.fill: parent
          anchors.rightMargin: archiveBtn.visible ? archiveBtn.width + 10 : 0
          enabled: prow.modelData.kind !== "sub"
          onClicked: { tasks.progressIndex = prow.navIndex; tasks.toggleExpand(prow.modelData); tasks.forceActiveFocus() }
        }
      }
    }

    // the archive: search it, bring lists back
    Rectangle {
      id: archiveBox
      y: parent.height - height
      width: parent.width
      height: 150
      radius: 16
      color: Qt.rgba(tasks.cc.paper.r, tasks.cc.paper.g, tasks.cc.paper.b, 0.5)
      border.color: tasks.cc.ink
      border.width: 1
      Row {
        x: 12; y: 10
        spacing: 10
        CcHeading { cc: tasks.cc; text: "  ARCHIVE (" + tasks.archivedTodos.length + ")"; anchors.verticalCenter: parent.verticalCenter }
        Field {
          id: archiveField
          width: 260
          placeholder: "search the archive…  (/)"
          input.onTextChanged: tasks.archiveQuery = input.text
          Component.onCompleted: archiveInput = archiveField.input
        }
      }
      ListView {
        x: 12; y: 48
        width: parent.width - 24
        height: parent.height - 56
        clip: true
        spacing: 4
        model: tasks.archivedTodos
        delegate: Item {
          required property var modelData
          width: ListView.view.width
          height: 28
          Rectangle { width: 6; height: 20; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(parent.modelData.group) }
          Text {
            x: 14; width: parent.width - restoreBtn.width - 24
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: parent.modelData.title + (parent.modelData.group ? "  ·  " + parent.modelData.group : "") + "  ·  " + parent.modelData.counts.done + "/" + parent.modelData.subs.length
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 12
          }
          CcButton {
            id: restoreBtn
            cc: tasks.cc
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: ""; text: "restore"; fontSize: 10
            onClicked: tasks.act(["unarchive", parent.modelData.id], function(r) { tasks.selectedId = r.id; tasks.tab = "todo" })
          }
        }
      }
    }
  }
  property var archiveInput: null

  // ============================================================ right-click / g menu
  Rectangle {
    id: menu
    property var todo: null
    property int index: 0
    readonly property var groupNames: Object.keys(tasks.groupColors).sort()
    // items: each group, "no group", then actions
    readonly property var items: groupNames.map(function(g) { return { kind: "group", name: g } })
      .concat([{ kind: "group", name: "" }, { kind: "rename" }, { kind: "archive" }, { kind: "delete" }])
    visible: false
    z: 50
    width: 230
    height: menuCol.implicitHeight + 20
    radius: 14
    color: tasks.cc.paper
    border.color: tasks.cc.ink
    border.width: 2
    function run(it) {
      if (!todo) return
      if (it.kind === "group") tasks.act(["group", todo.id, it.name])
      else if (it.kind === "rename") { renameInput.text = todo.title; tasks.selectedId = todo.id; visible = false; renameInput.forceActiveFocus(); return }
      else if (it.kind === "archive") tasks.act(["archive", todo.id])
      else if (it.kind === "delete") tasks.act(["delete", todo.id])
      visible = false
      tasks.forceActiveFocus()
    }
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape) { visible = false; tasks.forceActiveFocus() }
      else if (event.key === Qt.Key_Up || event.text === "k") index = Math.max(0, index - 1)
      else if (event.key === Qt.Key_Down || event.text === "j") index = Math.min(items.length - 1, index + 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) run(items[index])
      else if (event.text === "n") groupInput.forceActiveFocus()
      else return
      event.accepted = true
    }
    Column {
      id: menuCol
      x: 10; y: 10
      width: parent.width - 20
      spacing: 3
      CcHeading { cc: tasks.cc; text: "GROUP" }
      Repeater {
        model: menu.items
        Rectangle {
          required property var modelData
          required property int index
          width: menuCol.width
          height: 24
          radius: 8
          color: index === menu.index ? Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.15) : "transparent"
          Row {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle { visible: parent.parent.modelData.kind === "group" && parent.parent.modelData.name !== ""; width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(parent.parent.modelData.name) }
            Text {
              text: {
                var it = parent.parent.modelData
                if (it.kind === "group") return (it.name === "" ? "no group" : it.name) + (menu.todo && menu.todo.group === it.name ? "  " : "")
                return it.kind === "rename" ? "  rename" : it.kind === "archive" ? "  archive" : "  delete"
              }
              color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 12
            }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: menu.run(parent.modelData) }
        }
      }
      Field {
        width: menuCol.width
        placeholder: "new group…  (n)"
        onAccepted: t => { if (menu.todo) tasks.act(["group", menu.todo.id, t]); menu.visible = false; tasks.forceActiveFocus() }
        Component.onCompleted: groupInput = input
      }
    }
  }
  property var groupInput: null
  // click away closes the menu
  MouseArea {
    anchors.fill: parent
    z: 49
    visible: menu.visible
    onClicked: { menu.visible = false; tasks.forceActiveFocus() }
  }

  // ================================================================ keys help
  Rectangle {
    visible: tasks.showHelp
    z: 60
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 620)
    height: helpText.implicitHeight + 30
    radius: 16
    color: tasks.cc.paper
    border.color: tasks.cc.ink
    border.width: 2
    Column {
      id: helpText
      x: 16; y: 15
      width: parent.width - 32
      spacing: 8
      Repeater {
        model: [
          ["", [["Tab / 1 2 3", "switch tabs"], ["?", "this help"], ["Esc", "back out, or close the command centre"]]],
          ["TODO · LIST", [["↑ ↓  j k", "pick a todo"], ["→  Enter", "open its sub-todos"], ["n", "new todo"], ["a", "add a sub-todo"],
                           ["Space", "mark finished"], ["e  F2", "rename"], ["g", "group menu"], ["A", "archive"], ["d d", "delete"], ["f", "show / hide finished"],
                           ["J K  Shift ↑↓", "move a todo"], ["drag", "move (into another group, too)"]]],
          ["TODO · SUB-TODOS", [["↑ ↓", "pick"], ["Space  Enter", "to do → in progress → done"], ["a", "add"], ["e", "edit"],
                                ["d", "delete"], ["J K  Shift ↑↓  drag", "move down / up"], ["←  Esc", "back to the list"]]],
          ["TASK LOG", [["↑ ↓", "pick a todo"], ["→  Enter", "into its lanes"], ["→  Space  /  ←", "move a sub-todo a lane on / back"],
                        ["w", "write in the log"], ["PgUp PgDn", "scroll the log"], ["click / right-click", "a lane on / back"]]],
          ["PROGRESS", [["↑ ↓", "pick"], ["Enter  Space", "expand / collapse"], ["A", "archive"], ["/", "search the archive"]]]
        ]
        Column {
          required property var modelData
          width: helpText.width
          spacing: 2
          CcHeading { visible: parent.modelData[0] !== ""; cc: tasks.cc; text: parent.modelData[0] }
          Flow {
            width: parent.width
            spacing: 14
            Repeater {
              model: parent.parent.modelData[1]
              Row {
                required property var modelData
                spacing: 6
                Text { text: parent.modelData[0]; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 12; font.bold: true }
                Text { text: parent.modelData[1]; color: tasks.cc.ink; opacity: 0.75; font.family: tasks.cc.font; font.pixelSize: 12 }
              }
            }
          }
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Text boxes: Enter saves, Esc leaves. Your todos are plain markdown in " + tasks.folder.replace(/^\/home\/[^/]+/, "~") + " — open them in Envy or any notes app."
        color: tasks.cc.ink; opacity: 0.7
        font.family: tasks.cc.font; font.pixelSize: 11
      }
    }
    MouseArea { anchors.fill: parent; onClicked: tasks.showHelp = false }
  }
}
