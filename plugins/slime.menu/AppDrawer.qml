import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "../slime.bar/ui"
import "../slime.bar/commandcenter"

// The Slime app launcher: drips out of the launcher monster with a search
// field and a grid of apps. Type to filter, arrows to move, Enter to launch,
// Esc to close. Search, hidden entries and launching come from Omarchy's own
// app library (same results as the Omarchy launcher) when the shell offers
// it, falling back to Quickshell's desktop entries.
SlimeKeyboardPanel {
  id: drawer

  required property var widget          // the launcher bar widget
  property string query: ""
  property int selected: 0

  readonly property var library: bar && bar.shell && bar.shell.appLibrary ? bar.shell.appLibrary : null
  readonly property int columns: 6
  readonly property real cell: (contentWidth - 2 * padding) / columns
  readonly property bool slime: !!bar && bar.slimeSkin === true
  readonly property color ink: slime ? bar.slimeInk : Color.foreground

  readonly property var apps: {
    query   // re-evaluate on typing
    if (library) return library.sortedEntries(query)
    var all = DesktopEntries.applications.values.filter(function(e) { return !e.noDisplay })
    var q = query.toLowerCase().trim()
    if (q !== "") all = all.filter(function(e) {
      return (e.name + " " + (e.genericName || "") + " " + (e.comment || "")).toLowerCase().indexOf(q) !== -1
    })
    return all.sort(function(a, b) { return a.name.localeCompare(b.name) })
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
  function move(delta) {
    if (apps.length === 0) return
    selected = Math.max(0, Math.min(apps.length - 1, selected + delta))
    grid.positionViewAtIndex(selected, GridView.Contain)
  }

  onQueryChanged: selected = 0
  onOpenChanged: if (open) { query = ""; search.text = ""; selected = 0 }

  contentWidth: fittedContentWidth(Style.space(560))
  contentHeight: fittedContentHeight(header.height + 12 + searchBox.height + 12 + Math.min(grid.contentHeight, cell * 1.15 * 4) + 4)
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

    // ---- header: the monster, a title, a way to the Omarchy menu ----------------
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
        text: drawer.apps.length + (drawer.query === "" ? " apps" : " found")
        color: drawer.ink
        font.family: drawer.bar && drawer.bar.displayFontFamily ? drawer.bar.displayFontFamily : look.font
        font.weight: drawer.bar ? drawer.bar.displayWeight : Font.Black
        font.pixelSize: 17
      }
      CcButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        cc: look
        icon: "\uf0c9"
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
        text: ""
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
          if (event.key === Qt.Key_Escape) { drawer.widget.appsOpen = false; event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { drawer.launch(drawer.apps[drawer.selected]); event.accepted = true }
          else if (event.key === Qt.Key_Right) { drawer.move(1); event.accepted = true }
          else if (event.key === Qt.Key_Left) { drawer.move(-1); event.accepted = true }
          else if (event.key === Qt.Key_Down) { drawer.move(drawer.columns); event.accepted = true }
          else if (event.key === Qt.Key_Up) { drawer.move(-drawer.columns); event.accepted = true }
          else if (event.key === Qt.Key_Tab) { drawer.move(event.modifiers & Qt.ShiftModifier ? -1 : 1); event.accepted = true }
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

    // ---- the apps -------------------------------------------------------------------
    GridView {
      id: grid
      y: searchBox.y + searchBox.height + 12
      width: parent.width
      height: parent.height - y
      clip: true
      cellWidth: drawer.cell
      cellHeight: drawer.cell * 1.15
      model: drawer.apps
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: drawer.selected

      delegate: Item {
        id: tile
        required property var modelData
        required property int index
        readonly property bool current: index === drawer.selected
        width: grid.cellWidth
        height: grid.cellHeight

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
          // bob a little when selected, like it's floating
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
          onEntered: {}
        }
      }
    }
  }
}
