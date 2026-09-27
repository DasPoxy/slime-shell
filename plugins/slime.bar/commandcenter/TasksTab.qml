import QtQuick
import QtQuick.Shapes
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
  property var groupOrder: []                 // hand-set group order (slime_tasks group-order)
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
  property string progressPane: "list"        // progress tab: list | archive
  property int logEntry: 0                    // which log entry, in the entries pane
  property string progressFollow: ""          // re-find this row after a move ("g:…" / "t:…")
  // logs by time (newest first) or in sections per sub-todo; remembered
  readonly property bool logBySub: !!(bar && bar.ccSections && bar.ccSections["tasks-log-by-sub"])
  function toggleLogSort() {
    if (!bar) return
    var m = Object.assign({}, bar.ccSections)
    if (logBySub) delete m["tasks-log-by-sub"]
    else m["tasks-log-by-sub"] = true
    bar.ccSections = m
    logEntry = 0
  }
  // what the log shows: entries, and (by sub-todo) a heading per section
  readonly property var logDisplay: {
    if (!logBySub || !selected) return logEntries.map(function(e) { return { kind: "entry", e: e } })
    var rows = [], used = {}
    selected.subs.forEach(function(sb, i) {
      var mine = logEntries.filter(function(e) { return e.sub === sb.text })
      if (!mine.length) return
      var shut = sectionFolded(sb.text)
      rows.push({ kind: "head", i: i, sub: sb, count: mine.length, collapsed: shut })
      mine.forEach(function(e) { used[logEntries.indexOf(e)] = true; if (!shut) rows.push({ kind: "entry", e: e, section: i }) })
    })
    var rest = logEntries.filter(function(e, n) { return !used[n] })
    if (rest.length) {
      var restShut = sectionFolded("")
      rows.push({ kind: "head", i: -1, sub: null, count: rest.length, collapsed: restShut })
      if (!restShut) rest.forEach(function(e) { rows.push({ kind: "entry", e: e, section: -1 }) })
    }
    return rows
  }
  // the keyboard's stops in the log: every entry, and (by sub-todo) every
  // section heading too
  readonly property var logEntryRows: {
    var out = []
    for (var i = 0; i < logDisplay.length; i++) out.push(i)
    return out
  }
  readonly property var logPicked: logEntryRows.length ? logDisplay[logEntryRows[Math.min(logEntry, logEntryRows.length - 1)]] : null
  function sectionOf(row) { return !row ? undefined : row.kind === "head" ? row.i : row.section }
  // by sub-todo: move a section (i.e. its sub-todo) past the next section
  function moveSection(dir) {
    var sec = sectionOf(logPicked)
    if (sec === undefined || sec < 0 || !selected) return
    var secs = []
    logDisplay.forEach(function(r) { if (r.kind === "head" && r.i >= 0) secs.push(r.i) })
    var at = secs.indexOf(sec), nb = secs[at + dir]
    if (nb === undefined) return
    act(["sub-move", selected.id, String(sec), String(nb)])
  }
  // ---- folding log sections (per todo and sub-todo, remembered) ----
  function sectionKey(subText) { return "tasks-log-sec:" + selectedId + ":" + subText }
  function sectionFolded(subText) { return !!(bar && bar.ccSections && bar.ccSections[sectionKey(subText)]) }
  function setSectionFolded(subText, shut) {
    if (!bar) return
    var m = Object.assign({}, bar.ccSections)
    if (shut) m[sectionKey(subText)] = true
    else delete m[sectionKey(subText)]
    bar.ccSections = m
  }
  function headText(row) { return row && row.sub ? row.sub.text : "" }
  // fold the picked row's section and rest on its heading
  function foldSectionOf(row) {
    var sec = sectionOf(row), txt = ""
    for (var i = 0; i < logDisplay.length; i++)
      if (logDisplay[i].kind === "head" && logDisplay[i].i === sec) { txt = headText(logDisplay[i]); break }
    setSectionFolded(txt, true)
    for (var j = 0; j < logDisplay.length; j++)
      if (logDisplay[j].kind === "head" && logDisplay[j].i === sec) { logEntry = j; return }
  }
  onProgressRowsChanged: {
    if (progressFollow === "") return
    var nav = progressRows.filter(function(r) { return r.kind !== "sub" })
    for (var i = 0; i < nav.length; i++) {
      var key = nav[i].kind === "group" ? "g:" + nav[i].name : "t:" + nav[i].t.id
      if (key === progressFollow) { progressIndex = i; progressFollow = ""; return }
    }
  }
  property int archiveIndex: 0
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
    sortGroups(names)
    var rows = []
    names.forEach(function(n) {
      var shut = groupCollapsed(n)
      rows.push({ kind: "group", name: n, count: byGroup[n].length, collapsed: shut })
      if (!shut) byGroup[n].forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    })
    // loose todos get a heading (and can fold away) only beside real groups
    var looseShut = names.length > 0 && groupCollapsed("")
    if (loose.length && names.length) rows.push({ kind: "group", name: "", count: loose.length, collapsed: looseShut })
    if (!looseShut) loose.forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    return rows
  }
  readonly property var todoOrder: todoRows.filter(function(r) { return r.kind === "todo" }).map(function(r) { return r.t.id })

  // ---- folding groups (remembered with the command centre's other sections) --
  // each tab remembers its own folds: scope "" (Todo), "progress", "log"
  function foldKey(name, scope) { return (scope ? "tasks-" + scope + "-group:" : "tasks-group:") + name }
  function groupCollapsed(name, scope) { return !!(bar && bar.ccSections && bar.ccSections[foldKey(name, scope)]) }
  function setGroupCollapsed(name, shut, scope) {
    if (!bar) return
    var m = Object.assign({}, bar.ccSections)
    if (shut) m[foldKey(name, scope)] = true
    else delete m[foldKey(name, scope)]
    bar.ccSections = m
  }
  // the keyboard cursor in the todo list: a todo's id, or "g:<group>" when
  // it's resting on a group heading ("" = on the selected todo)
  property string cursor: ""
  readonly property string cursorKey: cursor !== "" ? cursor : selectedId
  readonly property var todoNav: todoRows.map(function(r) { return r.kind === "group" ? "g:" + r.name : r.t.id })
  function moveCursor(d) {
    if (todoNav.length === 0) return
    var i = todoNav.indexOf(cursorKey)
    var key = todoNav[Math.max(0, Math.min(todoNav.length - 1, i < 0 ? 0 : i + d))]
    if (key.indexOf("g:") === 0) cursor = key
    else { cursor = ""; selectedId = key }
  }
  function toggleGroup(name) {
    var shut = !groupCollapsed(name)
    setGroupCollapsed(name, shut)
    if (shut && selected && (selected.group || "") === name) cursor = "g:" + name
  }

  // Task Log tab: grouped and ordered like the Todo tab (loose ones last)
  readonly property var logRows: {
    var byGroup = {}, names = [], loose = []
    todos.forEach(function(t) {
      if (t.group) {
        if (!byGroup[t.group]) { byGroup[t.group] = []; names.push(t.group) }
        byGroup[t.group].push(t)
      } else loose.push(t)
    })
    sortGroups(names)
    var rows = []
    names.forEach(function(n) {
      var shut = groupCollapsed(n, "log")
      rows.push({ kind: "group", name: n, count: byGroup[n].length, collapsed: shut })
      if (!shut) byGroup[n].forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    })
    var looseShut = names.length > 0 && groupCollapsed("", "log")
    if (loose.length && names.length) rows.push({ kind: "group", name: "", count: loose.length, collapsed: looseShut })
    if (!looseShut) loose.forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    return rows
  }
  property string logCursor: ""                // "g:<group>" on a heading, "" on the selected todo
  readonly property var logNav: logRows.map(function(r) { return r.kind === "group" ? "g:" + r.name : r.t.id })
  function moveLogCursor(d) {
    if (logNav.length === 0) return
    var i = logNav.indexOf(logCursor !== "" ? logCursor : selectedId)
    var key = logNav[Math.max(0, Math.min(logNav.length - 1, i < 0 ? 0 : i + d))]
    if (key.indexOf("g:") === 0) logCursor = key
    else { logCursor = ""; selectedId = key }
  }
  function toggleLogGroup(name) {
    var shut = !groupCollapsed(name, "log")
    setGroupCollapsed(name, shut, "log")
    if (shut && selected && (selected.group || "") === name) logCursor = "g:" + name
  }

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
    names.sort(function(a, b) { return (a === "") - (b === "") || tasks.groupRank(a) - tasks.groupRank(b) || a.localeCompare(b) })
    var rows = []
    names.forEach(function(n) {
      var list = byGroup[n], units = 0, done = 0
      list.forEach(function(t) {
        var u = Math.max(1, t.subs.length)
        units += u
        done += t.done ? u : t.counts.done
      })
      rows.push({ kind: "group", name: n, pct: units ? done / units : 0, count: list.length })
      if (tasks.groupCollapsed(n, "progress")) return
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
          tasks.groupOrder = r.groupOrder || []
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
  onSelectedIdChanged: { logEntries = []; subIndex = 0; logSub = 0; logEntry = 0; if (tab === "log") refresh() }
  onArchiveQueryChanged: { refresh(); archiveIndex = 0 }
  onArchivedTodosChanged: if (archiveIndex >= archivedTodos.length) archiveIndex = Math.max(0, archivedTodos.length - 1)
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
  // swap a todo (default: the selected one) with its neighbour in its group
  function nudgeTodo(dir, id) {
    var t = null
    for (var k = 0; k < todos.length; k++) if (todos[k].id === (id || selectedId)) t = todos[k]
    if (!t) return false
    var same = todos.filter(function(x) { return (x.group || "") === (t.group || "") }).map(function(x) { return x.id })
    var i = same.indexOf(t.id), j = i + dir
    if (i < 0 || j < 0 || j >= same.length) return false
    placeTodo(t.id, same[j], dir > 0, t.group || "")
    return true
  }
  // ---- group order (shared by every tab) ----
  function groupRank(n) { var i = groupOrder.indexOf(n); return i < 0 ? 100000 : i }
  function sortGroups(names) { names.sort(function(a, b) { return groupRank(a) - groupRank(b) || a.localeCompare(b) }) }
  function allGroupNames() {
    var seen = {}, out = []
    Object.keys(groupColors).concat(todos.map(function(t) { return t.group || "" })).forEach(function(n) {
      if (n && !seen[n]) { seen[n] = true; out.push(n) }
    })
    sortGroups(out)
    return out
  }
  function moveGroup(name, dir) {
    if (!name) return false                  // "no group" always sits last
    var order = allGroupNames(), i = order.indexOf(name), j = i + dir
    if (i < 0 || j < 0 || j >= order.length) return false
    order.splice(i, 1)
    order.splice(j, 0, name)
    act(["group-order"].concat(order))
    return true
  }
  // move a sub-todo past its neighbour in the same lane
  function moveInLane(t, i, dir) {
    var st = t.subs[i].state, j = i + dir
    while (j >= 0 && j < t.subs.length && t.subs[j].state !== st) j += dir
    if (j < 0 || j >= t.subs.length) return
    act(["sub-move", t.id, String(i), String(j)])
    logSub = j
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
    if (k === Qt.Key_Escape && !(tab === "todo" && pane === "subs") && !(tab === "log" && logPane !== "list")
        && !(tab === "progress" && progressPane === "archive") && !showHelp) {
      if (closeRequest) closeRequest()
      else if (bar) bar.commandCenterOpen = false
      event.accepted = true; return
    }
    if (k === Qt.Key_Escape && showHelp) { showHelp = false; event.accepted = true; return }
    if (tab === "todo") {
      var t = selected
      if (pane === "list" && cursor !== "") {
        // resting on a group heading
        var gname = cursor.slice(2)
        if ((up || down) && (event.modifiers & Qt.ShiftModifier)) moveGroup(gname, up ? -1 : 1)
        else if (up || down) moveCursor(up ? -1 : 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z") toggleGroup(gname)
        else if (k === Qt.Key_Right || txt === "l") { if (groupCollapsed(gname)) setGroupCollapsed(gname, false) }
        else if (k === Qt.Key_Left || txt === "h") { if (!groupCollapsed(gname)) setGroupCollapsed(gname, true) }
        else if (txt === "n") newInput.forceActiveFocus()
        else if (txt === "f") showDone = !showDone
        else return
      } else if (pane === "list") {
        var hasHead = t && todoNav.indexOf("g:" + (t.group || "")) >= 0
        if ((up || down) && (event.modifiers & Qt.ShiftModifier)) nudgeTodo(up ? -1 : 1)
        else if (up || down) moveCursor(up ? -1 : 1)
        // fold this todo's group away and rest on its heading
        else if ((k === Qt.Key_Left || txt === "h" || txt === "z") && hasHead) toggleGroup(t.group || "")
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
      var lt = selected, ln = lt ? lt.subs.length : 0, ne = logEntryRows.length
      var shiftMove = (up || down) && (event.modifiers & Qt.ShiftModifier)
      if (txt === "w" && lt) logInput.forceActiveFocus()
      else if (txt === "s") toggleLogSort()
      else if (k === Qt.Key_PageDown) logList.flick(0, -1600)
      else if (k === Qt.Key_PageUp) logList.flick(0, 1600)
      else if (logPane === "entries") {
        // the log itself (by sub-todo, its section headings fold like groups)
        var lp = logPicked, onHead = lp && lp.kind === "head"
        if (shiftMove) { if (logBySub) moveSection(up ? -1 : 1) }
        else if (up && logEntry <= 0) logPane = ln ? "lanes" : "list"
        else if (up) logEntry--
        else if (down) logEntry = Math.min(ne - 1, logEntry + 1)
        else if (onHead && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z")) setSectionFolded(headText(lp), !lp.collapsed)
        else if (onHead && (k === Qt.Key_Right || txt === "l")) setSectionFolded(headText(lp), false)
        else if (onHead && !lp.collapsed && (k === Qt.Key_Left || txt === "h")) setSectionFolded(headText(lp), true)
        else if (logBySub && lp && lp.kind === "entry" && (k === Qt.Key_Left || txt === "h" || txt === "z")) foldSectionOf(lp)
        else if (k === Qt.Key_Left || k === Qt.Key_Escape || txt === "h") logPane = "list"
        else return
      }
      else if (logPane === "list" && logCursor !== "") {
        // resting on a group heading
        var lg = logCursor.slice(2)
        if (shiftMove) moveGroup(lg, up ? -1 : 1)
        else if (up || down) moveLogCursor(up ? -1 : 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z") toggleLogGroup(lg)
        else if (k === Qt.Key_Right || txt === "l") setGroupCollapsed(lg, false, "log")
        else if (k === Qt.Key_Left || txt === "h") setGroupCollapsed(lg, true, "log")
        else return
      }
      else if (logPane === "list") {
        var logHead = lt && logNav.indexOf("g:" + (lt.group || "")) >= 0
        if (shiftMove) nudgeTodo(up ? -1 : 1)
        else if (up || down) moveLogCursor(up ? -1 : 1)
        else if ((k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter || txt === "l") && ln) { logPane = "lanes"; logSub = Math.min(logSub, ln - 1) }
        else if ((k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter || txt === "l") && ne) { logPane = "entries"; logEntry = 0 }
        else if ((k === Qt.Key_Left || txt === "h" || txt === "z") && logHead) toggleLogGroup(lt.group || "")
        else return
      } else {
        if (shiftMove && ln) moveInLane(lt, logSub, up ? -1 : 1)
        else if (up) logSub = Math.max(0, logSub - 1)
        else if (down && logSub >= ln - 1 && ne) { logPane = "entries"; logEntry = 0 }   // on into the log
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
      var na = archivedTodos.length
      if (txt === "/") archiveInput.forceActiveFocus()
      else if (progressPane === "list") {
        // down past the last row drops into the archive
        if ((up || down) && (event.modifiers & Qt.ShiftModifier) && r) {
          if (r.kind === "group" && moveGroup(r.name, up ? -1 : 1)) progressFollow = "g:" + r.name
          else if (r.kind === "todo" && nudgeTodo(up ? -1 : 1, r.t.id)) progressFollow = "t:" + r.t.id
        }
        else if (up) progressIndex = Math.max(0, progressIndex - 1)
        else if (down && progressIndex >= rows.length - 1 && na) { progressPane = "archive"; archiveIndex = Math.min(archiveIndex, na - 1) }
        else if (down) progressIndex = Math.min(rows.length - 1, progressIndex + 1)
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && r) toggleExpand(r)
        // same folding keys as the Todo tab
        else if (r && r.kind === "group" && (k === Qt.Key_Right || txt === "l")) setGroupCollapsed(r.name, false, "progress")
        else if (r && r.kind === "group" && (k === Qt.Key_Left || txt === "h")) setGroupCollapsed(r.name, true, "progress")
        else if (r && r.kind === "group" && txt === "z") toggleExpand(r)
        else if (r && r.kind === "todo" && (k === Qt.Key_Right || txt === "l")) { if (r.t.subs.length) setSubsOpen(r.t.id, true) }
        else if (r && r.kind === "todo" && (k === Qt.Key_Left || txt === "h")) {
          if (expanded["t:" + r.t.id]) setSubsOpen(r.t.id, false)
          else foldProgressGroupOf(r.t)
        }
        else if (r && r.kind === "todo" && txt === "z") foldProgressGroupOf(r.t)
        else if (txt === "A" && r && r.kind === "todo") act(["archive", r.t.id])
        else return
      } else {
        // up past the first archived list climbs back into the progress rows
        if (up && archiveIndex <= 0) { progressPane = "list"; progressIndex = Math.max(0, rows.length - 1) }
        else if (up) archiveIndex--
        else if (down) archiveIndex = Math.min(na - 1, archiveIndex + 1)
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "r") && na) {
          var a = archivedTodos[Math.min(archiveIndex, na - 1)]
          act(["unarchive", a.id], function(res) { tasks.selectedId = res.id; tasks.tab = "todo"; tasks.progressPane = "list" })
        }
        else if (k === Qt.Key_Escape) progressPane = "list"
        else return
      }
    }
    event.accepted = true
  }
  function toggleExpand(r) {
    if (r.kind === "group") { setGroupCollapsed(r.name, !groupCollapsed(r.name, "progress"), "progress"); return }
    setSubsOpen(r.t.id, !expanded["t:" + r.t.id])
  }
  function setSubsOpen(id, open) {
    var e = Object.assign({}, expanded)
    e["t:" + id] = open
    expanded = e
  }
  // fold a todo's group on the Progress tab and rest on its heading
  function foldProgressGroupOf(t) {
    var name = t.group || ""
    setGroupCollapsed(name, true, "progress")
    var nav = progressRows.filter(function(r) { return r.kind !== "sub" })
    for (var i = 0; i < nav.length; i++) if (nav[i].kind === "group" && nav[i].name === name) { progressIndex = i; return }
  }

  // ---- the tavern ----------------------------------------------------------------------
  readonly property color wood: Qt.darker(Qt.tint("#8a5a2e", Qt.rgba(cc.slime.r, cc.slime.g, cc.slime.b, 0.15)), 1.05)
  readonly property color woodLight: Qt.lighter(wood, 1.35)

  // ---- the tavern, deeper in: broken wall boards, a bar, a rack of mead -----
  // All of it sits under a film of goo (below), so it reads as a tavern the
  // slime has swallowed rather than a room you're standing in.
  component WoodPath: Shape {
    id: wp
    property string d: ""
    property color fill: tasks.wood
    property real line: 1.4
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: wp.fill
      strokeColor: tasks.cc.ink
      strokeWidth: wp.line
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: wp.d }
    }
  }
  // a barrel on its side, end-on: hoops, a mead mark, a tap
  component MeadBarrel: Item {
    id: mb
    property real size: 54
    width: size; height: size
    Rectangle { anchors.fill: parent; radius: width / 2; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.8 }
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.78; height: width; radius: width / 2; color: "transparent"; border.color: tasks.cc.ink; border.width: 1.2 }
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.52; height: width; radius: width / 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1 }
    Text { anchors.centerIn: parent; text: "M"; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.pixelSize: mb.size * 0.26 }
    Rectangle { x: parent.width / 2 - 3; y: parent.height * 0.86; width: 6; height: 9; radius: 2; color: tasks.cc.ink }
  }

  Item {
    id: tavernDeep
    anchors.fill: parent
    opacity: 0.5
    z: -1

    // broken wall boards: horizontal planks with snapped ends, nails, and
    // gaps where the goo shows through
    Repeater {
      model: [[0.02, 0.18, 0.30, 7], [0.36, 0.14, 0.22, 3], [0.64, 0.22, 0.33, 5], [0.05, 0.43, 0.20, 2],
              [0.30, 0.47, 0.28, 8], [0.72, 0.50, 0.24, 4], [0.12, 0.66, 0.26, 6], [0.58, 0.70, 0.18, 1]]
      Item {
        required property var modelData
        readonly property real bw: modelData[2] * tasks.width
        readonly property int seed: modelData[3]
        x: modelData[0] * tasks.width
        y: modelData[1] * tasks.height
        width: bw + 16; height: 22
        WoodPath {
          d: {
            var w = parent.bw, s = parent.seed
            // left end square, right end snapped into splinters
            return "M0 2 L" + w + " 2 L" + (w - 6 - s) + " 7 L" + (w + 6) + " 10 L" + (w - 4) + " 13 L" + (w + 2 - s % 3 * 3) + " 17 L0 18 Z"
          }
        }
        Rectangle { x: 6; y: 5; width: 3; height: 3; radius: 1.5; color: tasks.cc.ink }
        Rectangle { x: 6; y: 12; width: 3; height: 3; radius: 1.5; color: tasks.cc.ink }
        Rectangle { x: 14; y: 9; width: parent.bw * 0.5; height: 1; color: tasks.cc.ink; opacity: 0.35 }
      }
    }
    // holes knocked through the wall
    Repeater {
      model: [[0.48, 0.32, 46, 30], [0.20, 0.55, 34, 26], [0.84, 0.36, 40, 34]]
      WoodPath {
        required property var modelData
        anchors.fill: undefined
        x: modelData[0] * tasks.width; y: modelData[1] * tasks.height
        width: modelData[2]; height: modelData[3]
        fill: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.55)
        line: 1.2
        d: {
          var w = modelData[2], h = modelData[3]
          return "M" + w * 0.1 + " " + h * 0.3 + " L" + w * 0.35 + " 0 L" + w * 0.5 + " " + h * 0.22 + " L" + w * 0.8 + " " + h * 0.05
            + " L" + w + " " + h * 0.55 + " L" + w * 0.75 + " " + h + " L" + w * 0.4 + " " + h * 0.8 + " L0 " + h * 0.9 + " Z"
        }
      }
    }

    // the bar: a counter along the floor with taps and tankards on it
    Item {
      id: barCounter
      x: tasks.width * 0.2
      y: tasks.height - 78
      width: tasks.width * 0.5
      height: 78
      // back shelf with bottles
      Rectangle { y: -64; width: parent.width; height: 6; radius: 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1.2 }
      Repeater {
        model: 7
        Rectangle {
          required property int index
          x: 16 + index * (barCounter.width - 32) / 6
          y: -64 - height
          width: 9; height: 18 + (index * 7) % 9; radius: 3
          color: index % 3 === 0 ? tasks.cc.slime : index % 3 === 1 ? tasks.woodLight : tasks.cc.paper
          border.color: tasks.cc.ink; border.width: 1
          Rectangle { x: 2.5; y: -5; width: 4; height: 6; color: tasks.cc.ink }
        }
      }
      // counter top and front
      Rectangle { y: 10; width: parent.width; height: 12; radius: 4; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1.6 }
      Rectangle { x: 6; y: 22; width: parent.width - 12; height: parent.height - 22; color: tasks.wood; border.color: tasks.cc.ink; border.width: 1.6 }
      Repeater {
        model: 6
        Rectangle {
          required property int index
          x: 6 + (index + 1) * (barCounter.width - 12) / 7
          y: 22; width: 1.5; height: barCounter.height - 22
          color: tasks.cc.ink; opacity: 0.45
        }
      }
      // taps
      Repeater {
        model: 3
        Item {
          required property int index
          x: barCounter.width * (0.15 + index * 0.1)
          y: -12
          width: 12; height: 24
          Rectangle { x: 4; width: 4; height: 16; radius: 2; color: tasks.cc.paper; border.color: tasks.cc.ink; border.width: 1 }
          Rectangle { x: 1; y: 14; width: 10; height: 8; radius: 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1 }
        }
      }
      // tankards left on the bar
      Repeater {
        model: [0.52, 0.64, 0.83]
        SlimeGear {
          required property var modelData
          x: barCounter.width * modelData
          y: -12
          width: 24; height: 24; size: 24
          bar: tasks.bar
          kind: "mug"
        }
      }
    }

    // a rack of mead barrels on their sides, stacked three-two-one
    Item {
      id: meadRack
      x: 8
      y: tasks.height - height - 6
      width: 3 * 52 + 8
      height: 3 * 46 + 18
      Repeater {
        model: [[0, 2], [1, 2], [2, 2], [0.5, 1], [1.5, 1], [1, 0]]
        MeadBarrel {
          required property var modelData
          size: 50
          x: 4 + modelData[0] * 52
          y: modelData[1] * 44
        }
      }
      // the rack's legs
      Rectangle { x: 0; y: parent.height - 10; width: parent.width; height: 8; radius: 2; color: tasks.woodLight; border.color: tasks.cc.ink; border.width: 1.2 }
    }
  }

  // the goo the whole tavern is sunk in: a film of slime over it, lighter
  // toward the top, with bubbles rising through it
  Rectangle {
    anchors.fill: parent
    z: -1
    radius: 14
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(tasks.cc.slime.r, tasks.cc.slime.g, tasks.cc.slime.b, 0.10) }
      GradientStop { position: 1.0; color: Qt.rgba(tasks.cc.slime.r * 0.6, tasks.cc.slime.g * 0.6, tasks.cc.slime.b * 0.6, 0.30) }
    }
  }
  Repeater {
    model: 9
    Rectangle {
      required property int index
      readonly property real rise: ((tasks.bar ? tasks.bar.animTime : 0) * (0.035 + (index % 4) * 0.01) + index * 0.13) % 1
      z: -1
      x: ((index * 0.37 + 0.05) % 1) * tasks.width + Math.sin(rise * 8 + index) * 6
      y: tasks.height * (1 - rise)
      width: 5 + (index % 3) * 4; height: width; radius: width / 2
      color: "transparent"
      border.color: tasks.cc.paper; border.width: 1.2
      opacity: 0.5 * Math.sin(rise * Math.PI)
    }
  }

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
    property bool clearOnEnter: true
    signal accepted(string text)
    signal entered()
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
        if (field.clearOnEnter) text = ""
        if (t !== "") field.accepted(t)
        if (!field.keepFocus) tasks.forceActiveFocus()
        field.entered()
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
            if (tasks.todoRows[i].kind === "group" ? "g:" + tasks.todoRows[i].name === tasks.cursorKey
                : tasks.todoRows[i].t.id === tasks.cursorKey) return i
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
          // group header: click (or Enter / Space / ← → on it) folds it
          Rectangle {
            visible: row.modelData.kind === "group"
            anchors.fill: parent
            radius: 9
            readonly property bool here: row.modelData.kind === "group" && tasks.cursor === "g:" + row.modelData.name && tasks.pane === "list"
            color: here ? Qt.rgba(1, 1, 1, 0.6) : headMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
            border.color: tasks.cc.ink
            border.width: here ? 2 : 0
            Row {
              x: 6
              spacing: 6
              anchors.verticalCenter: parent.verticalCenter
              Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 9 }
              Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(row.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: !!row.modelData.name }
              CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: !row.modelData.name ? "NO GROUP" : row.modelData.name.toUpperCase() }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!row.modelData.collapsed
                text: row.modelData.count + (row.modelData.count === 1 ? " todo" : " todos")
                color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: 10
              }
            }
            MouseArea {
              id: headMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: row.modelData.kind === "group"
              onClicked: { tasks.pane = "list"; tasks.cursor = "g:" + row.modelData.name; tasks.toggleGroup(row.modelData.name); tasks.forceActiveFocus() }
            }
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
            border.width: sel ? (tasks.pane === "list" && tasks.cursor === "" ? 2.4 : 1.4) : 0
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
                    var first = null
                    for (var q = 0; q < tasks.todos.length && !first; q++)
                      if ((tasks.todos[q].group || "") === r.name && tasks.todos[q].id !== tasks.dragTodo) first = tasks.todos[q]
                    if (first) tasks.placeTodo(tasks.dragTodo, first.id, false, r.name)
                  } else {
                    tasks.placeTodo(tasks.dragTodo, r.t.id, p.y > it.y + it.height / 2, r.t.group || "")
                  }
                }
                tasks.dragTodo = ""
                tasks.dropY = -1
              }
              onClicked: mouse => {
                tasks.cursor = ""
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
      model: tasks.logRows
      delegate: Item {
        id: logRow
        required property var modelData
        width: logTodoList.width
        height: modelData.kind === "group" ? 24 : 44
        // group heading: click (or the keyboard) folds it
        Rectangle {
          visible: logRow.modelData.kind === "group"
          anchors.fill: parent
          radius: 9
          readonly property bool here: logRow.modelData.kind === "group" && tasks.logCursor === "g:" + logRow.modelData.name && tasks.logPane === "list"
          color: here ? Qt.rgba(1, 1, 1, 0.6) : logHeadMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
          border.color: tasks.cc.ink
          border.width: here ? 2 : 0
          Row {
            x: 6; spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.verticalCenter: parent.verticalCenter; text: logRow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 9 }
            Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(logRow.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: !!logRow.modelData.name }
            CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: !logRow.modelData.name ? "NO GROUP" : logRow.modelData.name.toUpperCase() }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!logRow.modelData.collapsed
              text: logRow.modelData.count + (logRow.modelData.count === 1 ? " todo" : " todos")
              color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: 10
            }
          }
          MouseArea {
            id: logHeadMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: logRow.modelData.kind === "group"
            onClicked: { tasks.logPane = "list"; tasks.logCursor = "g:" + logRow.modelData.name; tasks.toggleLogGroup(logRow.modelData.name); tasks.forceActiveFocus() }
          }
        }
        Rectangle {
        visible: logRow.modelData.kind === "todo"
        anchors.fill: parent
        readonly property var modelData: logRow.modelData.kind === "todo" ? logRow.modelData.t : ({ id: "", title: "", group: "", counts: { doing: 0 }, logCount: 0 })
        readonly property bool sel: modelData.id === tasks.selectedId
        radius: 12
        color: sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
        border.color: tasks.cc.ink
        border.width: sel ? (tasks.logCursor === "" ? 2.2 : 1.2) : 0
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
        MouseArea { anchors.fill: parent; onClicked: { tasks.logCursor = ""; tasks.selectedId = parent.modelData.id; tasks.forceActiveFocus() } }
        }
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
        // in the lanes, a note is about the sub-todo you've picked there
        readonly property var about: tasks.logPane === "lanes" && tasks.selected && tasks.selected.subs[tasks.logSub] ? tasks.selected.subs[tasks.logSub] : null
        placeholder: about ? "write in the log about “" + about.text + "”…  (w)" : "write in the log…  (w)"
        onAccepted: t => {
          if (!tasks.selected) return
          var args = ["log", tasks.selected.id, t, "--by", "you"]
          if (about) args = args.concat(["--sub", String(tasks.logSub)])
          tasks.act(args)
        }
        Component.onCompleted: logInput = logField.input
      }
      CcHeading {
        y: lanes.height + 50
        cc: tasks.cc
        text: "  LOG" + (tasks.logEntries.length ? " — " + tasks.logEntries.length + " ENTRIES, " + (tasks.logBySub ? "BY SUB-TODO" : "NEWEST FIRST") : "")
        font.underline: tasks.logPane === "entries"
      }
      CcButton {
        anchors.right: parent.right
        y: lanes.height + 44
        cc: tasks.cc
        icon: tasks.logBySub ? "\uf0ca" : "\uf017"
        text: tasks.logBySub ? "by sub-todo  (s)" : "newest first  (s)"
        fontSize: 10
        onClicked: { tasks.toggleLogSort(); tasks.forceActiveFocus() }
      }
      ListView {
        id: logList
        y: lanes.height + 70
        width: parent.width
        height: parent.height - y
        clip: true
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        model: tasks.logDisplay
        currentIndex: tasks.logPane === "entries" && tasks.logEntryRows.length ? tasks.logEntryRows[Math.min(tasks.logEntry, tasks.logEntryRows.length - 1)] : -1
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
          id: logItem
          required property var modelData
          required property int index
          width: logList.width
          height: modelData.kind === "head" ? 26 : entryBox.height
          // a sub-todo's section heading (by sub-todo): click, or the keys, fold it
          Rectangle {
            visible: logItem.modelData.kind === "head"
            anchors.fill: parent
            anchors.leftMargin: -4
            radius: 9
            readonly property bool picked: tasks.logPane === "entries" && logList.currentIndex === logItem.index
            color: picked ? Qt.rgba(1, 1, 1, 0.6) : secMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
            border.color: tasks.cc.ink
            border.width: picked ? 2 : 0
            MouseArea {
              id: secMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: logItem.modelData.kind === "head"
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                tasks.logPane = "entries"
                tasks.logEntry = logItem.index
                tasks.setSectionFolded(tasks.headText(logItem.modelData), !logItem.modelData.collapsed)
                tasks.forceActiveFocus()
              }
            }
          }
          Row {
            visible: logItem.modelData.kind === "head"
            x: 4
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.verticalCenter: parent.verticalCenter; text: logItem.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 9 }
            StateBox { anchors.verticalCenter: parent.verticalCenter; visible: !!logItem.modelData.sub; state3: logItem.modelData.sub ? logItem.modelData.sub.state : "todo" }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: logList.width - 50
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: logItem.modelData.kind !== "head" ? "" : (logItem.modelData.sub ? logItem.modelData.sub.text : "About the whole todo")
                + (logItem.modelData.collapsed ? "   ·   " + logItem.modelData.count + (logItem.modelData.count === 1 ? " entry" : " entries") : "")
              color: tasks.cc.ink
              font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: 13
            }
          }
          Rectangle {
          id: entryBox
          visible: logItem.modelData.kind === "entry"
          readonly property var modelData: logItem.modelData.kind === "entry" ? logItem.modelData.e : ({ time: "", by: "", sub: "", text: "" })
          readonly property bool picked: tasks.logPane === "entries" && logList.currentIndex === logItem.index
          x: tasks.logBySub ? 14 : 0
          width: logList.width - x
          height: entryText.implicitHeight + 54
          radius: 12
          color: Qt.rgba(1, 1, 1, picked ? 0.75 : 0.5)
          border.color: tasks.cc.ink
          border.width: picked ? 2 : 0
          Text {
            x: 10; y: 6
            text: parent.modelData.time + (parent.modelData.by ? "  ·  " + parent.modelData.by : "")
            color: tasks.cc.ink; opacity: 0.7
            font.family: tasks.cc.font; font.pixelSize: 10; font.bold: true
          }
          // what it's about: the todo, and the sub-todo if there is one
          Rectangle {
            x: 8; y: 21
            width: Math.min(parent.width - 16, aboutText.implicitWidth + 16)
            height: 18
            radius: 9
            color: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.12)
            Rectangle { x: 0; width: 5; height: parent.height; radius: 2.5; color: tasks.selected ? tasks.colorOf(tasks.selected.group) : "transparent" }
            Text {
              id: aboutText
              x: 9; anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 14
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: "\uf0ae  " + (tasks.selected ? tasks.selected.title : "") + (parent.parent.modelData.sub ? "   \u21b3  " + parent.parent.modelData.sub : "")
              color: tasks.cc.ink
              font.family: tasks.cc.font; font.pixelSize: 10; font.bold: true
            }
          }
          Text {
            id: entryText
            x: 10; y: 42
            width: parent.width - 20
            text: parent.modelData.text
            wrapMode: Text.Wrap
            textFormat: Text.MarkdownText
            color: tasks.cc.ink
            font.family: tasks.cc.font
            font.pixelSize: 12
          }
          MouseArea { anchors.fill: parent; onClicked: { tasks.logPane = "entries"; tasks.logEntry = tasks.logEntryRows.indexOf(logItem.index); tasks.forceActiveFocus() } }
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
        readonly property bool sel: modelData.kind !== "sub" && navIndex === tasks.progressIndex && tasks.progressPane === "list"
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
          Text { text: tasks.groupCollapsed(prow.modelData.name, "progress") ? "" : ""; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
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
          clearOnEnter: false
          onEntered: if (tasks.archivedTodos.length) { tasks.progressPane = "archive"; tasks.archiveIndex = 0 }
          input.onTextChanged: tasks.archiveQuery = input.text
          Component.onCompleted: archiveInput = archiveField.input
        }
      }
      ListView {
        id: archiveList
        x: 12; y: 48
        width: parent.width - 24
        height: parent.height - 56
        clip: true
        spacing: 4
        model: tasks.archivedTodos
        currentIndex: tasks.archiveIndex
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
          required property var modelData
          required property int index
          width: ListView.view.width
          height: 28
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -6; anchors.rightMargin: -2
            radius: 10
            visible: tasks.progressPane === "archive" && parent.index === tasks.archiveIndex
            color: Qt.rgba(1, 1, 1, 0.7)
            border.color: tasks.cc.ink; border.width: 2
          }
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
            onClicked: tasks.act(["unarchive", parent.modelData.id], function(r) { tasks.selectedId = r.id; tasks.tab = "todo"; tasks.progressPane = "list" })
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
                           ["J K  Shift ↑↓", "move a todo"], ["drag", "move (into another group, too)"],
                           ["←  z  (or click a heading)", "fold its group"], ["Enter  Space  →  on a heading", "fold / unfold"]]],
          ["TODO · SUB-TODOS", [["↑ ↓", "pick"], ["Space  Enter", "to do → in progress → done"], ["a", "add"], ["e", "edit"],
                                ["d", "delete"], ["J K  Shift ↑↓  drag", "move down / up"], ["←  Esc", "back to the list"]]],
          ["EVERYWHERE", [["Shift ↑↓", "move the highlighted todo, sub-todo, group or log section"]]],
          ["TASK LOG", [["↑ ↓", "pick a todo"], ["→ … ↓", "into the lanes, then on down into the log"], ["s", "log newest first / by sub-todo"], ["←  z  /  Enter  →  on a section", "fold / unfold it (by sub-todo)"], ["←  z  /  →  Enter on a heading", "fold / unfold its group"], ["→  Enter", "into its lanes"], ["→  Space  /  ←", "move a sub-todo a lane on / back"],
                        ["w", "write in the log (about the picked sub-todo)"], ["PgUp PgDn", "scroll the log"], ["click / right-click", "a lane on / back"]]],
          ["PROGRESS", [["↑ ↓", "pick"], ["Enter  Space", "expand / collapse"], ["→  ←", "open / close a todo, then fold its group"], ["z", "fold the group"], ["A", "archive"], ["↓ past the end", "into the archive"],
                        ["/", "search the archive (Enter: into the results)"], ["Enter  r", "restore an archived list"], ["↑ at the top  Esc", "back up"]]]
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
