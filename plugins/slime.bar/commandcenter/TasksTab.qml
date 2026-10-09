import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../ui"
import "tasks"

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
  // handed to the parts in tasks/ (`tasks: tasks` there would name their own property)
  readonly property var tasksTab: tasks
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
  // log entries are shown as Markdown, but nothing in them may reach out:
  // pictures become plain links (Qt would fetch a remote one) and raw HTML
  // shows as text; code is left exactly as written
  function safeMarkdown(t) {
    return String(t || "").split(/(```[\s\S]*?(?:```|$)|`[^`\n]*`)/).map(function(part, i) {
      if (i % 2) return part
      return part.replace(/</g, "&lt;").replace(/!\[([^\]]*)\]\(([^)]*)\)/g, "[$1]($2)")
    }).join("")
  }
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
    if (selected && selected.subs[n]) act(["sub-image-remove", selected.id, String(n), String(k), "--expect", selected.subs[n].text])
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
    if (viewEntry.isSub) act(["sub-edit", selected.id, String(n), text, "--expect", before])
    else act(["log-edit", viewEntry.id !== undefined ? viewEntry.id : selected.id, String(n), text, "--expect", before])
    viewEntry = Object.assign({}, viewEntry, { text: text })
    viewEditing = false
    forceActiveFocus()
  }
  // closing keeps what's being typed (a sub-todo, an entry in the viewer)
  // rather than dropping it; Esc still cancels
  property bool closing: false
  // (run on their own: the tab may be torn down before a queued save runs)
  function keepTyping() {
    var was = closing
    closing = true
    if (todoTab.subEdit.todoId !== "") todoTab.subEdit.commit()
    if (viewEditing) saveEdit()
    closing = was
  }
  onVisibleChanged: if (!visible) keepTyping()
  Connections {
    target: tasks.bar
    ignoreUnknownSignals: true
    function onCommandCenterOpenChanged() { if (tasks.bar && !tasks.bar.commandCenterOpen) tasks.keepTyping() }
  }
  Component.onDestruction: keepTyping()
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
        Qt.callLater(function() { logTab.logList.positionViewAtIndex(i, ListView.Beginning) })
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
  // a long sub-todo, shortened for the log and progress panels: its first
  // line, cut after 7-10 words (at a sentence break if there is one, and not
  // on a dangling "the" / "to" / "that")
  function brief(text) {
    var toks = (text || "").split("\n")[0].trim().split(/\s+/), ends = []
    toks.forEach(function(w, i) { if (/[A-Za-z0-9]/.test(w)) ends.push(i + 1) })   // "+" isn't a word
    if (ends.length <= 10) return toks.join(" ")
    var cut = ends[7]
    for (var n = 10; n >= 7; n--) if (/[.,;:!?]$/.test(toks[ends[n - 1] - 1])) { cut = ends[n - 1]; break }
    var out = toks.slice(0, cut)
    while (out.length > 5 && /^(a|an|the|to|of|and|or|that|which|with|for|in|on|at|by|from|is|be|will)$/i.test(out[out.length - 1])) out.pop()
    return out.join(" ").replace(/[,;:]$/, "") + "…"
  }
  function entryTag(e) {
    var grp = entryGroup(e)
    var title = e.id !== undefined ? e.title : (selected ? selected.title : "")
    var sup = grp ? superOf(grp) : ""
    return (sup ? sup + "  \u203a  " : "") + (grp ? grp + "  \u203a  " : "") + title + (e.sub ? "   \u21b3  " + brief(e.sub) : "")
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
      var mine = logEntries.filter(function(e) { return e.sub === sb.text.split("\n")[0].trim() })
      if (!mine.length) return
      var key = sectionKey(sb.text), shut = sectionFolded(key)
      rows.push({ kind: "head", what: "sub", i: i, sub: sb, key: key, level: 0, label: brief(sb.text), count: mine.length, collapsed: shut })
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
    act(["sub-move", selected.id, String(sec), String(nb), "--expect", selected.subs[sec].text])
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
    // closing: the tab (and its runner) is going away, so this runs on its own
    if (closing) { Quickshell.execDetached(["python3", script].concat(args)); return }
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
          // files that couldn't be read are left out: say which
          if (r.broken && r.broken.length)
            tasks.error = "couldn't read " + r.broken.map(function(b) { return "Todos/" + b.id + ".md" }).join(", ") + " (" + r.broken[0].error + ")"
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
    act(["sub-move", t.id, String(i), String(j), "--expect", t.subs[i].text])
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
  function remove(id, archived) {
    if (armedDelete !== id) { armedDelete = id; disarm.restart(); return }
    armedDelete = ""
    act(archived ? ["delete", id, "--archived"] : ["delete", id])
  }
  Timer { id: disarm; interval: 2500; onTriggered: tasks.armedDelete = "" }
  // a sub-todo the same way: d marks it, d again (within 2.5 s) deletes it
  property string armedSub: ""                // "<todo id>/<position>"
  function removeSub(t, i) {
    var key = t.id + "/" + i
    if (armedSub !== key) { armedSub = key; disarmSub.restart(); return }
    armedSub = ""
    act(["sub-delete", t.id, String(i), "--expect", t.subs[i].text])
    subIndex = Math.max(0, Math.min(subIndex, t.subs.length - 2))
  }
  Timer { id: disarmSub; interval: 2500; onTriggered: tasks.armedSub = "" }
  onSubIndexChanged: armedSub = ""
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
      helpCard.helpFlick.contentY = Math.max(0, Math.min(helpCard.helpFlick.contentHeight - helpCard.helpFlick.height, helpCard.helpFlick.contentY + (k === Qt.Key_Down || txt === "j" ? 60 : -60)))
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
        else if ((txt === "e" || k === Qt.Key_F2) && t) { todoTab.renameInput.text = t.title; todoTab.renameInput.forceActiveFocus() }
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
          if (to >= 0 && to < n) { act(["sub-move", t.id, String(subIndex), String(to), "--expect", t.subs[subIndex].text]); subIndex = to }
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
        else if ((txt === "e" || k === Qt.Key_F2) && t && n) todoTab.subEdit.begin(t, subIndex)
        else if ((txt === "d" || k === Qt.Key_Delete) && t && n) removeSub(t, subIndex)
        else if (txt === "K" && t && subIndex > 0) { act(["sub-move", t.id, String(subIndex), String(subIndex - 1), "--expect", t.subs[subIndex].text]); subIndex-- }
        else if (txt === "J" && t && subIndex < n - 1) { act(["sub-move", t.id, String(subIndex), String(subIndex + 1), "--expect", t.subs[subIndex].text]); subIndex++ }
        else return
      }
    } else if (tab === "log") {
      var lt = selected, ln = lt ? lt.subs.length : 0, ne = logEntryRows.length
      var shiftMove = (up || down) && (event.modifiers & Qt.ShiftModifier)
      if (txt === "w" && lt) logInput.forceActiveFocus()
      else if (txt === "L") jumpLogHere()
      else if (txt === "s" || txt === "S") toggleLogSort(txt === "S")
      else if (k === Qt.Key_PageDown) logTab.logList.flick(0, -1600)
      else if (k === Qt.Key_PageUp) logTab.logList.flick(0, 1600)
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
      // a: straight to the first thing in the archive
      else if (txt === "a" && archiveRows.length) { progressPane = "archive"; archiveIndex = 0 }
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
        // d, then d again: delete it (with its log and pictures, into the trash)
        else if (ar && ar.kind === "todo" && (txt === "d" || k === Qt.Key_Delete)) remove(ar.t.id, true)
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

  TavernBackdrop { id: tavernDeep; tasks: tasksTab }

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
      textFormat: Text.PlainText
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
      pal: tasks.bar && tasks.bar.slimePalette ? tasks.bar.slimePalette : ({})
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

  Row {
    id: signs
    x: 6
    spacing: 16
    TavernSign { tasks: tasksTab; key: "todo"; label: "Todo"; glyph: "" }
    TavernSign { tasks: tasksTab; key: "log"; label: "Task Log"; glyph: "" }
    TavernSign { tasks: tasksTab; key: "progress"; label: "Progress"; glyph: "" }
  }
  Text {
    textFormat: Text.PlainText
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

  readonly property real contentTop: 58

  // ======================================================================== TODO
  TodoPage { id: todoTab; tasks: tasksTab }
  property var subInput: null
  property var logInput: null
  property alias newInput: todoTab.newInput

  // ===================================================================== TASK LOG
  LogPage { id: logTab; tasks: tasksTab }

  // ===================================================================== PROGRESS
  ProgressPage { id: progressTab; tasks: tasksTab }
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
      else if (it.kind === "rename") { todoTab.renameInput.text = todo.title; tasks.selectedId = todo.id; visible = false; todoTab.renameInput.forceActiveFocus(); return }
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
              textFormat: Text.PlainText
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
        textFormat: Text.PlainText
        visible: menu.headGroup === "" && !menu.archived
        width: menuCol.width
        wrapMode: Text.Wrap
        text: menu.headSuper !== "" ? "deleting a super group keeps its groups" : "d d on a group deletes it (its todos just lose the group)"
        color: tasks.cc.ink; opacity: 0.55
        font.family: tasks.cc.font; font.pixelSize: Math.round(9 * tasks.fs) }
      Field {
        tasks: tasksTab
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
          textFormat: Text.PlainText
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
        text: tasks.safeMarkdown(viewer.e.text)
        wrapMode: Text.Wrap
        textFormat: Text.MarkdownText
        color: viewer.ink
        font.family: viewer.font
        font.pixelSize: Math.round(19 * tasks.fs)
        lineHeight: 1.2
      }
      // a sub-todo's pictures: pinned to the sheet
      Text {
        textFormat: Text.PlainText
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
                Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "\uf00d"; color: pin.armed ? "white" : viewer.ink; font.family: tasks.cc.font; font.pixelSize: 11 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                  onClicked: { tasks.picIndex = pin.index; if (tasks.armedPic !== pin.index) { tasks.armedPic = pin.index; disarmPic.restart() } else tasks.removePicture(viewer.e.n, pin.index) } }
              }
            }
            HoverHandler { id: pinHover }
            Text {
              textFormat: Text.PlainText
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
        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "\uf03e  drop to pin it to this sub-todo"; color: viewer.ink; font.family: viewer.font; font.pixelSize: 24 }
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
        Keys.onEnterPressed: tasks.finishRenameGroup(text.trim())
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
                          ["d d", "delete"], ["J K  Shift ↑↓  drag", "move down / up"], ["←  Esc", "back to the list"]]],
    ["EVERYWHERE", [["Shift ↑↓", "move the highlighted todo, sub-todo, group or log section"]]],
    ["TASK LOG", [["L  (here or on the Todo tab)", "jump to the selected todo's log"], ["L  on a super group, group, todo or sub-todo (here or on the Todo tab)", "jump to its section of the log"], ["↑ ↓", "pick a todo"], ["→ … ↓", "into the lanes, then on down into the log"], ["s  S", "log view: newest first · by sub-todo · all by todo · by group · by super group"], ["Enter on an entry", "open it over the panel"], ["c  /  e", "copy / edit the entry"], ["←  z  /  Enter  →  on a section", "fold / unfold it (by sub-todo)"], ["←  z  /  →  Enter on a heading", "fold / unfold its group"], ["→  Enter", "into its lanes"], ["→  Space  /  ←", "move a sub-todo a lane on / back"], ["Tab  Shift+Tab  in the lanes", "hop to the next / previous lane"], ["Enter on a sub-todo", "open it over the panel"],
                  ["w", "write in the log (about the picked sub-todo)"], ["PgUp PgDn", "scroll the log"], ["click / right-click", "a lane on / back"]]],
    ["PROGRESS", [["↑ ↓", "pick"], ["Enter  Space", "expand / collapse"], ["→  ←", "open / close a todo, then fold its group"], ["z", "fold the group"], ["A", "archive"], ["↓ past the end", "into the archive"], ["a", "jump to the archive's first item"],
                  ["/", "search the archive (Enter: into the results)"], ["Enter  r", "restore an archived list (you stay in the archive)"], ["r  on an archive heading", "restore the whole group / super group"], ["d d  on an archived todo", "delete it (to the trash)"], ["g  /  right-click", "group, restore or delete an archived list"], ["←  z  /  Enter  →  on a heading", "fold / unfold an archive group"], ["↑ at the top  Esc", "back up"]]]
        ]
  onShowHelpChanged: if (showHelp) { helpSection = tab === "log" ? 4 : tab === "progress" ? 5 : 1; helpCard.helpFlick.contentY = 0 }
  HelpCard { id: helpCard; tasks: tasksTab }

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
      textFormat: Text.PlainText
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
        property real blobMode: 2   // a drip panel: its edge jiggles
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
              textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
            textFormat: Text.PlainText
            visible: files.count === 0 && files.status === FolderListModel.Ready
            anchors.centerIn: parent
            text: "No pictures or folders here  (⌫ goes up)"
            color: tasks.cc.ink; opacity: 0.7; font.family: tasks.cc.font; font.pixelSize: 12
          }
        }
        Text {
          textFormat: Text.PlainText
          text: "arrows / hjkl pick · Enter opens a folder or adds the picture · ⌫ up · ~ home · Esc closes"
          color: tasks.cc.ink; opacity: 0.65; font.family: tasks.cc.font; font.pixelSize: Math.round(10 * tasks.fs)
        }
      }
    }
  }
}
