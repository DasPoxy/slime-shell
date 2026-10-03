import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQml
import QtQuick.Shapes
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../BarModel.js" as BarModel
import "../SlimeHub.js" as SlimeHub
import "../commandcenter"
import "../ui"
import "../dock"

PanelWindow {
  id: barWindow
  // the bar (Bar.qml), which this used to sit inside
  property var root: null

  // Hiding parks the bar just past its screen edge instead of unmapping it.
  // Unmapping frees the layer surface and the whole scene graph, so every
  // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
  // textures — which measures ~150ms against ~20ms to tear down. Parking
  // keeps the surface alive, so showing is only a margin change.
  visible: !remapGuard.remapping
  // Exactly the bar: third-party widget panels (Omarchy's PopupCard and
  // friends) measure and place themselves from this window's size. The
  // drips and the command centre live in skinWindow, just past the bar.
  exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
  exclusiveZone: root.barSize

  ScreenMoveRemap {
    id: remapGuard
    window: barWindow
  }

  margins {
    top: root.barHidden && root.position === "top" ? -barWindow.implicitHeight : 0
    bottom: root.barHidden && root.position === "bottom" ? -barWindow.implicitHeight : 0
    left: root.barHidden && root.position === "left" ? -barWindow.implicitWidth : 0
    right: root.barHidden && root.position === "right" ? -barWindow.implicitWidth : 0
  }

  anchors {
    top: root.position === "top" || root.vertical
    bottom: root.position === "bottom" || root.vertical
    left: root.position === "left" || !root.vertical
    right: root.position === "right" || !root.vertical
  }

  readonly property real thickness: root.barSize
  implicitWidth: root.vertical ? thickness : 0
  implicitHeight: root.vertical ? 0 : thickness
  color: root.slimeSkin || root.transparent ? "transparent" : root.background
  surfaceFormat.opaque: false
  WlrLayershell.namespace: "omarchy-bar"
  // "behind": the bar surface sits on the Bottom layer so drips hang behind
  // windows (the exclusive zone still keeps tiled windows off the bar). It
  // comes back to Top while the command centre is open so that stays usable.
  // keyboard input for the command centre's text fields, only while it's open
  WlrLayershell.keyboardFocus: root.hoverKeysWindow === barWindow ? WlrKeyboardFocus.Exclusive
    : ccShown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  readonly property bool slimeBehind: root.slimeSkin && root.layerReady && root.slimeLayer === "behind" && !ccShown && !root.panelRaised
  WlrLayershell.layer: slimeBehind ? WlrLayer.Bottom : WlrLayer.Top

  // ---- Slime skin ----
  // Command centre animation: 0 closed, 1 fully dripped open.
  property real ccProgress: 0
  readonly property bool ccShown: root.slimeSkin && (root.commandCenterOpen || ccProgress > 0)
  // Only as tall as needed: bar + drips while closed, room for the command
  // centre while it's open or animating. Fewer pixels for the shader.
  // The command centre's extent along the bar and away from it: content is
  // always laid out landscape, so on a side bar "along" is its height.
  // The command centre's height, capped to this screen (the height is
  // shared by every bar, but each screen may be a different size).
  readonly property real ccMaxHeight: root.vertical ? (screen ? screen.height - 32 : 1000) : ccMaxAway
  readonly property real ccHeight: Math.min(root.commandCenterHeight, ccMaxHeight)
  // ...and its width, narrowed on small or portrait screens
  readonly property real ccWidth: !screen ? root.commandCenterWidth
    : Math.min(root.commandCenterWidth, root.vertical ? screen.width - root.barSize - 24 : screen.width - 32)
  // narrow screens shrink the whole command centre rather than squeeze its
  // tabs (their layouts are built for the full width)
  readonly property real ccScale: ccWidth / root.commandCenterWidth
  readonly property real ccAlong: root.vertical ? ccHeight : ccWidth
  readonly property real ccAway: root.vertical ? ccWidth : ccHeight
  // One fixed size for the whole time the skin is on, tall enough for the
  // biggest command centre. Resizing a layer surface while it's on screen
  // races the compositor: for a frame Hyprland shows the new buffer
  // stretched to the old size, so the bar and panel visibly jumped on
  // opening, tab switches and folding sections. The shader skips the empty
  // pixels and the input mask keeps them click-through, so the extra room
  // costs next to nothing.
  readonly property real ccMaxAway: root.vertical ? ccWidth
    : (screen ? screen.height - root.barSize - 40 : 1000)
  readonly property real screenAway: screen ? (root.vertical ? screen.width : screen.height) : 1440
  readonly property real skinRoom: Math.max(dripRoom, Math.min(ccMaxAway + 160, screenAway - root.barSize))
  // Room past the bar for the longest drips to hang in full (the shader
  // shrinks falling drops away before this edge): longest drip at this
  // amount, plus bulbs under widgets, plus a stretch for drops to fall /
  // strands to snap / lava globs to sink.
  readonly property real dripRoom: {
    if (root.dripLevel <= 0) return 130
    var amt = root.dripAmount < 0 ? 1.85 : Math.min(root.dripAmount, 2.1)
    var fall = root.dripStyle === "stringy" || root.dripStyle === "lava" || root.dripStyle === "gelatinous" || root.dripStyle === "cava" ? 110 : 60
    return Math.max(130, Math.ceil(60 * amt + 50 + fall))
  }
  readonly property real barLength: root.vertical ? height : width
  property var bulbRects: []
  property var groupRects: []   // left, centre, right section extents
  property real ccCenterX: barLength / 2   // along the bar
  readonly property real ccPanelX: Math.max(16, Math.min(barLength - ccAlong - 16, ccCenterX - ccAlong / 2))
  // this window's top-left on the screen (bottom/right bars sit at the far edge)
  readonly property vector2d screenOrigin: Qt.vector2d(
    root.position === "right" && screen ? screen.width - width : 0,
    root.position === "bottom" && screen ? screen.height - height : 0)
  readonly property vector4d noBulb: Qt.vector4d(0, 0, 0, 0)

  NumberAnimation on ccProgress { id: ccAnim; running: false }
  Connections {
    target: root
    function onCommandCenterOpenChanged() {
      ccAnim.stop()
      ccAnim.to = root.commandCenterOpen ? 1 : 0
      ccAnim.duration = root.commandCenterOpen ? 750 : 420
      ccAnim.easing.type = root.commandCenterOpen ? Easing.OutQuad : Easing.InQuad
      ccAnim.start()
    }
    function onBulbsDirty() { barWindow.scheduleBulbs() }
  }

  property bool bulbsPending: false
  function scheduleBulbs() {
    if (bulbsPending) return
    bulbsPending = true
    Qt.callLater(function() { barWindow.bulbsPending = false; barWindow.updateBulbs() })
  }
  onWidthChanged: scheduleBulbs()
  onHeightChanged: scheduleBulbs()
  // Where each visible widget floats, in window coordinates, so the shader
  // can sag a bulb of ooze beneath it. Recomputed when something on the bar
  // moves (root.bulbsDirty), not every frame.
  function updateBulbs() {
    if (!root.slimeSkin) return
    var out = []
    var h = 28
    var y = Math.round((root.barSize - h) / 2)
    var groups = { left: null, center: null, right: null }
    var slots = root.moduleSlots
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || !slot.visible || slot.width <= 0 || !root.sameWindow(root.slotWindow(slot), barWindow)) continue
      var q = slot.mapToItem(barWindow.contentItem, 0, 0)
      // position and length along the bar (screen-aligned: the window
      // starts at the screen's edge on the bar's axis)
      var at = root.vertical ? q.y : q.x
      var len = root.vertical ? slot.height : slot.width
      var g = groups[slot.region]
      if (slot.region in groups)
        groups[slot.region] = g ? { x0: Math.min(g.x0, at), x1: Math.max(g.x1, at + len) } : { x0: at, x1: at + len }
      if (slot.moduleName === "slime.clock-weather") ccCenterX = at + len / 2
    }
    // Pills follow the layout order, not just what's visible: a joined run
    // is consecutive layout entries linked by pillJoin. Spacers inside a
    // run widen that pill; hidden widgets (the lich when nothing plays) and
    // unjoined spacers break the run so neighbours never bridge across.
    // In pill mode a lone spacer gets a pill of its own; in the other
    // shapes it stays bare goo.
    var joinPills = root.barShape === "pills"
    var sections = ["left", "center", "right"]
    for (var r = 0; r < sections.length; r++) {
      var region = sections[r]
      // this window's slots in the section, grouped by id, along the bar
      var byId = {}
      for (var j = 0; j < slots.length; j++) {
        var sl = slots[j]
        if (!sl || sl.region !== region || !root.sameWindow(root.slotWindow(sl), barWindow)) continue
        ;(byId[sl.moduleName] = byId[sl.moduleName] || []).push(sl)
      }
      for (var id in byId) byId[id].sort(function(a, b) { return root.slotAlong(a) - root.slotAlong(b) })
      var used = {}
      var entries = root.layoutEntries(region)
      var run = null
      function flush() {
        if (run && run.has && out.length < 24) out.push(Qt.vector4d(run.x0, y, run.x1 - run.x0, h))
        run = null
      }
      for (var e = 0; e < entries.length; e++) {
        var entry = entries[e]
        if (!entry) continue
        var eid = root.entryId(entry)
        var n = used[eid] || 0
        used[eid] = n + 1
        var slotHere = byId[eid] ? byId[eid][n] : null
        var shown = !!slotHere && slotHere.visible && slotHere.width > 0
        var noBulb = shown && !!slotHere.activeItem && slotHere.activeItem.slimeNoBulb === true
        if (!shown) { flush(); continue }
        var q2 = slotHere.mapToItem(barWindow.contentItem, 0, 0)
        var at2 = root.vertical ? q2.y : q2.x
        var len2 = root.vertical ? slotHere.height : slotHere.width
        if (!run) run = { x0: at2, x1: at2 + len2, has: false }
        else run.x1 = at2 + len2
        if (!noBulb || joinPills) run.has = true
        else if (!run.has && !(joinPills && entry.pillJoin)) { run = null; continue }  // lone spacer
        if (!(joinPills && entry.pillJoin)) flush()
      }
      flush()
    }
    if (JSON.stringify(out) !== JSON.stringify(bulbRects)) {
      bulbRects = out
      root.sharedBulbRects = out
    }
    var gr = ["left", "center", "right"].map(function(k) {
      var g = groups[k]
      return g ? Qt.vector4d(g.x0, y, g.x1 - g.x0, h) : Qt.vector4d(0, 0, 0, 0)
    })
    if (JSON.stringify(gr) !== JSON.stringify(groupRects)) {
      groupRects = gr
      root.sharedGroupRects = gr
    }
  }

  // safety net for anything that moves a widget without us hearing of it
  Timer { interval: 1000; running: root.slimeSkin; repeat: true; onTriggered: barWindow.updateBulbs() }
  Component.onCompleted: Qt.callLater(updateBulbs)

  mask: root.slimeSkin ? slimeMask : null
  property Region slimeMask: Region { item: barStrip }

  // the goo of the bar strip itself; skinWindow draws everything past it
  SlimeScene {
    root: barWindow.root
    anchors.fill: parent
    visible: root.slimeSkin
    win: barWindow
    origin: barWindow.screenOrigin
  }

  // detritus drifting through the bar, fading out behind widgets
  SlimeDebris {
    visible: root.slimeSkin && root.barDebris && root.material !== "plain" && !root.vertical
    y: 0
    width: barWindow.width
    height: root.barSize
    bar: root
    bitOpacity: 0.7
    room: root.barSize - 6
    avoid: barWindow.bulbRects
    within: root.barShape === "classic" ? [] : (root.barShape === "pills" ? barWindow.bulbRects : barWindow.groupRects)
    bits: {
      var out = [], kinds = (root.material === "sinew" || root.material === "muscle") ? ["eye", "tooth", "sword", "eye", "axe", "tooth", "eye", "skull"]
        : root.material === "bone" ? ["bone", "skull", "tooth", "sword", "bone", "axe", "eye", "mug"]
        : ["eye", "bubble", "frog", "bone", "hat", "bubble", "mug", "tooth", "potion", "sword", "bubble", "axe"]
      var own = ["eye", "bone", "tooth", "bubble"]
      var n = Math.max(1, Math.floor(barWindow.width / 150))
      for (var i = 0; i < n; i++) {
        var h = Math.abs(Math.sin(i * 12.9898) * 43758.5453) % 1
        var kind = kinds[i % kinds.length]
        var size = 10 + Math.round(h * 8)
        if (own.indexOf(kind) === -1) size = Math.round(size * 1.35)   // gear reads better a bit bigger
        out.push({ kind: kind, x: (i + 0.25 + h * 0.5) / n, y: 0.3 + h * 0.4, s: size, sp: 0.3 + h * 0.6 })
      }
      return out
    }
  }

  // with the command centre open, a left click anywhere on the bar closes
  // it (and still reaches whatever widget was clicked)
  MouseArea {
    anchors.fill: parent
    z: 1000
    enabled: root.commandCenterOpen
    acceptedButtons: Qt.LeftButton
    onPressed: mouse => { root.ccClosedByBar = Date.now(); root.commandCenterOpen = false; mouse.accepted = false }
  }

  Item {
    id: barStrip
    // the bar itself (the whole window)
    anchors.fill: parent

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }
  }

  // ---- Skin: drips, the command centre, the egg — in their own window just
  // past the bar, one fixed size (resizing a surface on screen makes it
  // jump for a frame), click-through except where the command centre is.
  // ---- Motion wallpaper: the picked video / gif, over Omarchy's background
  // (its own file, loaded on demand: without QtMultimedia only this is lost)
  Loader {
    id: motionLoader
    active: root.motionWall !== ""
    function load() { if (active) setSource("../ui/SlimeMotionWallpaper.qml", { bar: root, panel: barWindow }) }
    onActiveChanged: load()
    Component.onCompleted: load()
  }

  // ---- Desktop styling: rounded screen corners ----
  // Four small click-through overlays, one per corner, each a black
  // quarter-circle cut-out (like a rounded bezel). Over everything.
  Instantiator {
    model: root.desktopCorners > 0 ? 4 : 0
    delegate: PanelWindow {
      id: cornerWin
      required property int index
      readonly property bool atTop: index < 2
      readonly property bool atLeft: index % 2 === 0
      readonly property int r: root.desktopCorners
      screen: barWindow.screen
      color: "transparent"
      surfaceFormat.opaque: false
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "slime-desktop-corner"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      implicitWidth: r
      implicitHeight: r
      anchors { top: atTop; bottom: !atTop; left: atLeft; right: !atLeft }
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: "black"
          strokeColor: "transparent"
          // the square minus a quarter circle centred on the inner corner
          startX: cornerWin.atLeft ? 0 : cornerWin.r
          startY: cornerWin.atTop ? 0 : cornerWin.r
          PathLine { x: cornerWin.atLeft ? cornerWin.r : 0; y: cornerWin.atTop ? 0 : cornerWin.r }
          PathArc {
            x: cornerWin.atLeft ? 0 : cornerWin.r; y: cornerWin.atTop ? cornerWin.r : 0
            radiusX: cornerWin.r; radiusY: cornerWin.r
            direction: (cornerWin.atLeft === cornerWin.atTop) ? PathArc.Counterclockwise : PathArc.Clockwise
          }
          PathLine { x: cornerWin.atLeft ? 0 : cornerWin.r; y: cornerWin.atTop ? 0 : cornerWin.r }
        }
      }
    }
  }

  // ---- Desktop styling: slime patches in the far corners ----
  // The bar's own scene (its corner-blob shape) drawn on the edge across
  // from the bar, in two small click-through windows, so they follow
  // the bar's material, colour, shading, drips and animation.
  QtObject {
    id: patchWin                   // what SlimeScene reads off a bar window
    readonly property var screen: barWindow.screen
    readonly property real ccProgress: 0
    readonly property real ccPanelX: 0
    readonly property real ccAlong: 0
    readonly property real ccAway: 0
    readonly property real dripRoom: Math.min(barWindow.dripRoom, 170)
    readonly property vector4d noBulb: Qt.vector4d(0, 0, 0, 0)
    readonly property var bulbRects: []
    readonly property bool vert: root.oppositeEdge === "left" || root.oppositeEdge === "right"
    readonly property real len: screen ? (vert ? screen.height : screen.width) : 1920
    readonly property var groupRects: [Qt.vector4d(10, 6, 110, 28), noBulb, Qt.vector4d(len - 120, 6, 110, 28)]
  }
  Instantiator {
    model: root.cornerSlime && root.slimeSkin ? 2 : 0
    delegate: PanelWindow {
      id: patch
      required property int index
      readonly property string edge: root.oppositeEdge
      readonly property bool vert: patchWin.vert
      readonly property bool farEnd: index === 1          // right / bottom end of the edge
      readonly property real along: 200
      readonly property real away: root.barSize + patchWin.dripRoom
      screen: barWindow.screen
      // the dock draws this corner's blob itself when it melts into it
      visible: barWindow.visible && root.patchCorner(index) !== root.dockCorner
      color: "transparent"
      surfaceFormat.opaque: false
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "slime-corner-patch"
      WlrLayershell.layer: root.slimeLayer === "behind" ? WlrLayer.Bottom : WlrLayer.Top
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
      implicitWidth: vert ? away : along
      implicitHeight: vert ? along : away
      anchors {
        top: edge === "top" || (vert && !farEnd)
        bottom: edge === "bottom" || (vert && farEnd)
        left: edge === "left" || (!vert && !farEnd)
        right: edge === "right" || (!vert && farEnd)
      }
      readonly property real sw: screen ? screen.width : 0
      readonly property real sh: screen ? screen.height : 0
      SlimeScene {
        root: barWindow.root
        anchors.fill: parent
        win: patchWin
        orient: ({ top: 0, bottom: 1, left: 2, right: 3 })[patch.edge]
        barShape: 4               // corner blobs, centred on the corners
        eggDrip: Qt.vector4d(0, 0, 0, 0)
        origin: Qt.vector2d(
          patch.edge === "right" ? patch.sw - patch.width : (!patch.vert && patch.farEnd) ? patch.sw - patch.width : 0,
          patch.edge === "bottom" ? patch.sh - patch.height : (patch.vert && patch.farEnd) ? patch.sh - patch.height : 0)
      }
    }
  }

  // ---- Drips: a window exactly as deep as the drips hang, just past the
  // bar. It only changes size when the drip settings change (so no jump),
  // and being small it's cheap to redraw every frame — a full-screen
  // surface redrawn 60 times a second cost ~25% of a core on its own.
  PanelWindow {
    id: dripWindow
    screen: barWindow.screen
    visible: root.slimeSkin && barWindow.visible
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drips"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.layer: barWindow.slimeBehind ? WlrLayer.Bottom : WlrLayer.Top
    mask: Region {}

    readonly property real depth: barWindow.dripRoom
    implicitWidth: root.vertical ? depth : 0
    implicitHeight: root.vertical ? 0 : depth
    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }
    readonly property real edgeMargin: root.barHidden ? -(depth + root.barSize) : root.barSize
    margins {
      top: root.position === "top" ? dripWindow.edgeMargin : 0
      bottom: root.position === "bottom" ? dripWindow.edgeMargin : 0
      left: root.position === "left" ? dripWindow.edgeMargin : 0
      right: root.position === "right" ? dripWindow.edgeMargin : 0
    }
    readonly property vector2d screenOrigin: Qt.vector2d(
      root.position === "left" ? root.barSize : root.position === "right" && screen ? screen.width - root.barSize - width : 0,
      root.position === "top" ? root.barSize : root.position === "bottom" && screen ? screen.height - root.barSize - height : 0)
    function awayToLocal(away) {
      var d = away - root.barSize
      return root.position === "bottom" ? height - d : root.position === "right" ? width - d : d
    }

    SlimeScene {
      root: barWindow.root
      anchors.fill: parent
      win: barWindow
      origin: dripWindow.screenOrigin
    }

    // the easter-egg captive, drawn inside the egg drip's bulb
    SlimeCaptive {
      readonly property var tip: root.eggTip
      visible: tip !== null && root.slimeSkin
      readonly property real bx: tip ? tip.x : 0
      readonly property real by: tip ? dripWindow.awayToLocal(tip.y) : 0
      x: (root.vertical ? by : bx) - width / 2
      y: (root.vertical ? bx : by) - height / 2
      size: 25
      kind: root.eggKind
      time: root.animTime
      ink: root.slimeInk
      paper: root.paperColor
      goo: root.slimeColor
      pal: root.slimePalette
    }
  }

  // ---- SlimeS-Dock ----
  // The bar's own scene with the dock shape (5) on the dock's edge, so it
  // wears the bar's material, colour, shading and drips; the icons, menu and
  // add-apps panel are dock/DockContent.qml. Everything here is in bar space:
  // `along` the edge from the screen's start, `away` from the edge.
  QtObject {
    id: dockWin
    readonly property var screen: barWindow.screen
    readonly property string edge: root.dockEdgeEff
    readonly property bool vert: edge === "left" || edge === "right"
    readonly property real len: screen ? (vert ? screen.height : screen.width) : 1920
    readonly property int s: root.dockIconSize
    readonly property int gap: 10
    readonly property int count: root.dockItems.length + 1          // + the add button
    readonly property real dockLen: count * s + (count + 1) * gap
    readonly property bool mergeStart: root.dockCorner !== "" && root.dockAlign === "start"
    readonly property bool mergeEnd: root.dockCorner !== "" && root.dockAlign === "end"
    // on a side edge, the end that meets the bar ("start" / "end" / ""): a
    // dock pushed to that end sits just past the bar and melts into it
    readonly property string barEnd: vert ? (root.position === "top" ? "start" : root.position === "bottom" ? "end" : "")
      : (root.position === "left" ? "start" : root.position === "right" ? "end" : "")
    readonly property bool barStart: barEnd === "start" && root.dockAlign === "start"
    readonly property bool barFinish: barEnd === "end" && root.dockAlign === "end"
    readonly property real bs: root.barSize
    readonly property real barLen: screen ? (root.vertical ? screen.height : screen.width) : 1920
    readonly property real lo: barStart ? bs + 10 : 10
    readonly property real hi: barFinish ? len - bs - 10 : len - 10
    readonly property real a0: root.dockAlign === "start" ? (barStart ? bs + 16 : mergeStart ? 44 : 24)
      : root.dockAlign === "end" ? len - dockLen - (barFinish ? bs + 16 : mergeEnd ? 44 : 24)
      : Math.round((len - dockLen) / 2)
    readonly property real thick: s + 20
    readonly property real panelW: 460
    readonly property real panelH: 400
    readonly property real panelX: Math.max(lo, Math.min(hi - panelW, a0 + dockLen / 2 - panelW / 2))
    readonly property real dripRoom: Math.min(barWindow.dripRoom, 170)
    // the right-click menu: a smaller drip hanging from its icon
    readonly property real menuW: 230
    readonly property real menuH: 166
    readonly property real menuX: Math.max(lo, Math.min(hi - menuW,
      a0 + gap + s / 2 + Math.max(0, dockContent.menuFor) * (s + gap) - menuW / 2))
    // the window along [w0, w1], always deep enough for the panel: it never
    // resizes as a menu or panel opens and shuts (a resize made the dock jump)
    // (room for a menu hanging from the first or last icon, too)
    // (melting into the bar: from a few px inside the bar, to cover its outline there)
    readonly property real w0: mergeStart ? 0 : barStart ? bs - 3 : Math.max(0, Math.min(a0 - menuW / 2, panelX) - 70)
    readonly property real w1: mergeEnd ? len : barFinish ? len - bs + 3 : Math.min(len, Math.max(a0 + dockLen + menuW / 2, panelX + panelW) + 70)
    readonly property real depth: thick + dripRoom + panelH + 40
    property real panelProgress: 0
    readonly property bool menuBlob: dockContent.blob === "menu"
    readonly property real ccProgress: panelProgress
    readonly property real ccPanelX: menuBlob ? menuX : panelX
    readonly property real ccAlong: menuBlob ? menuW : panelW
    readonly property real ccAway: menuBlob ? menuH : panelH
    readonly property vector4d noBulb: Qt.vector4d(0, 0, 0, 0)
    readonly property var bulbRects: []
    // ends: x 0 a corner blob, x 1 the bar (y = its thickness) to melt into
    readonly property var groupRects: [mergeStart ? Qt.vector4d(0, 0, 1, 1) : barStart ? Qt.vector4d(1, bs, 1, 1) : noBulb,
      Qt.vector4d(a0, 4, dockLen, s + 8), mergeEnd ? Qt.vector4d(0, 0, 1, 1) : barFinish ? Qt.vector4d(1, bs, 1, 1) : noBulb]
  }
  PanelWindow {
    id: dockWindow
    screen: barWindow.screen
    visible: root.dockEnabled && root.slimeSkin && barWindow.visible
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "slime-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: dockContent.panelOpen || dockContent.menuIndex >= 0 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // shown for good, it keeps windows off its strip; hidden, it floats over them
    exclusionMode: root.dockAutoHide ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: root.dockAutoHide ? 0 : dockWin.thick
    readonly property string edge: dockWin.edge
    readonly property bool vert: dockWin.vert
    implicitWidth: vert ? dockWin.depth : dockWin.w1 - dockWin.w0
    implicitHeight: vert ? dockWin.w1 - dockWin.w0 : dockWin.depth
    anchors {
      top: edge === "top" || vert
      bottom: edge === "bottom"
      left: edge === "left" || !vert
      right: edge === "right"
    }
    // the bar's reserved strip pushes a side dock's window along; take it back off
    readonly property real barPush: vert && root.position === "top" ? root.barSize : !vert && root.position === "left" ? root.barSize : 0
    margins { left: vert ? 0 : dockWin.w0 - barPush; top: vert ? dockWin.w0 - barPush : 0 }
    mask: Region { item: dockContent.hotArea }
    readonly property real sw: screen ? screen.width : 0
    readonly property real sh: screen ? screen.height : 0
    SlimeScene {
      root: barWindow.root
      anchors.fill: parent
      win: dockWin
      // tucked away: the drips draw back in as it slides off, and once it's
      // gone nothing is drawn at all
      visible: dockContent.reveal > 0.01
      dripAmount: root.dripLevel * dockContent.reveal
      // melting into the bar: the gradient carries on from the bar's at the join
      dockBracket: Qt.vector4d(0, 0, dockWin.barStart || dockWin.barFinish
        ? ((dockWindow.edge === "left" || dockWindow.edge === "top") ? 30 : dockWin.barLen - 30) - (dockWin.barStart ? dockWin.bs : dockWin.len - dockWin.bs)
        : 0, 0)
      orient: ({ top: 0, bottom: 1, left: 2, right: 3 })[dockWindow.edge]
      barShape: 5
      barHeight: dockWin.thick
      eggDrip: Qt.vector4d(0, 0, 0, 0)
      dripExtra: Qt.vector4d(root.dripExtraVec.x, root.dripExtraVec.y, dockWin.depth, dockWin.thick + dockWin.dripRoom)
      // tucked away: the whole scene slides out past the edge
      readonly property real off: dockContent.hideOffset
      origin: Qt.vector2d(
        (dockWindow.edge === "right" ? dockWindow.sw - dockWindow.width - off : dockWindow.edge === "left" ? off : dockWin.w0),
        (dockWindow.edge === "bottom" ? dockWindow.sh - dockWindow.height - off : dockWindow.edge === "top" ? off : dockWin.w0))
    }
    DockContent {
      id: dockContent
      anchors.fill: parent
      bar: root
      geo: dockWin
      win: dockWindow
    }
  }

  // ---- Command centre: full-size (fixed) window, mapped only while the
  // command centre is out; it draws the panel's goo past the drip band.
  PanelWindow {
    id: skinWindow
    screen: barWindow.screen
    visible: root.slimeSkin && barWindow.visible && barWindow.ccShown
    color: "transparent"
    surfaceFormat.opaque: false
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-skin"
    // the keyboard while it's open, so every tab can be driven from the
    // keyboard straight away (Esc closes it; clicking off it does too)
    WlrLayershell.keyboardFocus: root.commandCenterOpen || root.hoverKeysWindow === skinWindow ? WlrKeyboardFocus.Exclusive
      : barWindow.ccShown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // only mapped while the command centre is out, which always shows
    // above windows (even when the slime is drawn behind them). Overlay,
    // not Top: the drip window is raised to Top at the same moment and
    // would otherwise stack over the command centre's content.
    WlrLayershell.layer: WlrLayer.Overlay

    readonly property real depth: barWindow.skinRoom
    implicitWidth: root.vertical ? depth : 0
    implicitHeight: root.vertical ? 0 : depth
    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }
    // right past the bar (and parked off-screen with it when it hides)
    readonly property real edgeMargin: root.barHidden ? -(depth + root.barSize) : root.barSize
    margins {
      top: root.position === "top" ? skinWindow.edgeMargin : 0
      bottom: root.position === "bottom" ? skinWindow.edgeMargin : 0
      left: root.position === "left" ? skinWindow.edgeMargin : 0
      right: root.position === "right" ? skinWindow.edgeMargin : 0
    }
    // this window's top-left on the screen
    readonly property vector2d screenOrigin: Qt.vector2d(
      root.position === "left" ? root.barSize : root.position === "right" && screen ? screen.width - root.barSize - width : 0,
      root.position === "top" ? root.barSize : root.position === "bottom" && screen ? screen.height - root.barSize - height : 0)
    // bar space (distance from the bar's screen edge) -> this window
    function awayToLocal(away) {
      var d = away - root.barSize
      return root.position === "bottom" ? height - d : root.position === "right" ? width - d : d
    }

    // Click-through, except the command centre while it's open. While it's
    // open the whole window takes clicks, and a click anywhere off the
    // panel closes it (Hyprland's focus grab won't take in this second
    // window, so the grab can't do this: it would swallow the panel's own
    // input). The bar window above still works as normal.
    mask: root.commandCenterOpen ? null : ccRegion
    property Region ccRegion: Region { item: ccHit }
    MouseArea {
      anchors.fill: parent
      enabled: root.commandCenterOpen
      acceptedButtons: Qt.AllButtons
      onPressed: mouse => {
        var p = mapToItem(ccHit, mouse.x, mouse.y)
        if (p.x < 0 || p.y < 0 || p.x > ccHit.width || p.y > ccHit.height) root.commandCenterOpen = false
        else mouse.accepted = false
      }
    }

    Item {
      id: ccHit
      readonly property real away: root.commandCenterOpen ? barWindow.ccAway : 0
      x: root.vertical ? (root.position === "left" ? 0 : skinWindow.width - away) : barWindow.ccPanelX
      y: root.vertical ? barWindow.ccPanelX : (root.position === "bottom" ? skinWindow.height - away : 0)
      width: root.vertical ? away : barWindow.ccAlong
      height: root.vertical ? barWindow.ccAlong : away
    }

    // the command centre's goo, past the drip band (dripWindow draws that)
    // A fullscreen window covers the Top layer, drip window included: then
    // this (Overlay) window draws the whole panel, from the bar's edge down
    readonly property bool dripsCovered: {
      var m = Hyprland.monitorFor(screen)
      return !!(m && m.activeWorkspace && m.activeWorkspace.hasFullscreen)
    }
    readonly property real dripDepth: dripsCovered ? 0 : Math.min(barWindow.dripRoom, depth)
    SlimeScene {
      root: barWindow.root
      id: ccScene
      win: barWindow
      // past the drip band, as deep as the panel plus the drips under it
      readonly property real reach: Math.min(skinWindow.depth, barWindow.ccAway + 200)
      readonly property real extent: Math.max(0, reach - skinWindow.dripDepth)
      readonly property real along0: Math.max(0, barWindow.ccPanelX - 90)
      readonly property real alongLen: Math.min(barWindow.barLength - along0, barWindow.ccAlong + 180)
      x: root.vertical ? (root.position === "left" ? skinWindow.dripDepth : skinWindow.width - reach) : along0
      y: root.vertical ? along0 : (root.position === "bottom" ? skinWindow.height - reach : skinWindow.dripDepth)
      width: root.vertical ? extent : alongLen
      height: root.vertical ? alongLen : extent
      origin: Qt.vector2d(skinWindow.screenOrigin.x + x, skinWindow.screenOrigin.y + y)
    }

    // debris adrift in the command centre's ooze, behind its content
    SlimePanelDebris {
      x: commandCenter.x - 12 * barWindow.ccScale
      y: commandCenter.y - 8 * barWindow.ccScale
      width: (commandCenter.width + 24) * barWindow.ccScale
      height: (commandCenter.implicitHeight + 16) * barWindow.ccScale
      bar: root
      active: root.commandCenterOpen
      opacity: commandCenter.opacity
    }

    // ---- Command centre (fades in once the ooze has settled) ----
    CommandCenter {
      id: commandCenter
      // laid out landscape on every edge; sits just off the bar
      x: root.position === "left" ? 20 * barWindow.ccScale
        : root.position === "right" ? skinWindow.width - (20 + width) * barWindow.ccScale
        : barWindow.ccPanelX + 24 * barWindow.ccScale
      y: root.position === "bottom" ? skinWindow.height - (20 + implicitHeight) * barWindow.ccScale
        : root.vertical ? barWindow.ccPanelX + 22 * barWindow.ccScale
        : 20 * barWindow.ccScale
      width: root.commandCenterWidth - 48
      scale: barWindow.ccScale
      transformOrigin: Item.TopLeft
      bar: root
      maxHeight: (barWindow.ccMaxHeight - 44) / barWindow.ccScale
      shown: barWindow.ccShown
      opacity: Math.max(0, (barWindow.ccProgress - 0.8) / 0.2)
      visible: root.slimeSkin && opacity > 0
      onImplicitHeightChanged: if (shown) {
        root.commandCenterHeightTarget = Math.max(160, (implicitHeight + 44) * barWindow.ccScale)
        root.commandCenterHeight = root.commandCenterHeightTarget
      }
    }
  }


  // ---- Slime-Tasks pop-out: the Tasks tab in a floating drip panel ----
  QtObject {
    id: tasksLook                     // what the Tasks tab reads off the command centre
    readonly property var bar: root
    readonly property color ink: root.slimeInk
    readonly property color slime: root.slimeColor
    readonly property color paper: root.paperColor
    readonly property string font: root.fontFamily
    readonly property string displayFont: root.displayFontFamily
    readonly property int displayWeight: root.displayWeight
    readonly property color wash: Qt.rgba(1, 1, 1, 0.45)
  }
  QtObject { id: tasksPopOwner; function close() { root.tasksPopOpen = false } }
  SlimeKeyboardPanel {
    id: tasksPop
    anchorItem: barStrip
    bar: root
    owner: tasksPopOwner
    floating: true
    open: root.tasksPopOpen && root.slimeSkin && !!barWindow.screen && !!Hyprland.focusedMonitor
      && Hyprland.focusedMonitor.name === barWindow.screen.name
    contentWidth: Math.min(1040, barWindow.screen ? barWindow.screen.width - 120 : 1040)
    contentHeight: Math.min(700, barWindow.screen ? barWindow.screen.height - 160 : 700)
    Loader {
      anchors.fill: parent
      active: tasksPop.open || tasksPop.visible
      sourceComponent: TasksTab {
        cc: tasksLook
        closeRequest: function() { root.tasksPopOpen = false }
        Component.onCompleted: { tasksPop.focusTarget = this; forceActiveFocus() }
      }
      onLoaded: { item.width = Qt.binding(function() { return width }); item.height = Qt.binding(function() { return height }) }
    }
  }

  PopupWindow {
    id: tooltipWindow

    visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
    color: "transparent"
    implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
    implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

    anchor {
      id: tooltipAnchor
      window: barWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var target = root.tooltipTarget
        if (!root.targetBelongsToWindow(target, barWindow)) return

        var popupWidth = tooltipWindow.implicitWidth
        var popupHeight = tooltipWindow.implicitHeight
        var localX = target.width / 2 - popupWidth / 2
        var localY = target.height + 6

        if (root.position === "bottom") {
          localY = -popupHeight - 6
        } else if (root.position === "left") {
          localX = target.width + 6
          localY = target.height / 2 - popupHeight / 2
        } else if (root.position === "right") {
          localX = -popupWidth - 6
          localY = target.height / 2 - popupHeight / 2
        }

        var point = barWindow.contentItem.mapFromItem(target, localX, localY)
        tooltipAnchor.rect.x = Math.round(point.x)
        tooltipAnchor.rect.y = Math.round(point.y)
      }
    }

    BorderSurface {
      id: tooltipBubble
      implicitWidth: tooltipLabel.implicitWidth + 20
      implicitHeight: tooltipLabel.implicitHeight + 14
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius

      Text {
        id: tooltipLabel
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.tooltipText
        color: Color.tooltip.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  Component {
    id: horizontalBar

    Item {
      id: hBar
      anchors.fill: parent
      // blob: the side sections huddle up against the centre, a gap apart
      readonly property bool huddle: root.barShape === "blob"
      readonly property vector4d mid: barWindow.groupRects[1] || Qt.vector4d(0, 0, 0, 0)
      readonly property real midStart: mid.z > 0 ? mid.x : width / 2
      readonly property real midEnd: mid.z > 0 ? mid.x + mid.z : width / 2
      readonly property real gap: 30

      // the centre section slides aside when a side section grows into it
      // (a tray or indicators opening on a crowded bar) instead of overlapping
      readonly property real gapMin: 6
      readonly property real cStart: mid.z > 0 ? mid.x - centerShift : width / 2
      readonly property real cEnd: mid.z > 0 ? mid.x + mid.z - centerShift : width / 2
      readonly property real pushRight: Math.max(0, hLeft.x + hLeft.width + gapMin - cStart)
      readonly property real pushLeft: Math.max(0, cEnd + gapMin - hRight.x)
      readonly property real centerShift: huddle ? 0 : pushRight - pushLeft
      CenterModules { root: barWindow.root; anchors.fill: parent; transform: Translate { x: hBar.centerShift } }

      LeftModules {
        root: barWindow.root
        id: hLeft
        x: hBar.huddle ? Math.max(Style.space(8), hBar.midStart - hBar.gap - width) : Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      RightModules {
        root: barWindow.root
        id: hRight
        x: hBar.huddle ? Math.min(parent.width - width - Style.space(8), hBar.midEnd + hBar.gap) : parent.width - width - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  Component {
    id: verticalBar

    Item {
      id: vBar
      anchors.fill: parent
      readonly property bool huddle: root.barShape === "blob"
      readonly property vector4d mid: barWindow.groupRects[1] || Qt.vector4d(0, 0, 0, 0)
      readonly property real midStart: mid.z > 0 ? mid.x : height / 2
      readonly property real midEnd: mid.z > 0 ? mid.x + mid.z : height / 2
      readonly property real gap: 30

      readonly property real gapMin: 6
      readonly property real cStart: mid.z > 0 ? mid.x - centerShift : height / 2
      readonly property real cEnd: mid.z > 0 ? mid.x + mid.z - centerShift : height / 2
      readonly property real pushDown: Math.max(0, vLeft.y + vLeft.height + gapMin - cStart)
      readonly property real pushUp: Math.max(0, cEnd + gapMin - vRight.y)
      readonly property real centerShift: huddle ? 0 : pushDown - pushUp
      CenterModules { root: barWindow.root; anchors.fill: parent; transform: Translate { y: vBar.centerShift } }

      LeftModules {
        root: barWindow.root
        id: vLeft
        y: vBar.huddle ? Math.max(Style.space(8), vBar.midStart - vBar.gap - height) : Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
      }

      RightModules {
        root: barWindow.root
        id: vRight
        y: vBar.huddle ? Math.min(parent.height - height - Style.space(8), vBar.midEnd + vBar.gap) : parent.height - height - Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }
  }
}
