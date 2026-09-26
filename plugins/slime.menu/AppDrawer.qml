import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"
import "Fuzzy.js" as Fuzzy

// The Slime app launcher. Clicked on the bar it drips out of the launcher
// monster; summoned by keybind it floats in the middle of the screen
// (`floating`). Type to fuzzy-search apps and Omarchy's menu commands
// (every action in the Omarchy menu, plus your menu extensions); start with
// ">" to search commands only. Arrows / Tab move, Enter runs, Esc closes.
// Apps come from Omarchy's app library (same hidden entries and launching as
// the Omarchy launcher), falling back to Quickshell's desktop entries.
SlimeKeyboardPanel {
  id: drawer

  required property var widget          // the launcher bar widget
  property string query: ""
  property int selected: 0
  property var commands: []             // from commands.py

  readonly property var library: bar && bar.shell && bar.shell.appLibrary ? bar.shell.appLibrary : null
  readonly property int columns: 6
  readonly property real cell: (contentWidth - 2 * padding) / columns
  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property color ink: slime ? bar.slimeInk : Color.foreground
  readonly property bool commandsOnly: query.indexOf(">") === 0
  readonly property string term: commandsOnly ? query.slice(1).trim() : query.trim()

  readonly property var allApps: {
    if (library) return library.sortedEntries("")
    return DesktopEntries.applications.values.filter(function(e) { return !e.noDisplay })
      .sort(function(a, b) { return a.name.localeCompare(b.name) })
  }

  function rank(list, fieldsOf, limit) {
    var scored = []
    for (var i = 0; i < list.length; i++) {
      var s = Fuzzy.best(term, fieldsOf(list[i]))
      if (s >= 0) scored.push({ item: list[i], s: s })
    }
    scored.sort(function(a, b) { return b.s - a.s })
    return scored.slice(0, limit).map(function(x) { return x.item })
  }

  readonly property var apps: {
    if (commandsOnly) return []
    if (term === "") return allApps
    return rank(allApps, function(e) {
      return [nameFor(e), (e.genericName || "") + " " + (e.keywords ? e.keywords.join(" ") : "") + " " + (e.comment || "")]
    }, 12)
  }
  readonly property var cmds: {
    if (term === "" && !commandsOnly) return []
    if (term === "") return commands.slice(0, 40)
    return rank(commands, function(c) { return [c.label, c.path + " " + c.label, c.keywords] }, commandsOnly ? 40 : 8)
  }
  readonly property int total: apps.length + cmds.length

  // held as a property: the panel's default children are its card content
  property Process commandLoader: Process {
    command: ["python3", Qt.resolvedUrl("commands.py").toString().replace("file://", "")]
    stdout: StdioCollector {
      onStreamFinished: { try { drawer.commands = JSON.parse(text) } catch (e) {} }
    }
  }

  function iconFor(entry) {
    if (library) return library.iconSource(entry.icon)
    return Quickshell.iconPath(entry.icon, "application-x-executable")
  }
  function nameFor(entry) { return library ? library.entryName(entry) : entry.name }
  function launch(entry) {
    if (!entry) return
    if (library) library.launch(entry.id, nameFor(entry))
    else entry.execute()
    widget.appsOpen = false
  }
  function runCommand(c) {
    if (!c) return
    widget.appsOpen = false
    Quickshell.execDetached(["bash", "-c", c.action])
  }
  function activate(i) {
    if (i < apps.length) launch(apps[i])
    else runCommand(cmds[i - apps.length])
  }
  // Grid-aware movement: left/right step, up/down jump a row inside the apps
  // grid and one row at a time through the commands.
  function move(key) {
    if (total === 0) return
    var i = selected, inApps = i < apps.length
    if (key === "right" || key === "tab") i += 1
    else if (key === "left" || key === "backtab") i -= 1
    else if (key === "down") i += inApps && i + columns < apps.length ? columns : (inApps ? Math.max(1, apps.length - i) : 1)
    else if (key === "up") i -= !inApps ? 1 : columns
    selected = Math.max(0, Math.min(total - 1, i))
    scroller.reveal(selected)
  }

  onQueryChanged: { selected = 0; scroller.contentY = 0 }
  onOpenChanged: if (open) { query = ""; search.text = ""; selected = 0; scroller.contentY = 0; drawer.commandLoader.running = true }

  contentWidth: fittedContentWidth(Style.space(580))
  contentHeight: fittedContentHeight(header.height + 12 + searchBox.height + 12 + cell * 1.15 * 4 + 4)
  focusTarget: search

  // held as a property: the panel's default children are its card content
  property QtObject look: QtObject {
    readonly property var bar: drawer.bar
    readonly property color ink: drawer.ink
    readonly property color slime: drawer.slime ? drawer.bar.slimeColor : Color.accent
    readonly property string font: drawer.bar ? drawer.bar.fontFamily : Style.font.family
  }

  Item {
    anchors.fill: parent

    // ---- header -----------------------------------------------------------------
    Item {
      id: header
      width: parent.width
      height: 34
      SlimeMonster {
        id: headMonster
        anchors.verticalCenter: parent.verticalCenter
        size: 30
        variant: drawer.widget.current[2] === "monster" ? drawer.widget.current[3] : 0
        mood: drawer.query !== "" ? "emote" : "idle"
        time: drawer.slime ? drawer.bar.animTime : 0
        body: drawer.slime ? drawer.bar.monsterBody : "white"
        ink: drawer.ink
        eye: drawer.slime ? drawer.bar.paperColor : "white"
        blush: drawer.slime ? drawer.bar.monsterBlush : "pink"
      }
      Text {
        x: headMonster.width + 10
        anchors.verticalCenter: parent.verticalCenter
        text: drawer.query === "" ? drawer.allApps.length + " apps  ·  type > for commands"
          : drawer.apps.length + " apps · " + drawer.cmds.length + " commands"
        color: drawer.ink
        font.family: drawer.bar && drawer.bar.displayFontFamily ? drawer.bar.displayFontFamily : look.font
        font.weight: drawer.bar ? drawer.bar.displayWeight : Font.Black
        font.pixelSize: 16
      }
      CcButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        cc: look
        icon: ""
        text: "Omarchy menu"
        fontSize: 11
        onClicked: {
          drawer.widget.appsOpen = false
          Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "omarchy.menu", "{\"menu\":\"root\"}"])
        }
      }
    }

    // ---- search -----------------------------------------------------------------
    Rectangle {
      id: searchBox
      y: header.height + 12
      width: parent.width
      height: 38
      radius: 19
      color: Qt.rgba(1, 1, 1, 0.6)
      border.color: drawer.ink
      border.width: 2

      Text {
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        text: drawer.commandsOnly ? "" : ""
        color: drawer.ink
        font.family: look.font
        font.pixelSize: 14
      }
      TextInput {
        id: search
        x: 38
        width: parent.width - 52
        anchors.verticalCenter: parent.verticalCenter
        color: drawer.ink
        selectionColor: drawer.ink
        selectedTextColor: drawer.slime ? drawer.bar.paperColor : "white"
        font.family: look.font
        font.pixelSize: 15
        font.bold: true
        clip: true
        onTextChanged: drawer.query = text
        Keys.onPressed: event => {
          var keys = {}
          keys[Qt.Key_Right] = "right"; keys[Qt.Key_Left] = "left"; keys[Qt.Key_Down] = "down"; keys[Qt.Key_Up] = "up"
          if (event.key === Qt.Key_Escape) { drawer.widget.appsOpen = false; event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { drawer.activate(drawer.selected); event.accepted = true }
          else if (event.key === Qt.Key_Tab) { drawer.move("tab"); event.accepted = true }
          else if (event.key === Qt.Key_Backtab) { drawer.move("backtab"); event.accepted = true }
          else if (keys[event.key] && (event.key === Qt.Key_Up || event.key === Qt.Key_Down || search.text === "" || (event.key === Qt.Key_Right && search.cursorPosition === search.text.length) || (event.key === Qt.Key_Left && search.cursorPosition === 0))) {
            drawer.move(keys[event.key]); event.accepted = true
          }
        }
      }
      Text {
        visible: search.text === ""
        x: 38
        anchors.verticalCenter: parent.verticalCenter
        text: "search the ooze…"
        color: drawer.ink
        opacity: 0.5
        font.family: look.font
        font.pixelSize: 14
      }
    }

    // ---- results: apps grid, then commands --------------------------------------------
    Flickable {
      id: scroller
      y: searchBox.y + searchBox.height + 12
      width: parent.width
      height: parent.height - y
      clip: true
      contentHeight: results.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      // keep result i in view
      function reveal(i) {
        var top, h
        if (i < drawer.apps.length) { top = Math.floor(i / drawer.columns) * drawer.cell * 1.15; h = drawer.cell * 1.15 }
        else { top = appGrid.height + (drawer.apps.length ? 12 : 0) + cmdHeading.height + 6 + (i - drawer.apps.length) * 34; h = 34 }
        if (top < contentY) contentY = top
        else if (top + h > contentY + height) contentY = top + h - height
      }

      Column {
        id: results
        width: scroller.width
        spacing: 6

        Grid {
          id: appGrid
          columns: drawer.columns
          visible: drawer.apps.length > 0
          Repeater {
            model: drawer.apps
            Item {
              id: tile
              required property var modelData
              required property int index
              readonly property bool current: index === drawer.selected
              width: drawer.cell
              height: drawer.cell * 1.15

              Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 16
                color: tile.current ? Qt.rgba(1, 1, 1, 0.7) : (tileHover.hovered ? Qt.rgba(1, 1, 1, 0.4) : "transparent")
                border.color: tile.current ? drawer.ink : "transparent"
                border.width: 2
              }
              HoverHandler { id: tileHover }

              IconImage {
                id: appIcon
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                implicitSize: Math.round(drawer.cell * 0.42)
                source: drawer.iconFor(tile.modelData)
                asynchronous: true
                transform: Translate { y: tile.current && drawer.slime ? Math.sin(drawer.bar.animTime * 3) * 2 : 0 }
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: appIcon.y + appIcon.implicitSize + 6
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                text: drawer.nameFor(tile.modelData)
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                color: drawer.ink
                font.family: look.font
                font.pixelSize: 11
                font.bold: tile.current
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: drawer.launch(tile.modelData)
              }
            }
          }
        }

        CcHeading {
          id: cmdHeading
          visible: drawer.cmds.length > 0
          cc: look
          text: "OMARCHY COMMANDS"
        }
        Repeater {
          model: drawer.cmds
          Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: drawer.apps.length + index === drawer.selected
            width: results.width
            height: 28
            radius: 12
            color: row.current ? Qt.rgba(1, 1, 1, 0.7) : (rowHover.hovered ? Qt.rgba(1, 1, 1, 0.4) : Qt.rgba(1, 1, 1, 0.18))
            border.color: row.current ? drawer.ink : "transparent"
            border.width: 2
            HoverHandler { id: rowHover }
            Text {
              id: cmdIcon
              x: 12
              width: 18
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.icon
              color: drawer.ink
              font.family: look.font
              font.pixelSize: 14
            }
            Row {
              x: cmdIcon.x + cmdIcon.width + 8
              width: parent.width - x - 12
              anchors.verticalCenter: parent.verticalCenter
              clip: true
              Text {
                visible: row.modelData.path !== ""
                text: row.modelData.path + " › "
                color: drawer.ink
                opacity: 0.6
                font.family: look.font
                font.pixelSize: 12
              }
              Text {
                text: row.modelData.label
                color: drawer.ink
                font.family: look.font
                font.pixelSize: 12
                font.bold: true
              }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: drawer.runCommand(row.modelData)
            }
          }
        }
      }
    }
  }
}
