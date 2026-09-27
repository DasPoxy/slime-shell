import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../slime.menu/Fuzzy.js" as Fuzzy

// Start-Up: apps launched when you log in, and the workspace each one opens
// on. Saved to ~/.config/omarchy/slime-shell/startup.json and run by
// slime-startup, which the tab hooks into ~/.config/hypr/autostart.lua (a
// fenced block, added the first time you pick an app). Anything already in
// autostart.lua is listed read-only underneath.
Item {
  id: startup
  // the command centre's text size (Settings → Command centre → text size)
  readonly property real fs: cc && cc.fontScale ? cc.fontScale : 1

  property var cc: null
  property var apps: []                 // [{id, name, workspace, enabled}]
  property string query: ""
  property bool hooked: true
  property var existing: []             // other autostart.lua lines
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/slime-shell/startup.json"
  readonly property string script: Qt.resolvedUrl("slime-startup").toString().replace("file://", "")
  readonly property var library: cc && cc.bar.shell && cc.bar.shell.appLibrary ? cc.bar.shell.appLibrary : null
  readonly property var allApps: {
    if (library) return library.sortedEntries("")
    return DesktopEntries.applications.values.filter(function(e) { return !e.noDisplay })
  }
  function nameOf(e) { return library ? library.entryName(e) : e.name }
  function iconOf(icon) { return library ? library.iconSource(icon) : Quickshell.iconPath(icon, "application-x-executable") }
  function entryFor(id) {
    for (var i = 0; i < allApps.length; i++) if (allApps[i].id === id) return allApps[i]
    return null
  }

  readonly property var matches: {
    var q = query.trim()
    if (q === "") return []
    var taken = {}
    for (var i = 0; i < apps.length; i++) taken[apps[i].id] = true
    var scored = []
    for (var j = 0; j < allApps.length; j++) {
      var e = allApps[j]
      if (taken[e.id]) continue
      var s = Fuzzy.best(q, [nameOf(e), e.genericName || ""])
      if (s >= 0) scored.push({ e: e, s: s })
    }
    scored.sort(function(a, b) { return b.s - a.s })
    return scored.slice(0, 6).map(function(x) { return x.e })
  }

  implicitHeight: column.implicitHeight

  // ---- storage --------------------------------------------------------------
  FileView {
    id: file
    path: startup.configPath
    printErrors: false
    atomicWrites: true
    onLoaded: { try { startup.apps = JSON.parse(text()) } catch (e) { startup.apps = [] } }
    onLoadFailed: startup.apps = []
  }
  function save(next) {
    apps = next
    file.setText(JSON.stringify(next, null, 2) + "\n")
    if (!hooked && next.length > 0) { installer.running = true }
  }
  function add(e) { save(apps.concat([{ id: e.id, name: nameOf(e), workspace: 0, enabled: true }])); query = ""; search.text = "" }
  function update(i, key, value) {
    var next = apps.map(function(a) { return Object.assign({}, a) })
    next[i][key] = value
    save(next)
  }
  function remove(i) { save(apps.filter(function(_, k) { return k !== i })) }

  Process {
    id: statusProbe
    command: ["bash", startup.script, "status"]
    running: true
    stdout: StdioCollector { onStreamFinished: startup.hooked = text.trim() === "yes" }
  }
  Process {
    id: installer
    command: ["bash", startup.script, "install"]
    onExited: statusProbe.running = true
  }
  Process {
    id: existingProbe
    running: true
    command: ["sh", "-c", "sed -n '/slime-shell startup/,/slime-shell startup/!p' \"$HOME/.config/hypr/autostart.lua\" | grep -E '^[[:space:]]*o\\.(launch|exec)_on_start' || true"]
    stdout: StdioCollector {
      onStreamFinished: startup.existing = text.split("\n").filter(function(l) { return l.trim() !== "" })
        .map(function(l) { var m = l.match(/\("(.*)"\)/); return m ? m[1] : l.trim() })
    }
  }

  // ---- ui ---------------------------------------------------------------------
  Column {
    id: column
    width: parent.width
    spacing: 10

    CcHeading {
      cc: startup.cc
      text: startup.apps.length === 0 ? "NOTHING LAUNCHES AT LOGIN YET — ADD AN APP BELOW"
        : startup.apps.filter(function(a) { return a.enabled !== false }).length + " APPS LAUNCH AT LOGIN"
    }

    Repeater {
      model: startup.apps
      Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property var entry: startup.entryFor(modelData.id)
        width: column.width
        height: 44
        radius: 14
        color: startup.cc.wash
        opacity: modelData.enabled === false ? 0.55 : 1

        IconImage {
          id: icon
          x: 10
          anchors.verticalCenter: parent.verticalCenter
          implicitSize: 26
          source: row.entry ? startup.iconOf(row.entry.icon) : ""
        }
        Text {
          x: icon.x + 36
          width: 150
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: row.modelData.name
          color: startup.cc.ink
          font.family: startup.cc.font
          font.pixelSize: Math.round(13 * startup.fs)
          font.bold: true
        }
        // workspace picker: auto, then 1..10
        Row {
          x: icon.x + 36 + 158
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Repeater {
            model: 11
            Rectangle {
              required property int index
              readonly property bool on: (row.modelData.workspace || 0) === index
              width: index === 0 ? 36 : 20
              height: 20
              radius: 10
              color: on ? startup.cc.ink : Qt.rgba(1, 1, 1, 0.5)
              Text {
                anchors.centerIn: parent
                text: parent.index === 0 ? "auto" : (parent.index === 10 ? "0" : parent.index)
                color: parent.on ? startup.cc.slime : startup.cc.ink
                font.family: startup.cc.font
                font.pixelSize: Math.round(10 * startup.fs)
                font.bold: true
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: startup.update(row.index, "workspace", parent.index)
              }
              CcFocus { onActivate: startup.update(row.index, "workspace", parent.index) }
            }
          }
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          spacing: 6
          CcButton {
            cc: startup.cc
            text: row.modelData.enabled === false ? "off" : "on"
            on: row.modelData.enabled !== false
            fontSize: 11
            onClicked: startup.update(row.index, "enabled", row.modelData.enabled === false)
          }
          CcButton { cc: startup.cc; icon: ""; fontSize: 11; onClicked: startup.remove(row.index) }
        }
      }
    }

    // add an app
    Rectangle {
      width: column.width
      height: 36
      radius: 18
      color: Qt.rgba(1, 1, 1, 0.6)
      border.color: startup.cc.ink
      border.width: 2
      Text {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: startup.cc.ink
        font.family: startup.cc.font
        font.pixelSize: Math.round(13 * startup.fs) }
      CcFocus { onActivate: search.forceActiveFocus() }
      TextInput {
        id: search
        x: 36
        width: parent.width - 50
        anchors.verticalCenter: parent.verticalCenter
        color: startup.cc.ink
        font.family: startup.cc.font
        font.pixelSize: Math.round(14 * startup.fs)
        font.bold: true
        clip: true
        onTextChanged: startup.query = text
        Keys.onReturnPressed: if (startup.matches.length) startup.add(startup.matches[0])
      }
      Text {
        visible: search.text === ""
        x: 36
        anchors.verticalCenter: parent.verticalCenter
        text: "add an app to start at login…"
        color: startup.cc.ink
        opacity: 0.5
        font.family: startup.cc.font
        font.pixelSize: Math.round(13 * startup.fs) }
    }
    Flow {
      width: column.width
      spacing: 6
      visible: startup.matches.length > 0
      Repeater {
        model: startup.matches
        CcButton {
          required property var modelData
          cc: startup.cc
          icon: ""
          text: startup.nameOf(modelData)
          onClicked: startup.add(modelData)
        }
      }
    }

    Text {
      visible: !startup.hooked && startup.apps.length > 0
      width: column.width
      wrapMode: Text.Wrap
      text: "Hooking into ~/.config/hypr/autostart.lua…"
      color: startup.cc.ink
      font.family: startup.cc.font
      font.pixelSize: Math.round(11 * startup.fs)
      opacity: 0.7
    }

    CcHeading {
      visible: startup.existing.length > 0
      cc: startup.cc
      topPadding: 6
      text: "ALSO STARTED BY AUTOSTART.LUA (EDIT THAT FILE TO CHANGE)"
    }
    Repeater {
      model: startup.existing
      Text {
        required property string modelData
        width: column.width
        elide: Text.ElideRight
        text: "•  " + modelData
        color: startup.cc.ink
        font.family: startup.cc.font
        font.pixelSize: Math.round(12 * startup.fs)
        opacity: 0.8
      }
    }
  }
}
