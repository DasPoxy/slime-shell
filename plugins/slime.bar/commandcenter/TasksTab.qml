import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
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
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  property var cc: null
  readonly property var bar: cc ? cc.bar : null
  // set when shown somewhere other than the command centre (the pop-out)
  property var closeRequest: null
  readonly property string script: Qt.resolvedUrl("slime_tasks.py").toString().replace("file://", "")

  // ---- data -------------------------------------------------------------------
  property string folder: ""
  property var groupColors: ({})
  property var groupOrder: []                 // hand-set group order (slime_tasks group-order)
  property var supersMap: ({})                // super groups (groups of groups): {name: {color}}
  property var superOrderList: []
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
  // ---- one log entry, opened over the whole panel (Enter) ----
  property var viewEntry: null                // the entry being read
  property bool viewEditing: false
  property string copiedNote: ""
  function openEntry(e, edit) {
    viewEntry = e
    viewEditing = false
    if (edit) startEdit()
  }
  // ---- pictures on sub-todos ----
  // the pictures of the sub-todo open in the viewer (live, so adds show up)
  readonly property var viewPics: viewEntry && viewEntry.isSub && selected && selected.subs[viewEntry.n]
    ? selected.subs[viewEntry.n].images || [] : []
  property int picIndex: -1                   // the picked picture in the viewer
  property string zoomPic: ""                 // a picture shown over everything
  property int armedPic: -1                   // d once: waiting for the second d
  onViewPicsChanged: if (picIndex >= viewPics.length) picIndex = viewPics.length - 1
  // pictures fold open under their sub-todo in the list (remembered; open by default)
  function picsKey(t, sb) { return "tasks-pics-shut:" + (t ? t.id : "") + ":" + (sb ? sb.text : "") }
  function picsOpen(t, sb) { return !(bar && bar.ccSections && bar.ccSections[picsKey(t, sb)]) }
  function togglePics(t, sb) {
    if (!bar || !sb || !(sb.images || []).length) return
    var m = Object.assign({}, bar.ccSections), key = picsKey(t, sb)
    if (m[key]) delete m[key]; else m[key] = true
    bar.ccSections = m
  }
  function addPicture(t, n, file) {
    if (t && file) act(["sub-image-add", t.id, String(n), String(file)])
  }
  function removePicture(n, k) {
    if (selected) act(["sub-image-remove", selected.id, String(n), String(k)])
    armedPic = -1
  }
  Timer { id: disarmPic; interval: 2500; onTriggered: tasks.armedPic = -1 }
  // the file picker (a drip panel): which sub-todo it adds to
  property var pickFor: null                  // { id, n }
  function openPicker(t, n) {
    if (!t || !t.subs[n]) return
    pickFor = { id: t.id, n: n }
    picker.open()
  }

  // a sub-todo, opened over the whole panel the same way (Enter on it)
  function openSub(t, i, edit) {
    if (!t || !t.subs[i]) return
    var st = t.subs[i].state
    openEntry({ isSub: true, n: i, text: t.subs[i].text, by: "", sub: "", time: "",
                where: "sub-todo " + (i + 1) + "  ·  " + (st === "done" ? "done" : st === "doing" ? "in progress" : "to do") }, edit)
  }
  function copyEntry(e) {
    if (!e) return
    Quickshell.execDetached(["wl-copy", "--", e.text])
    copiedNote = "copied to the clipboard"
    copiedTimer.restart()
  }
  function startEdit() {
    if (!viewEntry) return
    viewEditing = true
    viewEditor.text = viewEntry.text
    viewEditor.forceActiveFocus()
    viewEditor.cursorPosition = viewEditor.text.length
  }
  function saveEdit() {
    if (!viewEntry || (!selected && viewEntry.id === undefined)) return
    var text = viewEditor.text.trim()
    if (text === "" || text === viewEntry.text) { viewEditing = false; forceActiveFocus(); return }
    var before = viewEntry.text, n = viewEntry.n
    if (viewEntry.isSub) act(["sub-edit", selected.id, String(n), text])
    else act(["log-edit", viewEntry.id !== undefined ? viewEntry.id : selected.id, String(n), text, "--expect", before])
    viewEntry = Object.assign({}, viewEntry, { text: text })
    viewEditing = false
    forceActiveFocus()
  }
  function closeEntry() { viewEntry = null; viewEditing = false; picIndex = -1; zoomPic = ""; armedPic = -1; forceActiveFocus() }
  // L: straight to the selected todo's log (first entry), from either tab
  property bool jumpToLog: false
  function firstEntryRow() {
    for (var i = 0; i < logDisplay.length; i++)
      if (logDisplay[i].kind === "entry" && (!logWide || logDisplay[i].e.id === selectedId)) return i
    for (var j = 0; j < logDisplay.length; j++) if (logDisplay[j].kind === "entry") return j
    return 0
  }
  // L in the Task Log: straight to the highlighted super group's, group's,
  // todo's or sub-todo's section of the log (switching the log's view to one
  // that has that section, and unfolding the way there)
  property var logJumpTo: null                // {what, name} of the heading to land on
  // L on the Todo tab: over to the Task Log with the same thing highlighted
  // there (super group, group, todo or sub-todo), then on to its section
  function jumpLogFromTodo(what, name) {
    tab = "log"
    if (what === "super" || what === "group") { logPane = "list"; logCursor = (what === "super" ? "s:" : "g:") + name }
    else if (what === "sub") { logPane = "lanes"; logCursor = ""; logSub = name }
    else { logPane = "list"; logCursor = "" }
    jumpLogHere()
  }
  function jumpLogHere() {
    var what = "", name = "", mode = logMode, vals = []
    if (logPane === "list" && logCursor.indexOf("s:") === 0) {
      what = "super"; name = logCursor.slice(2); mode = "super"; vals = [name]
    } else if (logPane === "list" && logCursor.indexOf("g:") === 0) {
      what = "group"; name = logCursor.slice(2)
      mode = logMode === "super" ? "super" : "group"
      vals = mode === "super" ? [superOf(name), name] : [name]
    } else if (logPane === "lanes" && selected && selected.subs[logSub]) {
      what = "sub"; name = logSub; mode = "sub"
    } else if (selected && logWide) {
      what = "todo"; name = selected.id
      var g = selected.group
      vals = logMode === "super" ? [superOf(g), g, name] : logMode === "group" ? [g, name] : [name]
    } else { jumpLog(); return }
    // the view, and every fold on the way down, in one go
    var m = Object.assign({}, bar.ccSections)
    delete m["tasks-log-by-sub"]
    m["tasks-log-mode"] = mode
    if (what === "sub") delete m[sectionKey(selected.subs[logSub].text)]
    else {
      var levels = mode === "super" ? ["super", "group", "todo"] : mode === "group" ? ["group", "todo"] : ["todo"]
      var path = ""
      vals.forEach(function(v, i) {
        delete m["tasks-log-sec:" + mode + ":" + path + "/" + levels[i] + ":" + v]
        path += "/" + v
      })
    }
    bar.ccSections = m
    logJumpTo = { what: what, name: name }
    tryLogJump()
  }
  function tryLogJump() {
    if (!logJumpTo) return
    for (var i = 0; i < logDisplay.length; i++) {
      var r = logDisplay[i]
      if (r.kind === "head" && r.what === logJumpTo.what && (r.what === "sub" ? r.i === logJumpTo.name : r.name === logJumpTo.name)) {
        logJumpTo = null
        logPane = "entries"
        logEntry = i
        // the section's heading at the top of the log, its entries below it
        Qt.callLater(function() { logList.positionViewAtIndex(i, ListView.Beginning) })
        return
      }
    }
    // not there (yet): wait for the log to load; if it has, there's nothing logged about it
    if (!(logWide ? logAllReader.running : logReader.running) && (logWide ? allLogEntries.length : true)) {
      if (logJumpTo.what === "sub") { logPane = "entries"; logEntry = 0 }
      logJumpTo = null
    }
  }
  function jumpLog() {
    if (!selected) return
    tab = "log"
    logCursor = ""
    logPane = "entries"
    logEntry = firstEntryRow()
    jumpToLog = true
    refresh()
  }
  onLogDisplayChanged: {
    if (jumpToLog && logDisplay.length) { logEntry = firstEntryRow(); jumpToLog = false }
    tryLogJump()
  }
  Timer { id: copiedTimer; interval: 1600; onTriggered: tasks.copiedNote = "" }
  property string progressFollow: ""          // re-find this row after a move ("g:…" / "t:…")
  // how the log is shown (s / S cycle it; remembered):
  //   time  - this todo's log, newest first      sub   - this todo's, by sub-todo
  //   todo  - every todo's log, by todo           group - by group › todo
  //   super - by super group › group › todo
  readonly property var logModes: ["time", "sub", "todo", "group", "super"]
  readonly property var logModeNames: ({ time: "newest first", sub: "by sub-todo", todo: "all · by todo", group: "all · by group", super: "all · by super group" })
  readonly property var logModeIcons: ({ time: "\uf017", sub: "\uf0ca", todo: "\uf0ae", group: "\uf07b", super: "\uf247" })
  readonly property string logMode: {
    var m = bar && bar.ccSections ? bar.ccSections["tasks-log-mode"] : ""
    if (logModes.indexOf(m) >= 0) return m
    return bar && bar.ccSections && bar.ccSections["tasks-log-by-sub"] ? "sub" : "time"
  }
  readonly property bool logBySub: logMode === "sub"
  readonly property bool logWide: logMode === "todo" || logMode === "group" || logMode === "super"
  property var allLogEntries: []              // every todo's log (the "all · …" views)
  function toggleLogSort(back) {
    if (!bar) return
    var m = Object.assign({}, bar.ccSections)
    delete m["tasks-log-by-sub"]
    m["tasks-log-mode"] = logModes[(logModes.indexOf(logMode) + (back ? logModes.length - 1 : 1)) % logModes.length]
    bar.ccSections = m
    logEntry = 0
  }
  onLogModeChanged: refresh()
  // the log's entries in the current view (the "all" views: newest first)
  readonly property var logShown: logWide
    ? allLogEntries.slice().sort(function(a, b) { return a.time < b.time ? 1 : a.time > b.time ? -1 : b.n - a.n })
    : logEntries
  // an entry's full tag: super group › group › todo  ↳ sub-todo
  function entryGroup(e) { return e.id !== undefined ? e.group : (selected ? selected.group : "") }
  function entryTag(e) {
    var grp = entryGroup(e)
    var title = e.id !== undefined ? e.title : (selected ? selected.title : "")
    var sup = grp ? superOf(grp) : ""
    return (sup ? sup + "  \u203a  " : "") + (grp ? grp + "  \u203a  " : "") + title + (e.sub ? "   \u21b3  " + e.sub : "")
  }
  // what the log shows: entries, and a heading per section (levels nest)
  readonly property var logDisplay: {
    var rows = []
    if (logWide) {
      // sections: super group › group › todo, as deep as the view goes;
      // sections come newest activity first, like the entries in them
      var levels = logMode === "super" ? ["super", "group", "todo"] : logMode === "group" ? ["group", "todo"] : ["todo"]
      var keyOf = function(e, what) { return what === "super" ? superOf(e.group) : what === "group" ? e.group : e.id }
      var build = function(list, depth, path) {
        if (depth === levels.length) {
          list.forEach(function(e) { rows.push({ kind: "entry", e: e, level: depth }) })
          return
        }
        var what = levels[depth], order = [], by = {}
        list.forEach(function(e) {
          var k = keyOf(e, what)
          if (!by[k]) { by[k] = []; order.push(k) }
          by[k].push(e)
        })
        // "not in a super group" / "no group" go last (sort isn't stable: keep first-seen order by hand)
        if (order.indexOf("") >= 0) { order.splice(order.indexOf(""), 1); order.push("") }
        order.forEach(function(k) {
          var mine = by[k], key = "tasks-log-sec:" + logMode + ":" + path + "/" + what + ":" + k
          var shut = sectionFolded(key)
          rows.push({ kind: "head", what: what, name: k, level: depth, key: key, count: mine.length, collapsed: shut,
                      label: what === "todo" ? mine[0].title : k !== "" ? k : what === "super" ? "Not in a super group" : "No group",
                      group: what === "todo" ? mine[0].group : what === "group" ? k : "" })
          if (!shut) build(mine, depth + 1, path + "/" + k)
        })
      }
      build(logShown, 0, "")
      return rows
    }
    if (!logBySub || !selected) return logEntries.map(function(e) { return { kind: "entry", e: e, level: 0 } })
    var used = {}
    selected.subs.forEach(function(sb, i) {
      var mine = logEntries.filter(function(e) { return e.sub === sb.text })
      if (!mine.length) return
      var key = sectionKey(sb.text), shut = sectionFolded(key)
      rows.push({ kind: "head", what: "sub", i: i, sub: sb, key: key, level: 0, label: sb.text, count: mine.length, collapsed: shut })
      mine.forEach(function(e) { used[logEntries.indexOf(e)] = true; if (!shut) rows.push({ kind: "entry", e: e, section: i, level: 1 }) })
    })
    var rest = logEntries.filter(function(e, n) { return !used[n] })
    if (rest.length) {
      var restKey = sectionKey(""), restShut = sectionFolded(restKey)
      rows.push({ kind: "head", what: "sub", i: -1, sub: null, key: restKey, level: 0, label: "About the whole todo", count: rest.length, collapsed: restShut })
      if (!restShut) rest.forEach(function(e) { rows.push({ kind: "entry", e: e, section: -1, level: 1 }) })
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
  function sectionFolded(key) { return !!(bar && bar.ccSections && bar.ccSections[key]) }
  function setSectionFolded(key, shut) {
    if (!bar || !key) return
    var m = Object.assign({}, bar.ccSections)
    if (shut) m[key] = true
    else delete m[key]
    bar.ccSections = m
  }
  // the heading a row sits under (-1: none)
  function parentHead(at) {
    var lv = logDisplay[at] ? logDisplay[at].level : 0
    for (var i = at - 1; i >= 0; i--)
      if (logDisplay[i].kind === "head" && logDisplay[i].level < lv) return i
    return -1
  }
  // fold the section the picked row is in, and rest on its heading; false if none
  function foldSectionOf(at) {
    var h = parentHead(at)
    if (h < 0) return false
    setSectionFolded(logDisplay[h].key, true)
    logEntry = h
    return true
  }
  onProgressRowsChanged: {
    if (progressFollow === "") return
    var nav = progressRows.filter(function(r) { return r.kind !== "sub" })
    for (var i = 0; i < nav.length; i++) {
      var key = nav[i].kind === "group" ? "g:" + nav[i].name : nav[i].kind === "super" ? "s:" + nav[i].name : "t:" + nav[i].t.id
      if (key === progressFollow) { progressIndex = i; progressFollow = ""; return }
    }
  }
  property int archiveIndex: 0               // a row of archiveRows (heading or todo)
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

  // ---- super groups: groups that hold other groups ----
  function superOf(g) {
    var sup = g && groupColors[g] ? groupColors[g].super : ""
    return sup && supersMap[sup] ? sup : ""
  }
  function superColor(n) { return supersMap[n] ? supersMap[n].color : tasks.cc.ink }
  function superRank(n) { var i = superOrderList.indexOf(n); return i < 0 ? 100000 : i }
  // the (sorted) group names arranged under their supers: each super (in
  // super order) followed by its groups, then the groups not in one
  function arrangeGroups(names) {
    var bySup = {}, sups = [], plain = []
    names.forEach(function(n) {
      var sp = n ? superOf(n) : ""
      if (sp) { if (!bySup[sp]) { bySup[sp] = []; sups.push(sp) } bySup[sp].push(n) }
      else plain.push(n)
    })
    sups.sort(function(a, b) { return superRank(a) - superRank(b) || a.localeCompare(b) })
    var out = []
    sups.forEach(function(sp) {
      out.push({ kind: "super", name: sp, members: bySup[sp] })
      bySup[sp].forEach(function(n) { out.push({ kind: "g", name: n, depth: 1 }) })
    })
    plain.forEach(function(n) { out.push({ kind: "g", name: n, depth: 0 }) })
    return out
  }
  function superCollapsed(n, scope) { return groupCollapsed("super:" + n, scope) }
  function setSuperCollapsed(n, shut, scope) { setGroupCollapsed("super:" + n, shut, scope) }
  function moveSuper(n, dir) {
    var all = Object.keys(supersMap)
    all.sort(function(a, b) { return superRank(a) - superRank(b) || a.localeCompare(b) })
    var i = all.indexOf(n), j = i + dir
    if (i < 0 || j < 0 || j >= all.length) return false
    all.splice(i, 1); all.splice(j, 0, n)
    act(["super-order"].concat(all))
    return true
  }
  // the keys on a super heading (same as a group's); true if handled
  function superKeys(n, scope, k, txt, up, down, shift, move) {
    if ((up || down) && shift) { moveSuper(n, up ? -1 : 1); return true }
    if (up || down) { move(up ? -1 : 1); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z") { setSuperCollapsed(n, !superCollapsed(n, scope), scope); return true }
    if (k === Qt.Key_Right || txt === "l") { setSuperCollapsed(n, false, scope); return true }
    if (k === Qt.Key_Left || txt === "h") { setSuperCollapsed(n, true, scope); return true }
    if (txt === "e" || k === Qt.Key_F2) { startRenameSuper(n); return true }
    if (txt === "A") { archiveSuper(n); return true }
    if (txt === "d" || k === Qt.Key_Delete) { deleteSuperKey(n); return true }
    if (txt === "g") { openSuperMenu(n, tasks.width * 0.2, 120); return true }
    return false
  }
  property string armedSuper: ""
  Timer { id: disarmSuper; interval: 2500; onTriggered: tasks.armedSuper = "" }
  function deleteSuperKey(n) {
    if (armedSuper !== n) { armedSuper = n; disarmSuper.restart(); return }
    armedSuper = ""
    act(["super-delete", n])
  }
  property bool renamingIsSuper: false
  function startRenameSuper(n) {
    renamingIsSuper = true
    renamingGroup = n
    renameGroupInput.text = n
    renameGroupInput.selectAll()
    renameGroupInput.forceActiveFocus()
  }
  function superHeadColor(n, here, hover) {
    return armedSuper !== "" && armedSuper === n ? Qt.rgba(1, 0.4, 0.4, 0.65)
      : here ? Qt.rgba(1, 1, 1, 0.65) : hover ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(1, 1, 1, 0.2)
  }

  // A super group's heading (Todo and Task Log lists)
  component SuperHead: Rectangle {
    id: sh
    property string name: ""
    property bool collapsed: false
    property int count: 0
    property bool here: false
    signal toggle()
    signal menu(real x, real y)
    radius: 10
    color: tasks.superHeadColor(name, here, shMouse.containsMouse)
    border.color: tasks.cc.ink
    border.width: here ? 2 : 1
    Rectangle { width: 7; height: parent.height; radius: 3.5; color: tasks.superColor(sh.name) }
    Row {
      x: 12; spacing: 7
      anchors.verticalCenter: parent.verticalCenter
      Text { anchors.verticalCenter: parent.verticalCenter; text: sh.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
      Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf247"; color: tasks.superColor(sh.name); style: Text.Outline; styleColor: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(13 * tasks.fs) }
      Text { anchors.verticalCenter: parent.verticalCenter; text: sh.name; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(14 * tasks.fs) }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: sh.collapsed
        text: sh.count + (sh.count === 1 ? " todo" : " todos")
        color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
    }
    MouseArea {
      id: shMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: mouse => {
        if (mouse.button === Qt.RightButton) { var p = mapToItem(tasks, mouse.x, mouse.y); sh.menu(p.x, p.y) }
        else sh.toggle()
      }
    }
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
    var rows = [], shutSuper = false
    arrangeGroups(names).forEach(function(it) {
      if (it.kind === "super") {
        shutSuper = superCollapsed(it.name, "")
        var c = 0
        it.members.forEach(function(m) { c += byGroup[m].length })
        rows.push({ kind: "super", name: it.name, count: c, collapsed: shutSuper })
        return
      }
      if (it.depth && shutSuper) return
      var n = it.name, shut = groupCollapsed(n)
      rows.push({ kind: "group", name: n, count: byGroup[n].length, collapsed: shut, depth: it.depth })
      if (!shut) byGroup[n].forEach(function(t) { rows.push({ kind: "todo", t: t, depth: it.depth }) })
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
  readonly property var todoNav: todoRows.map(function(r) { return r.kind === "group" ? "g:" + r.name : r.kind === "super" ? "s:" + r.name : r.t.id })
  function moveCursor(d) {
    if (todoNav.length === 0) return
    var i = todoNav.indexOf(cursorKey)
    var key = todoNav[Math.max(0, Math.min(todoNav.length - 1, i < 0 ? 0 : i + d))]
    if (key.indexOf("g:") === 0 || key.indexOf("s:") === 0) cursor = key
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
    var rows = [], shutSuper = false
    arrangeGroups(names).forEach(function(it) {
      if (it.kind === "super") {
        shutSuper = superCollapsed(it.name, "log")
        var c = 0
        it.members.forEach(function(m) { c += byGroup[m].length })
        rows.push({ kind: "super", name: it.name, count: c, collapsed: shutSuper })
        return
      }
      if (it.depth && shutSuper) return
      var n = it.name
      var shut = groupCollapsed(n, "log")
      rows.push({ kind: "group", name: n, count: byGroup[n].length, collapsed: shut, depth: it.depth })
      if (!shut) byGroup[n].forEach(function(t) { rows.push({ kind: "todo", t: t, depth: it.depth }) })
    })
    var looseShut = names.length > 0 && groupCollapsed("", "log")
    if (loose.length && names.length) rows.push({ kind: "group", name: "", count: loose.length, collapsed: looseShut })
    if (!looseShut) loose.forEach(function(t) { rows.push({ kind: "todo", t: t }) })
    return rows
  }
  property string logCursor: ""                // "g:<group>" on a heading, "" on the selected todo
  readonly property var logNav: logRows.map(function(r) { return r.kind === "group" ? "g:" + r.name : r.kind === "super" ? "s:" + r.name : r.t.id })
  function moveLogCursor(d) {
    if (logNav.length === 0) return
    var i = logNav.indexOf(logCursor !== "" ? logCursor : selectedId)
    var key = logNav[Math.max(0, Math.min(logNav.length - 1, i < 0 ? 0 : i + d))]
    if (key.indexOf("g:") === 0 || key.indexOf("s:") === 0) logCursor = key
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
    var rows = [], shutSuper = false
    function tally(list) {
      var units = 0, done = 0
      list.forEach(function(t) {
        var u = Math.max(1, t.subs.length)
        units += u
        done += t.done ? u : t.counts.done
      })
      return [units, done]
    }
    tasks.arrangeGroups(names).forEach(function(it) {
      if (it.kind === "super") {
        shutSuper = tasks.superCollapsed(it.name, "progress")
        var u = 0, d = 0, c = 0
        it.members.forEach(function(m) { var tl = tally(byGroup[m]); u += tl[0]; d += tl[1]; c += byGroup[m].length })
        rows.push({ kind: "super", name: it.name, pct: u ? d / u : 0, count: c, collapsed: shutSuper })
        return
      }
      if (it.depth && shutSuper) return
      var n = it.name, list = byGroup[n], tl = tally(list)
      rows.push({ kind: "group", name: n, pct: tl[0] ? tl[1] / tl[0] : 0, count: list.length, depth: it.depth })
      if (tasks.groupCollapsed(n, "progress")) return
      list.forEach(function(t) {
        rows.push({ kind: "todo", t: t, depth: it.depth })
        if (tasks.expanded["t:" + t.id]) t.subs.forEach(function(s) { rows.push({ kind: "sub", t: t, s: s, depth: it.depth }) })
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
          tasks.supersMap = r.supers || ({})
          tasks.superOrderList = r.superOrder || []
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
  Process {
    id: logAllReader
    command: ["python3", tasks.script, "log-all"]
    stdout: StdioCollector {
      onStreamFinished: { try { tasks.allLogEntries = JSON.parse(text).entries } catch (e) { tasks.allLogEntries = [] } }
    }
  }
  function refresh() {
    if (!lister.running) lister.running = true
    if (tab === "log" && logWide && !logAllReader.running) logAllReader.running = true
    if (tab === "log" && selectedId !== "" && !logReader.running) {
      logReader.command = ["python3", script, "log-show", selectedId]
      logReader.running = true
    }
    if (tab === "progress" && !archiveLister.running) archiveLister.running = true
  }
  onTabChanged: refresh()
  onSelectedIdChanged: { logEntries = []; subIndex = 0; logSub = 0; logEntry = 0; if (tab === "log") refresh() }
  onArchiveQueryChanged: { refresh(); archiveIndex = 0 }
  onArchiveRowsChanged: if (archiveIndex >= archiveRows.length) archiveIndex = Math.max(0, archiveRows.length - 1)
  // the archive, by group (in group order, loose ones last), then by title
  readonly property var archiveSorted: archivedTodos.slice().sort(function(a, b) {
    var ga = a.group || "", gb = b.group || "", sa = superOf(ga), sb = superOf(gb)
    return (sa === "") - (sb === "") || superRank(sa) - superRank(sb) || sa.localeCompare(sb)
      || (ga === "") - (gb === "") || groupRank(ga) - groupRank(gb) || ga.localeCompare(gb) || a.title.localeCompare(b.title)
  })
  // what the archive list shows: super group › group headings, then the todos
  readonly property var archiveRows: {
    var rows = [], lastSup = null, last = null, shead = null, head = null
    var named = archiveSorted.some(function(t) { return !!t.group })
    archiveSorted.forEach(function(t, i) {
      var g = t.group || "", sp = superOf(g)
      if (sp !== lastSup) {
        shead = sp ? { kind: "shead", name: sp, count: 0, collapsed: superCollapsed(sp, "archive") } : null
        if (shead) rows.push(shead)
        lastSup = sp; last = null
      }
      if (shead) shead.count++
      var hidden = shead && shead.collapsed
      if (named && g !== last) {
        head = { kind: "head", name: g, count: 0, depth: sp ? 1 : 0, collapsed: groupCollapsed(g, "archive") }
        if (!hidden) rows.push(head)
      }
      last = g
      if (head) head.count++
      if (!hidden && !(head && head.collapsed)) rows.push({ kind: "todo", t: t, i: i, depth: head ? head.depth : 0 })
    })
    return rows
  }
  // the super heading an archive row sits under (-1: none)
  function archiveSuperRow(at) {
    for (var i = at - 1; i >= 0; i--) {
      if (archiveRows[i].kind === "shead") return i
      if (archiveRows[i].kind === "head" && !archiveRows[i].depth) return -1
    }
    return -1
  }
  // fold the group an archived row belongs to and rest on its heading
  function foldArchiveGroupOf(t) {
    var g = t.group || ""
    setGroupCollapsed(g, true, "archive")
    for (var i = 0; i < archiveRows.length; i++)
      if (archiveRows[i].kind === "head" && archiveRows[i].name === g) { archiveIndex = i; return }
  }
  function restoreArchived(a) { if (a) act(["unarchive", a.id]) }   // stays in the archive: restore several in a row
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
  function hopLane(dir) {
    var t = selected, order = ["todo", "doing", "done"]
    if (!t || !t.subs.length) return
    var at = order.indexOf(t.subs[Math.min(logSub, t.subs.length - 1)].state)
    for (var step = 1; step <= 2; step++) {
      var st = order[(at + dir * step + 3) % 3]
      for (var i = 0; i < t.subs.length; i++) if (t.subs[i].state === st) { logSub = i; return }
    }
  }
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
  // the same menu on a group heading: archive or delete the whole group
  function openSuperMenu(name, x, y) {
    menu.archived = false
    menu.todo = null
    menu.headGroup = ""
    menu.headSuper = name
    menu.armed = ""
    menu.x = Math.max(0, Math.min(tasks.width - menu.width, x))
    menu.y = Math.max(50, Math.min(tasks.height - menu.height, y))
    menu.index = 0
    menu.visible = true
    menu.forceActiveFocus()
  }
  function openGroupMenu(name, x, y) {
    if (!name) return                         // "no group" isn't a group
    menu.archived = false
    menu.todo = null
    menu.headSuper = ""
    menu.headGroup = name
    menu.armed = ""
    menu.x = Math.max(0, Math.min(tasks.width - menu.width, x))
    menu.y = Math.max(50, Math.min(tasks.height - menu.height, y))
    menu.index = 0
    menu.visible = true
    menu.forceActiveFocus()
  }
  function archiveGroup(name) { if (name) act(["group-archive", name]) }
  function archiveSuper(name) { if (name) act(["super-archive", name]) }
  // restore a whole group (or super group) from the archive; you stay in the archive
  function restoreGroup(name) { act(["group-restore", name]) }
  function restoreSuper(name) { if (name) act(["super-restore", name]) }
  // ---- rename (e) / delete (d d) the highlighted group, on any tab ----
  property string armedGroup: ""             // waiting for the second d
  property string renamingGroup: ""
  Timer { id: disarmGroup; interval: 2500; onTriggered: tasks.armedGroup = "" }
  function deleteGroupKey(name) {
    if (!name) return
    if (armedGroup !== name) { armedGroup = name; disarmGroup.restart(); return }
    armedGroup = ""
    act(["group-delete", name])
  }
  function startRenameGroup(name) {
    if (!name) return
    renamingGroup = name
    renameGroupInput.text = name
    renameGroupInput.selectAll()
    renameGroupInput.forceActiveFocus()
  }
  function finishRenameGroup(to) {
    var from = renamingGroup
    var isSuper = renamingIsSuper
    renamingGroup = ""
    renamingIsSuper = false
    forceActiveFocus()
    if (!to || to === from) return
    if (isSuper) {
      if (bar && bar.ccSections) {
        var ms = Object.assign({}, bar.ccSections)
        ;["", "progress", "log"].forEach(function(sc) {
          if (ms[foldKey("super:" + from, sc)]) { delete ms[foldKey("super:" + from, sc)]; ms[foldKey("super:" + to, sc)] = true }
        })
        bar.ccSections = ms
      }
      if (cursor === "s:" + from) cursor = "s:" + to
      if (logCursor === "s:" + from) logCursor = "s:" + to
      act(["super-rename", from, to])
      return
    }
    // folds follow the group to its new name
    if (bar && bar.ccSections) {
      var m = Object.assign({}, bar.ccSections)
      ;["", "progress", "log", "archive"].forEach(function(sc) {
        if (m[foldKey(from, sc)]) { delete m[foldKey(from, sc)]; m[foldKey(to, sc)] = true }
      })
      bar.ccSections = m
    }
    if (cursor === "g:" + from) cursor = "g:" + to
    if (logCursor === "g:" + from) logCursor = "g:" + to
    act(["group-rename", from, to])
  }
  function headColor(name, here, hover) {
    return armedGroup !== "" && armedGroup === name ? Qt.rgba(1, 0.4, 0.4, 0.65)
      : here ? Qt.rgba(1, 1, 1, 0.6) : hover ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
  }
  function openMenu(t, x, y, archived) {
    menu.archived = !!archived
    menu.headGroup = ""
    menu.headSuper = ""
    menu.armed = ""
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
    // Ctrl+Tab and Alt+1…6 belong to the command centre (switch its tabs)
    if (((event.modifiers & Qt.ControlModifier) && (k === Qt.Key_Tab || k === Qt.Key_Backtab))
        || ((event.modifiers & Qt.AltModifier) && k >= Qt.Key_1 && k <= Qt.Key_9)) return
    if (viewEntry) {
      // the entry viewer takes the keys while it's open
      var pics = viewPics
      if (zoomPic !== "") { if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "q") zoomPic = "" }
      else if (k === Qt.Key_Escape && picIndex >= 0) { picIndex = -1; armedPic = -1 }
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || txt === "q") closeEntry()
      // pictures (a sub-todo's): p adds, ← → pick, Enter shows it big, d d removes
      else if (txt === "p" && viewEntry.isSub) openPicker(selected, viewEntry.n)
      else if ((k === Qt.Key_Right || txt === "l") && pics.length) { picIndex = Math.min(pics.length - 1, picIndex + 1); armedPic = -1 }
      else if ((k === Qt.Key_Left || txt === "h") && pics.length) { picIndex = Math.max(0, picIndex - 1); armedPic = -1 }
      else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && picIndex >= 0 && pics[picIndex]) zoomPic = pics[picIndex].file
      else if ((txt === "d" || k === Qt.Key_Delete) && picIndex >= 0 && pics[picIndex]) {
        if (armedPic !== picIndex) { armedPic = picIndex; disarmPic.restart() }
        else removePicture(viewEntry.n, picIndex)
      }
      else if (txt === "c") copyEntry(viewEntry)
      else if (txt === "e") startEdit()
      else if (k === Qt.Key_Down || txt === "j") viewFlick.flick(0, -700)
      else if (k === Qt.Key_Up || txt === "k") viewFlick.flick(0, 700)
      else if (k === Qt.Key_PageDown || k === Qt.Key_Space) viewFlick.flick(0, -2200)
      else if (k === Qt.Key_PageUp) viewFlick.flick(0, 2200)
      event.accepted = true
      return
    }
    if (txt === "?") { showHelp = !showHelp; event.accepted = true; return }
    // in the Task Log's lanes, Tab / Shift+Tab hop between the three lanes
    // (skipping empty ones), onto the first sub-todo there
    if ((k === Qt.Key_Tab || k === Qt.Key_Backtab) && tab === "log" && logPane === "lanes" && selected) {
      hopLane(k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
      event.accepted = true; return
    }
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
    if (showHelp && (k === Qt.Key_Left || k === Qt.Key_Right || txt === "h" || txt === "l")) {
      var order = [0, 1, 2, 4, 5, 3], at = order.indexOf(helpSection)
      helpSection = order[(at + (k === Qt.Key_Left || txt === "h" ? 5 : 1)) % 6]
      event.accepted = true; return
    }
    if (showHelp && (k === Qt.Key_Down || k === Qt.Key_Up || txt === "j" || txt === "k")) {
      helpFlick.contentY = Math.max(0, Math.min(helpFlick.contentHeight - helpFlick.height, helpFlick.contentY + (k === Qt.Key_Down || txt === "j" ? 60 : -60)))
      event.accepted = true; return
    }
    if (tab === "todo") {
      var t = selected
      if (pane === "list" && cursor.indexOf("s:") === 0) {
        // resting on a super group's heading
        if (txt === "L") jumpLogFromTodo("super", cursor.slice(2))
        else if (!superKeys(cursor.slice(2), "", k, txt, up, down, event.modifiers & Qt.ShiftModifier, moveCursor)) return
      } else if (pane === "list" && cursor !== "") {
        // resting on a group heading
        var gname = cursor.slice(2)
        if ((up || down) && (event.modifiers & Qt.ShiftModifier)) moveGroup(gname, up ? -1 : 1)
        else if (up || down) moveCursor(up ? -1 : 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z") toggleGroup(gname)
        else if (k === Qt.Key_Right || txt === "l") { if (groupCollapsed(gname)) setGroupCollapsed(gname, false) }
        else if (k === Qt.Key_Left || txt === "h") { if (!groupCollapsed(gname)) setGroupCollapsed(gname, true) }
        else if (txt === "g") openGroupMenu(gname, tasks.width * 0.2, 120)
        else if (txt === "e" || k === Qt.Key_F2) startRenameGroup(gname)
        else if (txt === "d" || k === Qt.Key_Delete) deleteGroupKey(gname)
        else if (txt === "A") archiveGroup(gname)
        else if (txt === "L") jumpLogFromTodo("group", gname)
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
        else if (txt === "L" && t) jumpLogFromTodo("todo", t.id)
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
        else if (k === Qt.Key_Space && t && n) cycle(t, subIndex)
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && t && n) openSub(t, subIndex, false)
        else if (txt === "a" && t) subInput.forceActiveFocus()
        else if (txt === "L" && t && n) jumpLogFromTodo("sub", subIndex)
        else if (txt === "p" && t && n) openPicker(t, subIndex)
        else if (txt === "i" && t && n) togglePics(t, t.subs[subIndex])
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
      else if (txt === "L") jumpLogHere()
      else if (txt === "s" || txt === "S") toggleLogSort(txt === "S")
      else if (k === Qt.Key_PageDown) logList.flick(0, -1600)
      else if (k === Qt.Key_PageUp) logList.flick(0, 1600)
      else if (logPane === "entries") {
        // the log itself (by sub-todo, its section headings fold like groups)
        var lp = logPicked, onHead = lp && lp.kind === "head"
        if (shiftMove) { if (logBySub) moveSection(up ? -1 : 1) }
        else if (up && logEntry <= 0) logPane = ln ? "lanes" : "list"
        else if (up) logEntry--
        else if (down) logEntry = Math.min(ne - 1, logEntry + 1)
        else if (onHead && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z")) setSectionFolded(lp.key, !lp.collapsed)
        else if (onHead && (k === Qt.Key_Right || txt === "l")) setSectionFolded(lp.key, false)
        else if (onHead && !lp.collapsed && (k === Qt.Key_Left || txt === "h")) setSectionFolded(lp.key, true)
        // ← on a folded heading: up to the heading it sits in (else back to the list)
        else if (onHead && (k === Qt.Key_Left || txt === "h") && parentHead(logEntryRows[logEntry]) >= 0) logEntry = parentHead(logEntryRows[logEntry])
        else if (lp && lp.kind === "entry" && (k === Qt.Key_Left || txt === "h" || txt === "z") && foldSectionOf(logEntryRows[logEntry])) {}
        else if (lp && lp.kind === "entry" && (k === Qt.Key_Return || k === Qt.Key_Enter)) openEntry(lp.e, false)
        else if (lp && lp.kind === "entry" && txt === "c") copyEntry(lp.e)
        else if (lp && lp.kind === "entry" && txt === "e") openEntry(lp.e, true)
        else if (k === Qt.Key_Left || k === Qt.Key_Escape || txt === "h") logPane = "list"
        else return
      }
      else if (logPane === "list" && logCursor.indexOf("s:") === 0) {
        if (!superKeys(logCursor.slice(2), "log", k, txt, up, down, shiftMove, moveLogCursor)) return
      }
      else if (logPane === "list" && logCursor !== "") {
        // resting on a group heading
        var lg = logCursor.slice(2)
        if (shiftMove) moveGroup(lg, up ? -1 : 1)
        else if (up || down) moveLogCursor(up ? -1 : 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z") toggleLogGroup(lg)
        else if (txt === "g") openGroupMenu(lg, tasks.width * 0.1, 120)
        else if (txt === "e" || k === Qt.Key_F2) startRenameGroup(lg)
        else if (txt === "d" || k === Qt.Key_Delete) deleteGroupKey(lg)
        else if (txt === "A") archiveGroup(lg)
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
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && ln) openSub(lt, logSub, false)
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
      else if (progressPane === "list" && r && r.kind === "super"
               && !(down && !(event.modifiers & Qt.ShiftModifier) && progressIndex >= rows.length - 1 && na)) {
        if ((up || down) && (event.modifiers & Qt.ShiftModifier)) progressFollow = "s:" + r.name
        if (!superKeys(r.name, "progress", k, txt, up, down, event.modifiers & Qt.ShiftModifier,
                       function(d) { progressIndex = Math.max(0, Math.min(rows.length - 1, progressIndex + d)) })) return
      }
      else if (progressPane === "list") {
        // down past the last row drops into the archive
        if ((up || down) && (event.modifiers & Qt.ShiftModifier) && r) {
          if (r.kind === "group" && moveGroup(r.name, up ? -1 : 1)) progressFollow = "g:" + r.name
          else if (r.kind === "todo" && nudgeTodo(up ? -1 : 1, r.t.id)) progressFollow = "t:" + r.t.id
        }
        else if (up) progressIndex = Math.max(0, progressIndex - 1)
        else if (down && progressIndex >= rows.length - 1 && na) { progressPane = "archive"; archiveIndex = Math.min(archiveIndex, archiveRows.length - 1) }
        else if (down) progressIndex = Math.min(rows.length - 1, progressIndex + 1)
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && r) toggleExpand(r)
        // same folding keys as the Todo tab
        else if (r && r.kind === "group" && (k === Qt.Key_Right || txt === "l")) setGroupCollapsed(r.name, false, "progress")
        else if (r && r.kind === "group" && (k === Qt.Key_Left || txt === "h")) setGroupCollapsed(r.name, true, "progress")
        else if (r && r.kind === "group" && txt === "z") toggleExpand(r)
        else if (r && r.kind === "group" && txt === "g") openGroupMenu(r.name, tasks.width * 0.3, 120)
        else if (r && r.kind === "group" && (txt === "e" || k === Qt.Key_F2)) startRenameGroup(r.name)
        else if (r && r.kind === "group" && (txt === "d" || k === Qt.Key_Delete)) deleteGroupKey(r.name)
        else if (r && r.kind === "group" && txt === "A") archiveGroup(r.name)
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
        var ar = archiveRows[Math.min(archiveIndex, archiveRows.length - 1)]
        var nr = archiveRows.length
        if (up && archiveIndex <= 0) { progressPane = "list"; progressIndex = Math.max(0, rows.length - 1) }
        else if (up) archiveIndex--
        else if (down) archiveIndex = Math.min(nr - 1, archiveIndex + 1)
        // on a super group's heading: fold / unfold, r restores all of it
        else if (ar && ar.kind === "shead" && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z")) setSuperCollapsed(ar.name, !ar.collapsed, "archive")
        else if (ar && ar.kind === "shead" && (k === Qt.Key_Right || txt === "l")) setSuperCollapsed(ar.name, false, "archive")
        else if (ar && ar.kind === "shead" && (k === Qt.Key_Left || txt === "h")) setSuperCollapsed(ar.name, true, "archive")
        else if (ar && ar.kind === "shead" && (txt === "r" || txt === "R")) restoreSuper(ar.name)
        else if (ar && ar.kind === "shead" && (txt === "e" || k === Qt.Key_F2)) startRenameSuper(ar.name)
        else if (ar && ar.kind === "shead" && (txt === "d" || k === Qt.Key_Delete)) deleteSuperKey(ar.name)
        // on a group's heading: fold / unfold, like everywhere else (r restores the group)
        else if (ar && ar.kind === "head" && (txt === "r" || txt === "R")) restoreGroup(ar.name)
        // ← on a folded group in a super group: up to the super group's heading
        else if (ar && ar.kind === "head" && ar.collapsed && (k === Qt.Key_Left || txt === "h") && archiveSuperRow(archiveIndex) >= 0) archiveIndex = archiveSuperRow(archiveIndex)
        else if (ar && ar.kind === "head" && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "z")) setGroupCollapsed(ar.name, !ar.collapsed, "archive")
        else if (ar && ar.kind === "head" && (k === Qt.Key_Right || txt === "l")) setGroupCollapsed(ar.name, false, "archive")
        else if (ar && ar.kind === "head" && (k === Qt.Key_Left || txt === "h")) setGroupCollapsed(ar.name, true, "archive")
        else if (ar && ar.kind === "head" && (txt === "e" || k === Qt.Key_F2)) startRenameGroup(ar.name)
        else if (ar && ar.kind === "head" && (txt === "d" || k === Qt.Key_Delete)) deleteGroupKey(ar.name)
        // on an archived todo
        else if (ar && ar.kind === "todo" && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || txt === "r")) restoreArchived(ar.t)
        else if (ar && ar.kind === "todo" && txt === "g") openMenu(ar.t, tasks.width * 0.3, tasks.height - 360, true)
        else if (ar && ar.kind === "todo" && (k === Qt.Key_Left || txt === "h" || txt === "z") && archiveRows.some(function(x) { return x.kind === "head" })) foldArchiveGroupOf(ar.t)
        else if (k === Qt.Key_Escape) progressPane = "list"
        else return
      }
    }
    event.accepted = true
  }
  function toggleExpand(r) {
    if (r.kind === "super") { setSuperCollapsed(r.name, !superCollapsed(r.name, "progress"), "progress"); return }
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
      font.pixelSize: 14 + index % 3 * 3 }
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
        font.pixelSize: Math.round(15 * tasks.fs) }
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
    text: tasks.error !== "" ? "  " + tasks.error
      : tasks.armedGroup !== "" ? "d again: delete group " + tasks.armedGroup + " (its todos are kept)"
      : tasks.armedSuper !== "" ? "d again: delete super group " + tasks.armedSuper + " (its groups are kept)" : "? keys"
    color: tasks.cc.ink
    opacity: tasks.error !== "" ? 1 : 0.55
    font.family: tasks.cc.font
    font.pixelSize: Math.round(11 * tasks.fs)
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
      font.pixelSize: Math.round(12 * tasks.fs)
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
      font.pixelSize: Math.round(8 * tasks.fs) }
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
            if (tasks.todoNav[i] === tasks.cursorKey) return i
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
          height: modelData.kind === "group" ? 24 : modelData.kind === "super" ? 28 : 38
          SuperHead {
            visible: row.modelData.kind === "super"
            anchors.fill: parent
            name: row.modelData.kind === "super" ? row.modelData.name : ""
            collapsed: !!row.modelData.collapsed
            count: row.modelData.count || 0
            here: row.modelData.kind === "super" && tasks.cursor === "s:" + row.modelData.name && tasks.pane === "list"
            onToggle: { tasks.pane = "list"; tasks.cursor = "s:" + name; tasks.setSuperCollapsed(name, !collapsed, ""); tasks.forceActiveFocus() }
            onMenu: (x, y) => { tasks.pane = "list"; tasks.cursor = "s:" + name; tasks.openSuperMenu(name, x, y) }
          }
          // group header: click (or Enter / Space / ← → on it) folds it
          Rectangle {
            visible: row.modelData.kind === "group"
            anchors.fill: parent
            radius: 9
            readonly property bool here: row.modelData.kind === "group" && tasks.cursor === "g:" + row.modelData.name && tasks.pane === "list"
            color: tasks.headColor(row.modelData.name, here, headMouse.containsMouse)
            border.color: tasks.cc.ink
            border.width: here ? 2 : 0
            Row {
              x: 6 + (row.modelData.depth || 0) * 16
              spacing: 6
              anchors.verticalCenter: parent.verticalCenter
              Text { anchors.verticalCenter: parent.verticalCenter; text: row.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
              Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(row.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: !!row.modelData.name }
              CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: !row.modelData.name ? "NO GROUP" : row.modelData.name.toUpperCase() }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!row.modelData.collapsed
                text: row.modelData.count + (row.modelData.count === 1 ? " todo" : " todos")
                color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
            }
            MouseArea {
              id: headMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: row.modelData.kind === "group"
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: mouse => {
                tasks.pane = "list"; tasks.cursor = "g:" + row.modelData.name; tasks.forceActiveFocus()
                if (mouse.button === Qt.RightButton) { var p = mapToItem(tasks, mouse.x, mouse.y); tasks.openGroupMenu(row.modelData.name, p.x, p.y) }
                else tasks.toggleGroup(row.modelData.name)
              }
            }
          }
          // a todo
          Rectangle {
            visible: row.modelData.kind === "todo"
            anchors.fill: parent
            anchors.leftMargin: (row.modelData.depth || 0) * 16
            readonly property var t: row.modelData.t
            readonly property bool sel: !!t && t.id === tasks.selectedId
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
              font.pixelSize: Math.round(13 * tasks.fs)
              font.bold: true
            }
            Text {
              id: countText
              anchors.right: parent.right; anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: parent.t && parent.t.subs.length ? parent.t.counts.done + "/" + parent.t.subs.length : ""
              color: tasks.cc.ink; opacity: 0.7
              font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs) }
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
            font.pixelSize: Math.round(18 * tasks.fs) }
          TextInput {
            id: renameInput
            visible: activeFocus
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            color: tasks.cc.ink
            font.family: tasks.cc.font
            font.pixelSize: Math.round(16 * tasks.fs)
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
            font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs) }
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
        // a change reloads the list (which scrolls back to the top): stay on
        // the sub-todo you were on
        onModelChanged: keepSub.restart()
        // (the reload resets currentIndex and breaks its binding: put both back)
        Timer {
          id: keepSub; interval: 40
          onTriggered: {
            subList.currentIndex = Qt.binding(function() { return tasks.subIndex })
            if (tasks.subIndex >= 0 && tasks.subIndex < subList.count) subList.positionViewAtIndex(tasks.subIndex, ListView.Contain)
          }
        }
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
          readonly property var pics: modelData.images || []
          readonly property bool picsShown: pics.length > 0 && tasks.picsOpen(tasks.selected, modelData)
          readonly property real textH: Math.max(30, subText.implicitHeight + 12)
          height: textH + (picsShown ? 72 : 0)
          radius: 10
          color: sel ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.3)
          border.color: tasks.cc.ink
          border.width: sel ? 2 : 0
          StateBox {
            x: 8; y: (subRow.textH - height) / 2
            state3: subRow.modelData.state
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
              onClicked: tasks.cycle(tasks.selected, subRow.index) }
          }
          Text {
            id: subText
            visible: !(subEdit.activeFocus && subEdit.index === subRow.index)
            x: 32; width: parent.width - x - 8 - (subRow.pics.length ? picChip.width + 6 : 0)
            y: (subRow.textH - implicitHeight) / 2
            text: subRow.modelData.text
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: tasks.cc.ink
            opacity: subRow.modelData.state === "done" ? 0.5 : 1
            font.strikeout: subRow.modelData.state === "done"
            font.italic: subRow.modelData.state === "doing"
            font.family: tasks.cc.font
            font.pixelSize: Math.round(12 * tasks.fs) }
          opacity: tasks.dragSub === index ? 0.45 : 1
          // its pictures: a chip that folds them (i), and a strip of thumbnails
          Rectangle {
            id: picChip
            z: 2
            visible: subRow.pics.length > 0
            anchors.right: parent.right; anchors.rightMargin: 6
            y: (subRow.textH - height) / 2
            width: chipText.implicitWidth + 14; height: 20; radius: 10
            color: chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.12)
            border.color: tasks.cc.ink; border.width: 1
            Text {
              id: chipText
              anchors.centerIn: parent
              text: "\uf03e " + subRow.pics.length + "  " + (subRow.picsShown ? "\uf077" : "\uf078")
              color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: true
            }
            MouseArea { id: chipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: tasks.togglePics(tasks.selected, subRow.modelData) }
          }
          Row {
            z: 2
            visible: subRow.picsShown
            x: 32; y: subRow.textH
            width: parent.width - x - 8
            height: 64
            spacing: 6
            clip: true
            Repeater {
              model: subRow.picsShown ? subRow.pics : []
              Rectangle {
                required property var modelData
                height: 64; width: Math.max(40, Math.min(140, thumb.implicitWidth > 0 ? 64 * thumb.implicitWidth / Math.max(1, thumb.implicitHeight) : 64))
                radius: 8; clip: true
                color: Qt.rgba(1, 1, 1, 0.5); border.color: tasks.cc.ink; border.width: 1.5
                Image {
                  id: thumb
                  anchors.fill: parent; anchors.margins: 2
                  source: "file://" + parent.modelData.file
                  sourceSize.height: 128
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                  onClicked: tasks.zoomPic = parent.modelData.file }
              }
            }
          }
          MouseArea {
            anchors.fill: parent; anchors.leftMargin: 28
            anchors.bottomMargin: subRow.picsShown ? 72 : 0
            anchors.rightMargin: subRow.pics.length ? picChip.width + 8 : 0
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
        font.pixelSize: Math.round(12 * tasks.fs)
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
      font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs) }
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
        height: modelData.kind === "group" ? 24 : modelData.kind === "super" ? 28 : 44
        SuperHead {
          visible: logRow.modelData.kind === "super"
          anchors.fill: parent
          name: logRow.modelData.kind === "super" ? logRow.modelData.name : ""
          collapsed: !!logRow.modelData.collapsed
          count: logRow.modelData.count || 0
          here: logRow.modelData.kind === "super" && tasks.logCursor === "s:" + logRow.modelData.name && tasks.logPane === "list"
          onToggle: { tasks.logPane = "list"; tasks.logCursor = "s:" + name; tasks.setSuperCollapsed(name, !collapsed, "log"); tasks.forceActiveFocus() }
          onMenu: (x, y) => { tasks.logPane = "list"; tasks.logCursor = "s:" + name; tasks.openSuperMenu(name, x, y) }
        }
        // group heading: click (or the keyboard) folds it
        Rectangle {
          visible: logRow.modelData.kind === "group"
          anchors.fill: parent
          radius: 9
          readonly property bool here: logRow.modelData.kind === "group" && tasks.logCursor === "g:" + logRow.modelData.name && tasks.logPane === "list"
          color: tasks.headColor(logRow.modelData.name, here, logHeadMouse.containsMouse)
          border.color: tasks.cc.ink
          border.width: here ? 2 : 0
          Row {
            x: 6 + (logRow.modelData.depth || 0) * 16; spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.verticalCenter: parent.verticalCenter; text: logRow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
            Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(logRow.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: !!logRow.modelData.name }
            CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: !logRow.modelData.name ? "NO GROUP" : logRow.modelData.name.toUpperCase() }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!logRow.modelData.collapsed
              text: logRow.modelData.count + (logRow.modelData.count === 1 ? " todo" : " todos")
              color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
          }
          MouseArea {
            id: logHeadMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: logRow.modelData.kind === "group"
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => {
              tasks.logPane = "list"; tasks.logCursor = "g:" + logRow.modelData.name; tasks.forceActiveFocus()
              if (mouse.button === Qt.RightButton) { var p = mapToItem(tasks, mouse.x, mouse.y); tasks.openGroupMenu(logRow.modelData.name, p.x, p.y) }
              else tasks.toggleLogGroup(logRow.modelData.name)
            }
          }
        }
        Rectangle {
        visible: logRow.modelData.kind === "todo"
        anchors.fill: parent
        anchors.leftMargin: (logRow.modelData.depth || 0) * 16
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
          Text { width: parent.width; elide: Text.ElideRight; text: parent.parent.modelData.title; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true }
          Text {
            width: parent.width; elide: Text.ElideRight
            text: (parent.parent.modelData.counts.doing ? " " + parent.parent.modelData.counts.doing + " in progress · " : "") + parent.parent.modelData.logCount + " log entries"
            color: tasks.cc.ink; opacity: 0.65; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
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
              id: laneList
              model: tasks.selected ? tasks.selected.subs.filter(function(s) { return s.state === parent.modelData[0] }) : []
              // stay on the picked sub-todo when the lane reloads
              function keepPicked() {
                for (var i = 0; i < count; i++) if (model[i] && model[i].i === tasks.logSub) { positionViewAtIndex(i, ListView.Contain); return }
              }
              onModelChanged: keepLane.restart()
              Timer { id: keepLane; interval: 40; onTriggered: laneList.keepPicked() }
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
                  font.pixelSize: Math.round(11 * tasks.fs) }
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
        text: "  LOG" + (tasks.logShown.length ? " — " + tasks.logShown.length + (tasks.logShown.length === 1 ? " ENTRY" : " ENTRIES") : "")
        font.underline: tasks.logPane === "entries"
      }
      CcButton {
        anchors.right: parent.right
        y: lanes.height + 44
        cc: tasks.cc
        icon: tasks.logModeIcons[tasks.logMode]
        text: tasks.logModeNames[tasks.logMode] + "  (s)"
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
                tasks.setSectionFolded(logItem.modelData.key, !logItem.modelData.collapsed)
                tasks.forceActiveFocus()
              }
            }
          }
          Row {
            id: headRow
            visible: logItem.modelData.kind === "head"
            x: 4 + (logItem.modelData.level || 0) * 14
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter
            readonly property string what: logItem.modelData.what || ""
            Text { anchors.verticalCenter: parent.verticalCenter; text: logItem.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
            StateBox { anchors.verticalCenter: parent.verticalCenter; visible: !!logItem.modelData.sub; state3: logItem.modelData.sub ? logItem.modelData.sub.state : "todo" }
            // super group / group / todo headings in the "all" views
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: headRow.what === "super" || headRow.what === "todo"
              text: headRow.what === "super" ? "\uf247" : "\uf0ae"
              color: headRow.what === "super" ? tasks.superColor(logItem.modelData.name) : tasks.cc.ink
              style: Text.Outline; styleColor: tasks.cc.ink
              font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs)
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: headRow.what === "group"
              width: 10; height: 10; radius: 5
              color: tasks.colorOf(logItem.modelData.group || "")
              border.color: tasks.cc.ink; border.width: 1
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: logList.width - 50 - headRow.x
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: logItem.modelData.kind !== "head" ? "" : logItem.modelData.label
                + (logItem.modelData.collapsed ? "   ·   " + logItem.modelData.count + (logItem.modelData.count === 1 ? " entry" : " entries") : "")
              color: tasks.cc.ink
              font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(13 * tasks.fs) }
          }
          Rectangle {
          id: entryBox
          visible: logItem.modelData.kind === "entry"
          readonly property var modelData: logItem.modelData.kind === "entry" ? logItem.modelData.e : ({ time: "", by: "", sub: "", text: "" })
          readonly property bool picked: tasks.logPane === "entries" && logList.currentIndex === logItem.index
          x: (logItem.modelData.level || 0) * 14
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
            font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: true
          }
          // what it's about: the todo, and the sub-todo if there is one
          Rectangle {
            x: 8; y: 21
            width: Math.min(parent.width - 16, aboutText.implicitWidth + 16)
            height: 18
            radius: 9
            color: Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.12)
            Rectangle { x: 0; width: 5; height: parent.height; radius: 2.5; color: tasks.colorOf(tasks.entryGroup(parent.parent.modelData)) }
            Text {
              id: aboutText
              x: 9; anchors.verticalCenter: parent.verticalCenter
              width: parent.width - 14
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: "\uf0ae  " + tasks.entryTag(parent.parent.modelData)
              color: tasks.cc.ink
              font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: true
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
            font.pixelSize: Math.round(12 * tasks.fs) }
          MouseArea {
            anchors.fill: parent
            onClicked: { tasks.logPane = "entries"; tasks.logEntry = tasks.logEntryRows.indexOf(logItem.index); tasks.forceActiveFocus() }
            onDoubleClicked: tasks.openEntry(logItem.modelData.e, false)
          }
          }
        }
        Text {
          visible: tasks.logShown.length === 0
          width: parent.width
          wrapMode: Text.Wrap
          text: "Nothing logged yet. Agents and scripts add entries with\n  slime-tasks log <id> \"…\"   and move sub-todos with   slime-tasks start/finish <id> <n>."
          color: tasks.cc.ink; opacity: 0.65
          font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs) }
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
        readonly property real indent: (modelData.kind === "super" ? 0 : modelData.kind === "group" ? 0 : modelData.kind === "todo" ? 18 : 44)
                                       + (modelData.depth || 0) * 16
        x: indent
        width: progressList.width - indent
        height: modelData.kind === "sub" ? 24 : 36
        radius: 12
        color: modelData.kind === "sub" ? "transparent"
          : modelData.kind === "group" && tasks.armedGroup !== "" && tasks.armedGroup === modelData.name ? Qt.rgba(1, 0.4, 0.4, 0.65)
          : modelData.kind === "super" ? tasks.superHeadColor(modelData.name, sel, false)
          : sel ? Qt.rgba(1, 1, 1, 0.72) : tasks.cc.wash
        border.color: tasks.cc.ink
        border.width: sel ? 2 : 0

        // super group
        Rectangle { visible: prow.modelData.kind === "super"; width: 7; height: parent.height; radius: 3.5; color: tasks.superColor(prow.modelData.name) }
        Row {
          visible: prow.modelData.kind === "super"
          x: 12; anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text { text: prow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
          Text { text: "\uf247"; color: tasks.superColor(prow.modelData.name); style: Text.Outline; styleColor: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(14 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
          Text { text: prow.modelData.kind === "super" ? prow.modelData.name : ""; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(16 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
          Text { text: prow.modelData.kind !== "super" ? "" : prow.modelData.count + (prow.modelData.count === 1 ? " todo" : " todos"); color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        }
        // group
        Row {
          visible: prow.modelData.kind === "group"
          x: 10; anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text { text: tasks.groupCollapsed(prow.modelData.name, "progress") ? "" : ""; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
          Rectangle { width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(prow.modelData.name); border.color: tasks.cc.ink; border.width: 1.2; visible: prow.modelData.name !== "" }
          Text { text: !prow.modelData.name ? "No group" : prow.modelData.name; color: tasks.cc.ink; font.family: tasks.cc.displayFont; font.weight: tasks.cc.displayWeight; font.pixelSize: Math.round(15 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
          Text { text: prow.modelData.kind !== "group" ? "" : prow.modelData.count + (prow.modelData.count === 1 ? " todo" : " todos"); color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
        }
        // todo
        Row {
          visible: prow.modelData.kind === "todo"
          x: 10; anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text { text: prow.modelData.kind === "todo" && prow.modelData.t.subs.length ? (tasks.expanded["t:" + prow.modelData.t.id] ? "" : "") : " "; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs); anchors.verticalCenter: parent.verticalCenter }
          Text {
            width: prow.width * 0.4
            elide: Text.ElideRight
            text: prow.modelData.kind === "todo" ? prow.modelData.t.title : ""
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true
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
            color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs)
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
          value: (prow.modelData.kind === "group" || prow.modelData.kind === "super") ? prow.modelData.pct : prow.modelData.kind === "todo" ? tasks.pct(prow.modelData.t) : 0
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
          text: Math.round(100 * ((prow.modelData.kind === "group" || prow.modelData.kind === "super") ? prow.modelData.pct : prow.modelData.kind === "todo" ? tasks.pct(prow.modelData.t) : 0)) + "%"
          color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true
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
          onEntered: if (tasks.archiveRows.length) {
            tasks.progressPane = "archive"
            var first = 0
            while (first < tasks.archiveRows.length - 1 && tasks.archiveRows[first].kind !== "todo") first++
            tasks.archiveIndex = first
          }
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
        model: tasks.archiveRows
        currentIndex: tasks.progressPane === "archive" ? tasks.archiveIndex : -1
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
          id: arow
          required property var modelData
          required property int index
          width: ListView.view.width
          height: modelData.kind === "head" ? 24 : modelData.kind === "shead" ? 28 : 28
          // a super group's heading: click folds it; restore all of it from here
          SuperHead {
            visible: arow.modelData.kind === "shead"
            anchors.fill: parent
            anchors.leftMargin: -6; anchors.rightMargin: -2
            name: arow.modelData.kind === "shead" ? arow.modelData.name : ""
            collapsed: !!arow.modelData.collapsed
            count: arow.modelData.count || 0
            here: arow.modelData.kind === "shead" && tasks.progressPane === "archive" && arow.index === tasks.archiveIndex
            onToggle: { tasks.progressPane = "archive"; tasks.archiveIndex = arow.index; tasks.setSuperCollapsed(name, !collapsed, "archive"); tasks.forceActiveFocus() }
            onMenu: (x, y) => { tasks.progressPane = "archive"; tasks.archiveIndex = arow.index; tasks.openSuperMenu(name, x, y) }
            CcButton {
              anchors.right: parent.right; anchors.rightMargin: 4
              anchors.verticalCenter: parent.verticalCenter
              cc: tasks.cc
              icon: "\uf0e2"; text: "restore all  (r)"; fontSize: 10
              onClicked: tasks.restoreSuper(arow.modelData.name)
            }
          }
          // a group's heading: click (or the keys) folds it
          Rectangle {
            visible: arow.modelData.kind === "head"
            anchors.fill: parent
            anchors.leftMargin: -6; anchors.rightMargin: -2
            radius: 9
            readonly property bool here: tasks.progressPane === "archive" && arow.index === tasks.archiveIndex
            color: tasks.headColor(arow.modelData.name, here, archHeadMouse.containsMouse)
            border.color: tasks.cc.ink
            border.width: here ? 2 : 0
            MouseArea {
              id: archHeadMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: arow.modelData.kind === "head"
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                tasks.progressPane = "archive"
                tasks.archiveIndex = arow.index
                tasks.setGroupCollapsed(arow.modelData.name, !arow.modelData.collapsed, "archive")
                tasks.forceActiveFocus()
              }
            }
          }
          CcButton {
            visible: arow.modelData.kind === "head"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            cc: tasks.cc
            icon: "\uf0e2"; text: "restore all  (r)"; fontSize: 10
            onClicked: tasks.restoreGroup(arow.modelData.name)
          }
          Row {
            visible: arow.modelData.kind === "head"
            x: (arow.modelData.depth || 0) * 14
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter
            Text { anchors.verticalCenter: parent.verticalCenter; text: arow.modelData.collapsed ? "\uf054" : "\uf078"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
            Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(arow.modelData.name); border.color: tasks.cc.ink; border.width: 1; visible: !!arow.modelData.name }
            CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: arow.modelData.kind !== "head" ? "" : arow.modelData.name ? arow.modelData.name.toUpperCase() : "NO GROUP" }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!arow.modelData.collapsed
              text: arow.modelData.count + (arow.modelData.count === 1 ? " todo" : " todos")
              color: tasks.cc.ink; opacity: 0.6; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs) }
          }
          Item {
            visible: arow.modelData.kind === "todo"
            anchors.fill: parent
            anchors.leftMargin: (arow.modelData.depth || 0) * 14
            readonly property var t: arow.modelData.kind === "todo" ? arow.modelData.t : ({ id: "", title: "", group: "", counts: { done: 0 }, subs: [] })
            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: -6; anchors.rightMargin: -2
              radius: 10
              visible: tasks.progressPane === "archive" && arow.index === tasks.archiveIndex
              color: Qt.rgba(1, 1, 1, 0.7)
              border.color: tasks.cc.ink; border.width: 2
            }
            Rectangle { x: 6; width: 6; height: 20; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(parent.t.group) }
            Text {
              x: 20; width: parent.width - restoreBtn.width - 30
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: parent.t.title + "  ·  " + parent.t.counts.done + "/" + parent.t.subs.length
              color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs) }
            MouseArea {
              anchors.fill: parent
              anchors.rightMargin: restoreBtn.width + 8
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: mouse => {
                tasks.progressPane = "archive"
                tasks.archiveIndex = arow.index
                tasks.forceActiveFocus()
                if (mouse.button === Qt.RightButton) {
                  var p = mapToItem(tasks, mouse.x, mouse.y)
                  tasks.openMenu(parent.t, p.x, p.y, true)
                }
              }
            }
            CcButton {
              id: restoreBtn
              cc: tasks.cc
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              icon: "\uf0e2"; text: "restore"; fontSize: 10
              onClicked: tasks.restoreArchived(parent.t)
            }
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
    property bool archived: false          // opened on an archived todo
    property string headGroup: ""          // opened on a group heading
    property string headSuper: ""          // opened on a super group heading
    property string armed: ""              // group waiting for the second d
    readonly property var groupNames: tasks.allGroupNames()
    // items: each group, "no group", then actions (on a heading: group actions)
    readonly property var items: headSuper !== ""
      ? [{ kind: "archiveSuper", name: headSuper }, { kind: "renameSuper", name: headSuper }, { kind: "deleteSuper", name: headSuper }]
      : headGroup !== ""
      ? [{ kind: "archiveGroup", name: headGroup }, { kind: "deleteGroup", name: headGroup }]
        .concat(Object.keys(tasks.supersMap).sort().map(function(sp) { return { kind: "intoSuper", name: sp } }))
        .concat(tasks.superOf(headGroup) ? [{ kind: "outOfSuper", name: tasks.superOf(headGroup) }] : [])
      : groupNames.map(function(g) { return { kind: "group", name: g } })
        .concat([{ kind: "group", name: "" }])
        .concat(archived ? [{ kind: "restore" }, { kind: "delete" }]
          : [{ kind: "rename" }, { kind: "archive" }]
            .concat(todo && todo.group ? [{ kind: "archiveGroup", name: todo.group }] : [])
            .concat([{ kind: "delete" }]))
    function deleteGroup(name) {
      if (!name) return
      if (armed !== name) { armed = name; return }      // d d, like deleting a todo
      armed = ""
      tasks.act(["group-delete", name])
      visible = false
      tasks.forceActiveFocus()
    }
    readonly property var arch: archived ? ["--archived"] : []
    visible: false
    z: 50
    width: 230
    height: menuCol.implicitHeight + 20
    radius: 14
    color: tasks.cc.paper
    border.color: tasks.cc.ink
    border.width: 2
    function run(it) {
      if (it.kind === "archiveGroup") { tasks.archiveGroup(it.name); visible = false; tasks.forceActiveFocus(); return }
      if (it.kind === "intoSuper") { tasks.act(["super-set", headGroup, it.name]); visible = false; tasks.forceActiveFocus(); return }
      if (it.kind === "outOfSuper") { tasks.act(["super-set", headGroup, ""]); visible = false; tasks.forceActiveFocus(); return }
      if (it.kind === "renameSuper") { visible = false; tasks.startRenameSuper(it.name); return }
      if (it.kind === "archiveSuper") { tasks.archiveSuper(it.name); visible = false; tasks.forceActiveFocus(); return }
      if (it.kind === "deleteSuper") {
        if (armed !== "s:" + it.name) { armed = "s:" + it.name; return }
        armed = ""
        tasks.act(["super-delete", it.name]); visible = false; tasks.forceActiveFocus(); return
      }
      if (it.kind === "deleteGroup") { deleteGroup(it.name); return }
      if (!todo) return
      if (it.kind === "group") tasks.act(["group", todo.id, it.name].concat(arch))
      else if (it.kind === "restore") tasks.restoreArchived(todo)
      else if (it.kind === "rename") { renameInput.text = todo.title; tasks.selectedId = todo.id; visible = false; renameInput.forceActiveFocus(); return }
      else if (it.kind === "archive") tasks.act(["archive", todo.id])
      else if (it.kind === "delete") tasks.act(["delete", todo.id].concat(arch))
      visible = false
      tasks.forceActiveFocus()
    }
    Keys.onPressed: event => {
      if (event.key === Qt.Key_Escape) { visible = false; tasks.forceActiveFocus() }
      else if (event.key === Qt.Key_Up || event.text === "k") index = Math.max(0, index - 1)
      else if (event.key === Qt.Key_Down || event.text === "j") index = Math.min(items.length - 1, index + 1)
      else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) run(items[index])
      // d d on a group (or on a heading's menu) deletes the group
      else if ((event.text === "d" || event.key === Qt.Key_Delete) && items[index] && (items[index].kind === "group" || items[index].kind === "deleteGroup") && items[index].name)
        deleteGroup(items[index].name)
      else if ((event.text === "d" || event.key === Qt.Key_Delete) && headSuper !== "") run({ kind: "deleteSuper", name: headSuper })
      else if ((event.text === "e" || event.key === Qt.Key_F2) && headSuper !== "") run({ kind: "renameSuper", name: headSuper })
      else if (event.text === "A" && headGroup !== "") { tasks.archiveGroup(headGroup); visible = false; tasks.forceActiveFocus() }
      else if (event.text === "n" && headSuper === "") groupInput.forceActiveFocus()
      else return
      event.accepted = true
    }
    Column {
      id: menuCol
      x: 10; y: 10
      width: parent.width - 20
      spacing: 3
      CcHeading { cc: tasks.cc; text: menu.headSuper !== "" ? "SUPER GROUP · " + menu.headSuper.toUpperCase()
        : menu.headGroup !== "" ? "GROUP · " + menu.headGroup.toUpperCase() : "GROUP" }
      Repeater {
        model: menu.items
        Rectangle {
          required property var modelData
          required property int index
          width: menuCol.width
          height: 24
          radius: 8
          readonly property bool armedHere: menu.armed !== "" && ((modelData.kind === "group" || modelData.kind === "deleteGroup") && modelData.name === menu.armed
                                                            || modelData.kind === "deleteSuper" && "s:" + modelData.name === menu.armed)
          color: armedHere ? Qt.rgba(1, 0.4, 0.4, 0.6) : index === menu.index ? Qt.rgba(tasks.cc.ink.r, tasks.cc.ink.g, tasks.cc.ink.b, 0.15) : "transparent"
          Row {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle { visible: parent.parent.modelData.kind === "group" && parent.parent.modelData.name !== ""; width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: tasks.colorOf(parent.parent.modelData.name) }
            Text {
              text: {
                var it = parent.parent.modelData
                if (parent.parent.armedHere) return "\uf1f8  d again: delete " + (it.kind === "deleteSuper" ? "super group " : "group ") + it.name
                if (it.kind === "intoSuper") return "\uf247  into super group " + it.name + (tasks.superOf(menu.headGroup) === it.name ? "  \uf00c" : "")
                if (it.kind === "outOfSuper") return "\uf057  out of super group " + it.name
                if (it.kind === "renameSuper") return "\uf044  rename super group  (e)"
                if (it.kind === "archiveSuper") return "\uf187  archive it all  (A)"
                if (it.kind === "deleteSuper") return "\uf1f8  delete super group  (d d)"
                if (it.kind === "archiveGroup") return "\uf187  archive the whole group"
                if (it.kind === "deleteGroup") return "\uf1f8  delete group  (d d)"
                if (it.kind === "group") return (it.name === "" ? "no group" : it.name) + (menu.todo && menu.todo.group === it.name ? "  " : "")
                return it.kind === "rename" ? "  rename" : it.kind === "archive" ? "  archive"
                  : it.kind === "restore" ? "  restore" : "  delete"
              }
              color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(12 * tasks.fs) }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: menu.run(parent.modelData) }
        }
      }
      Text {
        visible: menu.headGroup === "" && !menu.archived
        width: menuCol.width
        wrapMode: Text.Wrap
        text: menu.headSuper !== "" ? "deleting a super group keeps its groups" : "d d on a group deletes it (its todos just lose the group)"
        color: tasks.cc.ink; opacity: 0.55
        font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
      Field {
        visible: menu.headSuper === ""
        width: menuCol.width
        placeholder: menu.headGroup !== "" ? "new super group for it…  (n)" : "new group…  (n)"
        onAccepted: t => {
          if (menu.headGroup !== "") tasks.act(["super-set", menu.headGroup, t])
          else if (menu.todo) tasks.act(["group", menu.todo.id, t].concat(menu.arch))
          menu.visible = false; tasks.forceActiveFocus()
        }
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

  // ============================================================ log entry viewer
  // One entry over the whole panel, for reading (and copying / editing).
  FontLoader { id: fellFont; source: Qt.resolvedUrl("../fonts/IMFellEnglish-Regular.ttf") }
  QtObject {
    id: parchLook                    // CcButton colours, in ink and parchment
    readonly property var bar: tasks.bar
    readonly property color ink: viewer.ink
    readonly property color slime: viewer.sheet
    readonly property color paper: viewer.sheet
    readonly property string font: tasks.cc.font
    readonly property string displayFont: viewer.font
    readonly property int displayWeight: Font.Normal
    readonly property real fontScale: tasks.fs
    readonly property color wash: Qt.rgba(1, 0.95, 0.85, 0.5)
  }
  Rectangle {
    id: viewer
    visible: tasks.viewEntry !== null
    z: 58
    anchors.fill: parent
    color: "transparent"
    MouseArea { anchors.fill: parent }       // nothing underneath takes clicks

    // ---- a worn sheet of parchment: torn, scorched edges, stains, faded rules
    readonly property color ink: "#3a2412"
    readonly property color sheet: "#efdcb0"
    readonly property color sheetEdge: "#caa468"
    readonly property color scorch: "#6b3f17"
    readonly property string font: fellFont.status === FontLoader.Ready ? fellFont.name : tasks.cc.font
    function rnd(i) { var x = Math.sin(i * 78.233 + 12.9898) * 43758.5453; return x - Math.floor(x) }
    // the outline, nibbled all the way round
    function torn(w, h, m) {
      var p = [], i = 0, st = 14
      for (var x = m; x < w - m; x += st) p.push([x, m + rnd(i++) * 7])
      for (var y = m; y < h - m; y += st) p.push([w - m - rnd(i++) * 7, y])
      for (x = w - m; x > m; x -= st) p.push([x, h - m - rnd(i++) * 8])
      for (y = h - m; y > m; y -= st) p.push([m + rnd(i++) * 7, y])
      return "M " + p.map(function(q) { return q[0].toFixed(1) + " " + q[1].toFixed(1) }).join(" L ") + " Z"
    }
    Shape {
      id: sheetShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      readonly property string outline: viewer.torn(width, height, 6)
      ShapePath {                               // the sheet, lighter in the middle
        strokeColor: viewer.scorch
        strokeWidth: 2
        joinStyle: ShapePath.RoundJoin
        fillGradient: RadialGradient {
          centerX: sheetShape.width * 0.5; centerY: sheetShape.height * 0.45
          centerRadius: Math.max(sheetShape.width, sheetShape.height) * 0.62
          focalX: centerX; focalY: centerY
          GradientStop { position: 0.0; color: viewer.sheet }
          GradientStop { position: 0.72; color: Qt.darker(viewer.sheet, 1.05) }
          GradientStop { position: 1.0; color: viewer.sheetEdge }
        }
        PathSvg { path: sheetShape.outline }
      }
      ShapePath {                               // scorched rim
        fillColor: "transparent"
        strokeColor: Qt.rgba(0.42, 0.24, 0.09, 0.28)
        strokeWidth: 12
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: sheetShape.outline }
      }
    }
    // stains and a water ring
    Repeater {
      model: [[0.82, 0.18, 120], [0.14, 0.72, 160], [0.58, 0.86, 90], [0.33, 0.28, 70]]
      Shape {
        required property var modelData
        readonly property real r: modelData[2]
        x: modelData[0] * viewer.width - r; y: modelData[1] * viewer.height - r
        width: r * 2; height: r * 2
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: "transparent"
          fillGradient: RadialGradient {
            centerX: r; centerY: r; centerRadius: r; focalX: r; focalY: r
            GradientStop { position: 0.0; color: Qt.rgba(0.55, 0.36, 0.14, 0.10) }
            GradientStop { position: 0.8; color: Qt.rgba(0.55, 0.36, 0.14, 0.06) }
            GradientStop { position: 1.0; color: Qt.rgba(0.55, 0.36, 0.14, 0.0) }
          }
          PathSvg { path: "M 0 " + r + " A " + r + " " + r + " 0 1 1 " + (2 * r) + " " + r + " A " + r + " " + r + " 0 1 1 0 " + r + " Z" }
        }
      }
    }
    Rectangle {                                 // a mug's ring
      x: viewer.width * 0.86 - 36; y: viewer.height * 0.62 - 36
      width: 72; height: 72; radius: 36
      color: "transparent"
      border.color: Qt.rgba(0.45, 0.28, 0.1, 0.16); border.width: 4
    }
    Repeater {                                  // faded rules
      model: Math.max(0, Math.floor((viewer.height - 140) / 30))
      Rectangle {
        required property int index
        x: 30; y: 128 + index * 30
        width: viewer.width - 60; height: 1
        color: viewer.ink; opacity: 0.07
      }
    }
    Rectangle {                                 // an old fold down the middle
      x: viewer.width / 2; y: 14; width: 2; height: viewer.height - 28
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.5; color: Qt.rgba(0.4, 0.25, 0.1, 0.12) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }
    Shape {                                     // a dog-eared corner
      x: viewer.width - 52; y: viewer.height - 52
      width: 46; height: 46
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: viewer.sheetEdge
        strokeColor: viewer.scorch; strokeWidth: 1.4
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M 46 6 L 6 46 L 40 40 Z" }
      }
    }
    readonly property var e: tasks.viewEntry || ({ time: "", by: "", sub: "", text: "" })

    // header: when, who, what it's about, and the buttons
    Column {
      id: viewHead
      x: 34; y: 28
      width: parent.width - 68
      spacing: 6
      Row {
        width: parent.width
        spacing: 8
        Text {
          width: parent.width - viewButtons.width - 8
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: viewer.e.time + (viewer.e.by ? "  ·  " + viewer.e.by : "")
          color: viewer.ink; opacity: 0.7
          font.family: viewer.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true
        }
        Row {
          id: viewButtons
          spacing: 6
          anchors.verticalCenter: parent.verticalCenter
          CcButton { cc: parchLook; icon: "\uf0c5"; text: tasks.copiedNote !== "" ? "copied!" : "copy  (c)"; fontSize: 11; on: tasks.copiedNote !== ""; onClicked: tasks.copyEntry(tasks.viewEntry) }
          CcButton { cc: parchLook; visible: !tasks.viewEditing; icon: "\uf044"; text: "edit  (e)"; fontSize: 11; onClicked: tasks.startEdit() }
          CcButton { cc: parchLook; visible: !tasks.viewEditing && !!viewer.e.isSub; icon: "\uf03e"; text: "add picture  (p)"; fontSize: 11; onClicked: tasks.openPicker(tasks.selected, viewer.e.n) }
          CcButton { cc: parchLook; visible: tasks.viewEditing; icon: "\uf00c"; text: "save  (Ctrl+S)"; fontSize: 11; on: true; onClicked: tasks.saveEdit() }
          CcButton { cc: parchLook; visible: tasks.viewEditing; icon: "\uf00d"; text: "cancel  (Esc)"; fontSize: 11; onClicked: { tasks.viewEditing = false; tasks.forceActiveFocus() } }
          CcButton { cc: parchLook; visible: !tasks.viewEditing; icon: "\uf00d"; text: "close  (Esc)"; fontSize: 11; onClicked: tasks.closeEntry() }
        }
      }
      Rectangle {
        width: Math.min(parent.width, viewAbout.implicitWidth + 20)
        height: 24
        radius: 12
        color: Qt.rgba(0.45, 0.28, 0.1, 0.14)
        Rectangle { width: 6; height: parent.height; radius: 3; color: tasks.colorOf(tasks.entryGroup(viewer.e)) }
        Text {
          id: viewAbout
          x: 12; anchors.verticalCenter: parent.verticalCenter
          width: parent.width - 18
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: "\uf0ae  " + (viewer.e.isSub ? (tasks.selected ? tasks.selected.title : "") + "   \u21b3  " + viewer.e.where : tasks.entryTag(viewer.e))
          color: viewer.ink
          font.family: viewer.font; font.pixelSize: Math.round(12 * tasks.fs); font.bold: true
        }
      }
    }

    // reading
    Flickable {
      id: viewFlick
      visible: !tasks.viewEditing
      x: 34; y: viewHead.y + viewHead.height + 16
      width: parent.width - 68
      height: parent.height - y - 34
      clip: true
      contentHeight: viewCol.implicitHeight
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: viewCol
        width: viewFlick.width
        spacing: 18
      Text {
        id: viewText
        width: viewFlick.width
        text: viewer.e.text
        wrapMode: Text.Wrap
        textFormat: Text.MarkdownText
        color: viewer.ink
        font.family: viewer.font
        font.pixelSize: Math.round(19 * tasks.fs)
        lineHeight: 1.2
      }
      // a sub-todo's pictures: pinned to the sheet
      Text {
        visible: !!viewer.e.isSub
        width: parent.width
        wrapMode: Text.Wrap
        text: tasks.viewPics.length
          ? "PICTURES  ·  ← → pick · Enter show big · d d remove · p add (or drop files here)"
          : "No pictures yet: p (or the button) picks one, or drop image files onto the sheet."
        color: viewer.ink; opacity: 0.6
        font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); font.bold: true
      }
      Flow {
        visible: tasks.viewPics.length > 0
        width: parent.width
        spacing: 14
        Repeater {
          model: tasks.viewPics
          Item {
            id: pin
            required property var modelData
            required property int index
            readonly property bool picked: tasks.picIndex === index
            readonly property bool armed: tasks.armedPic === index
            width: Math.min(viewCol.width, 220)
            height: frame.height + 22
            rotation: (index % 3 - 1) * 1.6
            Rectangle {
              id: frame
              width: parent.width
              height: Math.max(80, Math.min(200, big.implicitHeight > 0 ? (width - 12) * big.implicitHeight / Math.max(1, big.implicitWidth) + 12 : 150))
              color: Qt.rgba(1, 0.98, 0.92, 0.9)
              border.color: pin.armed ? "#b03020" : viewer.ink
              border.width: pin.picked ? 3 : 1.4
              Image {
                id: big
                anchors.fill: parent; anchors.margins: 6
                source: "file://" + pin.modelData.file
                sourceSize.width: 440
                fillMode: Image.PreserveAspectFit
                asynchronous: true
              }
              // a pin through the top
              Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: -5; width: 12; height: 12; radius: 6; color: "#b03020"; border.color: viewer.ink; border.width: 1.2 }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { tasks.picIndex = pin.index; tasks.zoomPic = pin.modelData.file } }
              // remove (d d, or this)
              Rectangle {
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: -7
                width: 22; height: 22; radius: 11
                visible: pin.picked || pinHover.hovered
                color: pin.armed ? "#b03020" : Qt.rgba(1, 0.97, 0.88, 0.95)
                border.color: viewer.ink; border.width: 1.4
                Text { anchors.centerIn: parent; text: "\uf00d"; color: pin.armed ? "white" : viewer.ink; font.family: tasks.cc.font; font.pixelSize: 11 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                  onClicked: { tasks.picIndex = pin.index; if (tasks.armedPic !== pin.index) { tasks.armedPic = pin.index; disarmPic.restart() } else tasks.removePicture(viewer.e.n, pin.index) } }
              }
            }
            HoverHandler { id: pinHover }
            Text {
              y: frame.height + 4
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideMiddle
              text: pin.armed ? "d again: remove it" : pin.modelData.name
              color: pin.armed ? "#b03020" : viewer.ink
              font.family: viewer.font; font.pixelSize: Math.round(13 * tasks.fs)
            }
          }
        }
      }
      }
    }
    // drop image files onto the sheet (a sub-todo's) to pin them to it
    DropArea {
      anchors.fill: parent
      enabled: !!viewer.e.isSub && !tasks.viewEditing
      keys: ["text/uri-list"]
      onDropped: drop => {
        if (!drop.hasUrls) return
        for (var i = 0; i < drop.urls.length; i++) tasks.addPicture(tasks.selected, viewer.e.n, decodeURIComponent(String(drop.urls[i]).replace(/^file:\/\//, "")))
        drop.acceptProposedAction()
      }
      Rectangle {
        anchors.fill: parent; anchors.margins: 18
        visible: parent.containsDrag
        radius: 16
        color: Qt.rgba(1, 1, 1, 0.25)
        border.color: viewer.ink; border.width: 3
        Text { anchors.centerIn: parent; text: "\uf03e  drop to pin it to this sub-todo"; color: viewer.ink; font.family: viewer.font; font.pixelSize: 24 }
      }
    }

    // editing: the entry's raw markdown
    Rectangle {
      visible: tasks.viewEditing
      x: 28; y: viewHead.y + viewHead.height + 10
      width: parent.width - 56
      height: parent.height - y - 30
      radius: 8
      color: Qt.rgba(1, 0.97, 0.88, 0.8)
      border.color: viewer.ink
      border.width: 1.6
      Flickable {
        id: editFlick
        anchors.fill: parent
        anchors.margins: 10
        clip: true
        contentHeight: viewEditor.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        TextEdit {
          id: viewEditor
          width: editFlick.width
          wrapMode: TextEdit.Wrap
          textFormat: TextEdit.PlainText
          selectByMouse: true
          color: viewer.ink
          font.family: "monospace"
          font.pixelSize: Math.round(14 * tasks.fs)
          onCursorRectangleChanged: {
            if (cursorRectangle.y < editFlick.contentY) editFlick.contentY = cursorRectangle.y
            else if (cursorRectangle.y + cursorRectangle.height > editFlick.contentY + editFlick.height)
              editFlick.contentY = cursorRectangle.y + cursorRectangle.height - editFlick.height
          }
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { tasks.viewEditing = false; tasks.forceActiveFocus(); event.accepted = true }
            else if ((event.key === Qt.Key_S || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
              tasks.saveEdit(); event.accepted = true
            }
          }
        }
      }
    }
  }

  // ============================================================ rename a group
  Rectangle {
    visible: tasks.renamingGroup !== ""
    z: 57
    anchors.centerIn: parent
    width: 340
    height: 92
    radius: 16
    color: tasks.cc.paper
    border.color: tasks.cc.ink
    border.width: 2
    CcHeading { x: 16; y: 14; cc: tasks.cc; text: (tasks.renamingIsSuper ? "RENAME SUPER GROUP · " : "RENAME GROUP · ") + tasks.renamingGroup.toUpperCase() }
    Rectangle {
      x: 14; y: 40
      width: parent.width - 28
      height: 32
      radius: 16
      color: Qt.rgba(1, 1, 1, 0.75)
      border.color: tasks.cc.ink
      border.width: 2
      TextInput {
        id: renameGroupInput
        x: 12
        width: parent.width - 24
        anchors.verticalCenter: parent.verticalCenter
        color: tasks.cc.ink
        font.family: tasks.cc.font
        font.pixelSize: Math.round(13 * tasks.fs)
        clip: true
        Keys.onReturnPressed: tasks.finishRenameGroup(text.trim())
        Keys.onEscapePressed: { tasks.renamingGroup = ""; tasks.renamingIsSuper = false; tasks.forceActiveFocus() }
      }
    }
  }

  // ================================================================ keys help
  // one section at a time (the tab you're on first); ← → or the chips switch
  property int helpSection: 0
  readonly property var helpSections: [
    ["", [["Tab / 1 2 3", "switch tabs"], ["?", "this help"], ["Esc", "back out, or close the command centre"]]],
    ["TODO · LIST", [["↑ ↓  j k", "pick a todo"], ["→  Enter", "open its sub-todos"], ["n", "new todo"], ["a", "add a sub-todo"],
                     ["Space", "mark finished"], ["e  F2", "rename"], ["g", "group menu"], ["A", "archive"], ["d d", "delete"], ["f", "show / hide finished"],
                     ["J K  Shift ↑↓", "move a todo"], ["drag", "move (into another group, too)"],
                     ["←  z  (or click a heading)", "fold its group"], ["g  /  right-click on a heading", "group menu: archive or delete the group"],
                     ["A  on a heading", "archive the whole group"], ["e  /  d d  on a heading (any tab)", "rename / delete the group"], ["d d  on a group in the g menu", "delete that group"], ["Enter  Space  →  on a heading", "fold / unfold"],
                     ["g  on a group: into / new super group", "super groups hold groups; their headings take the same keys"], ["A  on a super group", "archive every todo in it"]]],
    ["TODO · SUB-TODOS", [["↑ ↓", "pick"], ["Space", "to do → in progress → done"], ["Enter", "open it over the panel (c copy · e edit)"], ["p", "add a picture (a drip panel of your files)"], ["i", "fold its pictures"], ["a", "add"], ["e", "edit"],
                          ["d", "delete"], ["J K  Shift ↑↓  drag", "move down / up"], ["←  Esc", "back to the list"]]],
    ["EVERYWHERE", [["Shift ↑↓", "move the highlighted todo, sub-todo, group or log section"]]],
    ["TASK LOG", [["L  (here or on the Todo tab)", "jump to the selected todo's log"], ["L  on a super group, group, todo or sub-todo (here or on the Todo tab)", "jump to its section of the log"], ["↑ ↓", "pick a todo"], ["→ … ↓", "into the lanes, then on down into the log"], ["s  S", "log view: newest first · by sub-todo · all by todo · by group · by super group"], ["Enter on an entry", "open it over the panel"], ["c  /  e", "copy / edit the entry"], ["←  z  /  Enter  →  on a section", "fold / unfold it (by sub-todo)"], ["←  z  /  →  Enter on a heading", "fold / unfold its group"], ["→  Enter", "into its lanes"], ["→  Space  /  ←", "move a sub-todo a lane on / back"], ["Tab  Shift+Tab  in the lanes", "hop to the next / previous lane"], ["Enter on a sub-todo", "open it over the panel"],
                  ["w", "write in the log (about the picked sub-todo)"], ["PgUp PgDn", "scroll the log"], ["click / right-click", "a lane on / back"]]],
    ["PROGRESS", [["↑ ↓", "pick"], ["Enter  Space", "expand / collapse"], ["→  ←", "open / close a todo, then fold its group"], ["z", "fold the group"], ["A", "archive"], ["↓ past the end", "into the archive"],
                  ["/", "search the archive (Enter: into the results)"], ["Enter  r", "restore an archived list (you stay in the archive)"], ["r  on an archive heading", "restore the whole group / super group"], ["g  /  right-click", "group, restore or delete an archived list"], ["←  z  /  Enter  →  on a heading", "fold / unfold an archive group"], ["↑ at the top  Esc", "back up"]]]
        ]
  onShowHelpChanged: if (showHelp) helpSection = tab === "log" ? 3 : tab === "progress" ? 4 : 1
  Rectangle {
    id: helpCard
    visible: tasks.showHelp
    z: 60
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 700)
    height: Math.min(parent.height - 40, helpHead.height + helpFlick.contentHeight + helpFoot.implicitHeight + 44)
    radius: 16
    color: tasks.cc.paper
    border.color: tasks.cc.ink
    border.width: 2
    MouseArea { anchors.fill: parent; onClicked: tasks.showHelp = false }
    Flow {
      id: helpHead
      x: 14; y: 12
      width: parent.width - 28
      spacing: 6
      Repeater {
        model: ["General", "Todo", "Sub-todos", "Task Log", "Progress", "Moving"]
        CcButton {
          required property string modelData
          required property int index
          cc: tasks.cc
          fontSize: 11
          text: modelData
          on: tasks.helpSection === helpIndex
          // sections: 0 general, 1 todo, 2 sub-todos, 3 everywhere, 4 log, 5 progress
          readonly property int helpIndex: [0, 1, 2, 4, 5, 3][index]
          onClicked: tasks.helpSection = helpIndex
        }
      }
    }
    Flickable {
      id: helpFlick
      x: 14; y: helpHead.y + helpHead.height + 10
      width: parent.width - 28
      height: Math.max(0, parent.height - y - helpFoot.implicitHeight - 20)
      contentHeight: helpGrid.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      // key | what it does, in two columns of pairs
      Grid {
        id: helpGrid
        width: helpFlick.width
        columns: width > 520 ? 2 : 1
        columnSpacing: 18
        rowSpacing: 5
        Repeater {
          model: (tasks.helpSections[tasks.helpSection] || ["", []])[1]
          Row {
            required property var modelData
            width: (helpGrid.width - (helpGrid.columns - 1) * helpGrid.columnSpacing) / helpGrid.columns
            spacing: 8
            Text {
              width: Math.min(130, parent.width * 0.42)
              wrapMode: Text.Wrap
              text: parent.modelData[0]
              color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs); font.bold: true
            }
            Text {
              width: parent.width - Math.min(130, parent.width * 0.42) - 8
              wrapMode: Text.Wrap
              text: parent.modelData[1]
              color: tasks.cc.ink; opacity: 0.78; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs)
            }
          }
        }
      }
    }
    Text {
      id: helpFoot
      x: 14
      anchors.bottom: parent.bottom; anchors.bottomMargin: 10
      width: parent.width - 28
      wrapMode: Text.Wrap
      text: "← → sections · Esc or ? closes · text boxes: Enter saves, Esc leaves · todos are plain markdown in " + tasks.folder.replace(/^\/home\/[^/]+/, "~")
      color: tasks.cc.ink; opacity: 0.6
      font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs)
    }
  }

  // ================================================== a picture, shown big
  Rectangle {
    id: zoom
    z: 62
    anchors.fill: parent
    visible: tasks.zoomPic !== ""
    color: Qt.rgba(0, 0, 0, 0.72)
    radius: 18
    Image {
      anchors.fill: parent; anchors.margins: 28
      source: tasks.zoomPic !== "" ? "file://" + tasks.zoomPic : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
      text: "Esc / Enter / click to close"
      color: "white"; opacity: 0.7; font.family: tasks.cc.font; font.pixelSize: 11
    }
    MouseArea { anchors.fill: parent; onClicked: { tasks.zoomPic = ""; tasks.forceActiveFocus() } }
    // Esc works here even from the sub-todo list (the tab's keys see the viewer's zoom only)
    focus: visible
    Keys.onPressed: event => { tasks.zoomPic = ""; tasks.forceActiveFocus(); event.accepted = true }
    onVisibleChanged: if (visible && !tasks.viewEntry) forceActiveFocus()
  }

  // ================================================== pick a picture (drip panel)
  FocusScope {
    id: picker
    z: 61
    anchors.fill: parent
    visible: false
    readonly property string home: Quickshell.env("HOME")
    property string dir: ""
    function open() {
      var last = tasks.bar && tasks.bar.ccSections ? tasks.bar.ccSections["tasks-pic-dir"] : ""
      dir = last || (home + "/Pictures")
      visible = true
      grid.currentIndex = 0
      grid.forceActiveFocus()
    }
    function close() {
      visible = false
      if (tasks.viewEntry) tasks.forceActiveFocus(); else tasks.forceActiveFocus()
    }
    function go(path) {
      dir = path
      grid.currentIndex = 0
      if (tasks.bar) { var m = Object.assign({}, tasks.bar.ccSections); m["tasks-pic-dir"] = path; tasks.bar.ccSections = m }
    }
    function up() { if (dir !== "/") go(dir.replace(/\/[^\/]+\/?$/, "") || "/") }
    function choose(i) {
      if (i < 0 || i >= files.count) return
      var path = files.get(i, "filePath")
      if (files.get(i, "fileIsDir")) { go(path); return }
      var t = null
      for (var k = 0; k < tasks.todos.length; k++) if (tasks.todos[k].id === tasks.pickFor.id) t = tasks.todos[k]
      tasks.addPicture(t, tasks.pickFor.n, path)
      close()
    }
    FolderListModel {
      id: files
      folder: picker.dir !== "" ? "file://" + picker.dir : ""
      nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp", "*.svg", "*.PNG", "*.JPG", "*.JPEG"]
      showDirs: true
      showDirsFirst: true
      showDotAndDotDot: false
      showHidden: false
      sortField: FolderListModel.Name
    }
    // dim the tab; a click outside closes it
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35); radius: 18
      MouseArea { anchors.fill: parent; onClicked: picker.close() } }

    // the panel: a blob of slime with drips hanging off it
    Item {
      id: ooze
      anchors.centerIn: parent
      width: Math.min(parent.width - 40, 640)
      height: Math.min(parent.height - 80, 460)
      readonly property real t: tasks.bar ? tasks.bar.animTime : 0
      // the bar's own slime (its shader, as a free-standing blob): same
      // material, colour, shading and drips as the bar
      ShaderEffect {
        x: -20; y: -10
        width: ooze.width + 40
        height: ooze.height + 110
        readonly property var bar: tasks.bar
        visible: !!bar && picker.visible
        fragmentShader: Qt.resolvedUrl("../shaders/slime.frag.qsb")
        // every shader uniform set explicitly: unset ones are not guaranteed to be 0
        property vector4d cullRect: Qt.vector4d(0, 0, 0, 0)
        property real clipTop: -100000
        property real poolDepth: 0
        property vector2d origin: Qt.vector2d(0, 0)
        property vector4d bulb0: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb1: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb2: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb3: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb4: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb5: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb6: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb7: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb8: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb9: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb10: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb11: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb12: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb13: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb14: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb15: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb16: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb17: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb18: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb19: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb20: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb21: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb22: Qt.vector4d(0, 0, 0, 0)
        property vector4d bulb23: Qt.vector4d(0, 0, 0, 0)
        property real blobMode: 1
        property real orient: 0
        property vector2d screenSize: Qt.vector2d(0, 0)
        property real barShape: 0
        property real material: bar ? bar.materialId : 0
        property vector4d dripStyle: bar ? bar.dripStyleVec : Qt.vector4d(1, 1, 0, 1)
        property vector4d dripExtra: bar ? bar.dripExtraVec : Qt.vector4d(0, 0, 0, 0)
        property vector4d cava0: bar ? bar.cava0 : Qt.vector4d(0, 0, 0, 0)
        property vector4d cava1: bar ? bar.cava1 : Qt.vector4d(0, 0, 0, 0)
        property vector4d cava2: bar ? bar.cava2 : Qt.vector4d(0, 0, 0, 0)
        property vector4d cava3: bar ? bar.cava3 : Qt.vector4d(0, 0, 0, 0)
        property vector4d cavaOpts: bar ? bar.cavaOpts : Qt.vector4d(0, 0, 0, 0)
        property vector4d dockBracket: Qt.vector4d(0, 0, 0, 0)
        property vector4d dropShape: Qt.vector4d(0, 0, 0, 0)
        property vector4d eggDrip: Qt.vector4d(0, 0, 0, 0)
        property vector4d group0: Qt.vector4d(0, 0, 0, 0)
        property vector4d group1: Qt.vector4d(0, 0, 0, 0)
        property vector4d group2: Qt.vector4d(0, 0, 0, 0)
        property real time: bar ? bar.animTime : 0
        property real barHeight: 10
        property real openProgress: 1
        property real dripAmount: bar ? bar.dripLevel : 1
        property real shadingStyle: bar ? bar.shadingStyle : 3
        property vector2d resolution: Qt.vector2d(width, height)
        property vector4d panelRect: Qt.vector4d(20, 10, ooze.width, ooze.height - 4)
        property color slimeColor: bar ? bar.slimeColor : "black"
        property color slimeColor2: bar ? bar.slimeColor2 : "black"
        property color paperColor: bar ? bar.paperColor : "white"
      }
      // the blob takes clicks (nothing underneath does)
      MouseArea { anchors.fill: parent }
      Column {
        x: 18; y: 18
        width: ooze.width - 36
        spacing: 8
        Row {
          width: parent.width
          spacing: 8
          CcHeading { cc: tasks.cc; anchors.verticalCenter: parent.verticalCenter; text: "PICK A PICTURE" }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 120 - upBtn.width - homeBtn.width - 24; height: 24; radius: 12
            color: tasks.cc.wash; border.color: tasks.cc.ink; border.width: 1
            Text {
              x: 10; width: parent.width - 20; anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideLeft
              text: picker.dir.replace(picker.home, "~")
              color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(11 * tasks.fs)
            }
          }
          CcButton { id: upBtn; cc: tasks.cc; icon: "\uf062"; text: "up  (⌫)"; fontSize: 10; onClicked: { picker.up(); grid.forceActiveFocus() } }
          CcButton { id: homeBtn; cc: tasks.cc; icon: "\uf015"; text: "~"; fontSize: 10; onClicked: { picker.go(picker.home); grid.forceActiveFocus() } }
        }
        GridView {
          id: grid
          width: parent.width
          height: ooze.height - 36 - 32 - 30
          clip: true
          cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 116)))
          cellHeight: 112
          model: files
          boundsBehavior: Flickable.StopAtBounds
          keyNavigationEnabled: true
          highlightFollowsCurrentItem: false
          delegate: Item {
            id: cell
            required property int index
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            readonly property bool here: GridView.isCurrentItem
            width: grid.cellWidth; height: grid.cellHeight
            Rectangle {
              anchors.fill: parent; anchors.margins: 4
              radius: 12
              color: cell.here ? Qt.rgba(1, 1, 1, 0.75) : cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.22)
              border.color: tasks.cc.ink; border.width: cell.here ? 2.5 : 1
              Text {
                visible: cell.fileIsDir
                anchors.horizontalCenter: parent.horizontalCenter; y: 12
                text: "\uf07b"; color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: 44
              }
              Image {
                visible: !cell.fileIsDir
                x: 6; y: 6; width: parent.width - 12; height: 70
                source: cell.fileIsDir ? "" : "file://" + cell.filePath
                sourceSize.height: 140
                fillMode: Image.PreserveAspectFit
                asynchronous: true
              }
              Text {
                x: 6; y: 80; width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: cell.fileName
                color: tasks.cc.ink; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs); font.bold: cell.fileIsDir
              }
            }
            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { grid.currentIndex = cell.index; picker.choose(cell.index) }
            }
          }
          onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)
          Keys.onPressed: event => {
            var k = event.key, txt = event.text
            if (k === Qt.Key_Escape || txt === "q") picker.close()
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) picker.choose(currentIndex)
            else if (k === Qt.Key_Backspace || txt === "-") picker.up()
            else if (txt === "~") picker.go(picker.home)
            else if (txt === "h") moveCurrentIndexLeft()
            else if (txt === "l") moveCurrentIndexRight()
            else if (txt === "k") moveCurrentIndexUp()
            else if (txt === "j") moveCurrentIndexDown()
            else return
            event.accepted = true
          }
          Text {
            visible: files.count === 0 && files.status === FolderListModel.Ready
            anchors.centerIn: parent
            text: "No pictures or folders here  (⌫ goes up)"
            color: tasks.cc.ink; opacity: 0.7; font.family: tasks.cc.font; font.pixelSize: 12
          }
        }
        Text {
          text: "arrows / hjkl pick · Enter opens a folder or adds the picture · ⌫ up · ~ home · Esc closes"
          color: tasks.cc.ink; opacity: 0.65; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs)
        }
      }
    }
  }
}
