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
import "BarModel.js" as BarModel
import "SlimeHub.js" as SlimeHub
import "commandcenter"
import "ui"
import "dock"
import "bar"

// Slime Shell bar: a clone of the Omarchy bar engine (layout, widget slots,
// drag/reorder, popouts, IPC all unchanged) with the slime skin painted by a
// shader behind the widgets. Widgets float in the ooze, each sagging a bulb of
// slime beneath it, and the slime.clock-weather widget drips the command
// centre open. The skin draws on a top bar; other positions fall back to the
// stock Omarchy look.
Item {
  id: root
  // handed to the bar windows in bar/ (`root: root` there would name their own property)
  readonly property var barRoot: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  // Read-only registry view for third-party full bars; the built-in bar does
  // not otherwise need it, but declaring it keeps clone construction atomic.
  property var pluginRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  // Slime Shell fonts. Each slime style pairs a decorative *display* face,
  // used only for big text (clocks, temperatures, headings), with Sniglet, a
  // rounded face that stays readable at small sizes, for everything else.
  //   system  fontconfig monospace for both
  //   chewy   blobby: Chewy display
  //   wetpaint drippy: Rubik Wet Paint display
  //   bubble  bubble letters: Rubik Bubbles display
  //   runic   fantasy runes: MedievalSharp display
  //   styro / nippo / array: Fontshare's Styro, Nippo and Array display faces.
  //   Their licence doesn't allow bundling them, so they're used when
  //   installed on the system (free from fontshare.com) and fall back to
  //   the rounded face otherwise.
  property string fontStyle: "system"
  readonly property var systemFaces: ({ styro: "Styro", nippo: "Nippo", array: "Array" })
  function hasFamily(name) { return Qt.fontFamilies().indexOf(name) >= 0 }
  readonly property var installedFaces: Object.keys(systemFaces).filter(function(k) { return hasFamily(systemFaces[k]) })
  readonly property bool slimeFonts: slimeSkin && fontStyle !== "system" && snigletFont.status === FontLoader.Ready
  property string fontFamily: slimeFonts ? snigletFont.name : Style.font.family
  readonly property string displayFontFamily: {
    if (!slimeFonts) return fontFamily
    if (fontStyle in systemFaces) return hasFamily(systemFaces[fontStyle]) ? systemFaces[fontStyle] : fontFamily
    var loader = ({ chewy: chewyFont, wetpaint: wetPaintFont, bubble: bubbleFont, runic: runicFont })[fontStyle] || null
    return loader && loader.status === FontLoader.Ready ? loader.name : fontFamily
  }
  // The bundled display faces have a single weight (asking for bold makes Qt
  // smear them); the Fontshare families come in real weights.
  readonly property int displayWeight: !slimeFonts ? Font.Black : (fontStyle in systemFaces ? Font.Bold : Font.Normal)
  FontLoader { id: snigletFont; source: Qt.resolvedUrl("fonts/Sniglet-Regular.ttf") }
  FontLoader { id: snigletBoldFont; source: Qt.resolvedUrl("fonts/Sniglet-ExtraBold.ttf") }
  FontLoader { id: chewyFont; source: Qt.resolvedUrl("fonts/Chewy-Regular.ttf") }
  FontLoader { id: wetPaintFont; source: Qt.resolvedUrl("fonts/RubikWetPaint-Regular.ttf") }
  FontLoader { id: bubbleFont; source: Qt.resolvedUrl("fonts/RubikBubbles-Regular.ttf") }
  FontLoader { id: runicFont; source: Qt.resolvedUrl("fonts/MedievalSharp-Regular.ttf") }
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: slimeSkin ? slimeInk : Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  // Set via the omarchy.bar IPC target's setForegroundOverride(hex). Lets a
  // plugin that paints its own chrome behind the transparent bar (rice-bar,
  // et al.) supply a foreground color matched to that chrome instead of the
  // wallpaper-sampled default from omarchy-bar-text-color, which has no way
  // to know what a third-party plugin drew. Empty string = no override.
  property string foregroundOverride: ""
  property color foreground: themeForeground
  property color barForeground: slimeSkin ? slimeInk : (useTransparentForeground ? transparentForeground : themeForeground)
  property bool foregroundAnimationEnabled: true
  property color background: Color.bar.background
  property color urgent: slimeSkin ? paperColor : Color.bar.active

  // ---- Slime skin ----------------------------------------------------------
  readonly property bool slimeSkin: true
  // Bar edge for the shader: 0 top, 1 bottom, 2 left, 3 right.
  readonly property real orientId: ["top", "bottom", "left", "right"].indexOf(position)
  readonly property int slimeBarSize: 40
  readonly property real commandCenterWidth: 860
  // Follows the open tab's content (set by the CommandCenter), animated so
  // the ooze stretches and settles when switching tabs.
  property real commandCenterHeight: 480
  // where commandCenterHeight is heading (the animation's end value)
  property real commandCenterHeightTarget: 480
  Behavior on commandCenterHeight { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
  property string ccTab: "home"
  // Command centre sections folded open/closed, by title (CcSection).
  property var ccSections: ({})

  // Full theme palette from colors.toml (Color only exposes a few roles).
  // (not "palette": every Item has one of its own)
  property var slimePalette: ({})
  function parsePalette(raw) {
    var out = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6,8})"/)
      if (m) out[m[1]] = m[2]
    }
    slimePalette = out
  }
  FileView {
    id: paletteFile
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parsePalette(text())
  }
  // Theme swaps arrive through the Color singleton; re-read the palette then.
  Connections {
    target: Color
    function onAccentChanged() { paletteFile.reload() }
    function onBackgroundChanged() { paletteFile.reload() }
  }

  // Widgets are inked in the theme's darkest tone so they read on the ooze;
  // active states use its lightest ("paper") tone.
  readonly property color slimeInk: slimePalette.background || Color.background
  property string slimeRole: "accent"
  readonly property color slimeColor: slimePalette[slimeRole] || Color.accent
  readonly property color paperColor: {
    var fg = Qt.color(slimePalette.foreground || Color.foreground)
    var bg = Qt.color(slimePalette.background || Color.background)
    return fg.hslLightness >= bg.hslLightness ? fg : bg
  }
  // "auto" picks the palette colour whose hue sits roughly 100° away from the
  // slime colour, for an anime-style complementary sweep.
  property string gradientRole: "auto"
  readonly property var hueRoles: ["red", "yellow", "green", "cyan", "blue", "magenta",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]
  readonly property color slimeColor2: {
    if (gradientRole === "none") return slimeColor
    if (gradientRole !== "auto") return slimePalette[gradientRole] || slimeColor
    var h1 = slimeColor.hsvHue
    if (h1 < 0) return slimePalette.accent || slimeColor
    var best = slimeColor, bestScore = 1e9
    for (var i = 0; i < hueRoles.length; i++) {
      if (!slimePalette[hueRoles[i]]) continue
      var c = Qt.color(slimePalette[hueRoles[i]])
      if (c.hsvHue < 0 || c.hsvSaturation < 0.35) continue
      var diff = Math.abs(c.hsvHue - h1) * 360
      if (diff > 180) diff = 360 - diff
      var score = Math.abs(diff - 100)
      if (score < bestScore) { bestScore = score; best = c }
    }
    return best
  }

  // Slime monsters (workspaces, launcher): bodies in the theme's paper tone
  // tinted with the gradient partner, so they pop off the ooze they float in.
  readonly property color monsterBody: Qt.tint(paperColor, Qt.rgba(slimeColor2.r, slimeColor2.g, slimeColor2.b, 0.3))
  readonly property color monsterBlush: slimePalette.bright_magenta || slimePalette.magenta || "#ff6fa8"
  // How the slime icons (workspaces, agents, launcher) are coloured:
  //   paper     pale paper tinted with the gradient partner (default: pops off the ooze)
  //   theme     the theme's own colours; workspace slimes each take a different hue
  //   gradient  shaded top to bottom like the bar: slime colour into its partner
  property string monsterColor: "paper"
  // ---- Desktop styling ----
  property int desktopCorners: 0            // rounded screen corners: radius in px, 0 = off
  property bool cornerSlime: false          // slime patches in the corners across from the bar
  property bool ccKeyboard: true            // command centre keyboard navigation
  // ---- wallpapers switching by themselves (options on the Wallpapers tab) ----
  property int wallAuto: 0                  // minutes between switches, 0 = off
  property bool wallShuffle: false          // random, or in order
  property string wallPool: "all"           // theme | mine | all
  property string wallSort: "name"          // the tab's order: name | type
  Timer {
    interval: Math.max(1, root.wallAuto) * 60000
    repeat: true
    running: root.wallAuto > 0
    onTriggered: root.nextWallpaper()
  }
  function nextWallpaper() {
    if (wallLister.running) return
    var home = Quickshell.env("HOME")
    var dirs = wallPool === "theme" ? [home + "/.local/state/omarchy/current/theme/backgrounds"]
      : wallPool === "mine" ? [home + "/Pictures/SlimeS-Wallpapers"]
      : [home + "/.local/state/omarchy/current/theme/backgrounds", home + "/Pictures/SlimeS-Wallpapers"]
    wallLister.command = ["bash", "-c", "for d; do find -L \"$d\" -maxdepth 1 -type f -iregex '.*\\.\\(png\\|jpe?g\\|webp\\|gif\\|mp4\\|webm\\|mkv\\|mov\\|m4v\\)' 2>/dev/null | sort; done; " +
      "echo \"@current $(readlink -f \"$HOME/.local/state/omarchy/current/background\")\"", "_"].concat(dirs)
    wallLister.running = true
  }
  Process {
    id: wallLister
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n").filter(function(l) { return l !== "" })
        var cur = "", files = []
        lines.forEach(function(l) { if (l.indexOf("@current ") === 0) cur = l.slice(9); else files.push(l) })
        if (root.motionWall !== "") cur = root.motionWall
        if (!files.length) return
        var at = files.indexOf(cur), pick
        if (root.wallShuffle && files.length > 1) { do { pick = Math.floor(Math.random() * files.length) } while (pick === at) }
        else pick = (at + 1) % files.length
        var path = files[pick]
        if (root.isMotion(path)) root.setMotionWall(path)
        else { root.clearMotionWall(); Quickshell.execDetached(["omarchy-theme-bg-set", path]) }
      }
    }
  }

  // ---- motion wallpapers (videos / gifs from ~/Pictures/SlimeS-Wallpapers) ----
  // Played muted and looping on a background layer over Omarchy's own; a
  // still frame (the poster) is set as the real background so the lock
  // screen and anything else reading it match. Picking any other background
  // (here, a theme change, Next, another picker) swaps the poster out, and
  // the motion stops.
  property string motionWall: ""
  readonly property bool motionIsGif: /\.gif$/i.test(motionWall)
  readonly property bool motionPaused: allFullscreen || slimeIdle.isIdle
  readonly property string posterDir: Quickshell.env("HOME") + "/.cache/slime-shell/wallpaper-posters"
  function isMotion(path) { return /\.(mp4|webm|mkv|mov|m4v|gif)$/i.test(String(path)) }
  function posterFor(path) {
    var b = String(path).split("/").pop().replace(/[^A-Za-z0-9._-]+/g, "-")
    return posterDir + "/" + b + ".jpg"
  }
  // the poster is made first (if it isn't cached), then set as the background
  function setMotionWall(path) {
    // absolute paths only: ImageMagick reads "msl:", "ephemeral:"... prefixes
    // as coders, not files
    if (String(path).charAt(0) !== "/") return
    motionStarter.command = ["bash", "-c",
      "mkdir -p \"$(dirname \"$2\")\"; [ -s \"$2\" ] || { case \"$1\" in " +
      "*.gif|*.GIF) magick \"$1[0]\" -resize 1920x \"$2\" ;; " +
      "*) ffmpeg -y -loglevel error -ss 1 -i \"$1\" -frames:v 1 -vf scale=1920:-2 \"$2\" ;; esac; }; " +
      "[ -s \"$2\" ] && omarchy-theme-bg-set \"$2\"", "_", path, posterFor(path)]
    motionPending = path
    motionStarter.running = true
  }
  property string motionPending: ""
  Process {
    id: motionStarter
    onExited: code => { if (code === 0) root.motionWall = root.motionPending; root.motionPending = "" }
  }
  function clearMotionWall() { motionWall = "" }
  // After a shell restart, other plugins may put "their" background back
  // (Theme Manager re-applies the wallpaper it remembers for the theme, then
  // checks it again a few seconds later). So the saved motion wallpaper keeps
  // playing over it, the background is left to settle (no change for 5 s, or
  // 25 s at most), and then the poster is set again.
  QtObject {
    id: motionSettle
    property bool active: false
    property string last: ""
    property int stable: 0
    property int waited: 0
    function begin() { active = true; last = ""; stable = 0; waited = 0; motionSettleTimer.restart() }
    function probe(out) {
      var lines = out.split("\n"), cur = lines[0] || "", exists = lines[1] === "yes"
      waited++
      if (cur === last) stable++
      else { stable = 0; last = cur }
      if (!exists) { motionSettleTimer.stop(); active = false; root.clearMotionWall(); return }
      if (stable < 5 && waited < 25) return
      motionSettleTimer.stop()
      active = false
      if (root.motionWall !== "" && cur !== root.posterFor(root.motionWall)) root.setMotionWall(root.motionWall)
    }
  }
  Timer {
    id: motionSettleTimer
    interval: 1000; repeat: true
    onTriggered: if (!motionSettleProbe.running) motionSettleProbe.running = true
  }
  Process {
    id: motionSettleProbe
    command: ["bash", "-c", "readlink -f \"$HOME/.local/state/omarchy/current/background\"; [ -f \"$1\" ] && echo yes || echo no", "_", root.motionWall]
    stdout: StdioCollector { onStreamFinished: motionSettle.probe(text) }
  }
  // the background moved on without us: stop
  Timer {
    interval: 3000; repeat: true
    running: root.motionWall !== "" && !motionSettle.active
    onTriggered: motionProbe.running = true
  }
  Process {
    id: motionProbe
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: if (root.motionWall !== "" && !motionSettle.active && text.trim() !== "" && text.trim() !== root.posterFor(root.motionWall)) root.motionWall = ""
    }
  }

  // ---- SlimeS-Dock: a dock of apps / folders on a free screen edge ----
  property bool dockEnabled: false
  property string dockEdge: "bottom"
  property string dockAlign: "center"       // start / center / end along its edge
  property bool dockAutoHide: false         // tucked away until hovered
  property int dockIconSize: 44
  // never on the bar's edge: moving the bar onto the dock's edge sends the dock across
  readonly property string dockEdgeEff: dockEdge === position ? oppositeEdge : dockEdge
  // (moving the bar onto the dock's edge: see onPositionChanged further down)
  property var dockItems: []                // {kind: "app", id} | {kind: "folder" | "file", path}
  property int dockPanelRequest: 0          // bumped to open the add-apps panel (Settings, IPC)
  function dockKey(it) { return it.kind === "app" ? "app:" + it.id : it.kind + ":" + it.path }
  function dockHas(it) { var k = dockKey(it); return dockItems.some(function(x) { return dockKey(x) === k }) }
  function dockAdd(it) { if (!it || dockHas(it)) return; dockItems = dockItems.concat([it]); dockSave() }
  function dockRemove(i) { var a = dockItems.slice(); a.splice(i, 1); dockItems = a; dockSave() }
  function dockRemoveItem(it) { var k = dockKey(it); dockItems = dockItems.filter(function(x) { return dockKey(x) !== k }); dockSave() }
  function dockMove(i, dir) {
    var j = i + dir
    if (j < 0 || j >= dockItems.length) return
    var a = dockItems.slice(), t = a[i]; a[i] = a[j]; a[j] = t
    dockItems = a; dockSave()
  }
  function dockSave() { dockFile.setText(JSON.stringify({ items: dockItems }, null, 2) + "\n") }
  FileView {
    id: dockFile
    path: Quickshell.env("HOME") + "/.config/omarchy/slime-shell/dock.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.dockItems = JSON.parse(text()).items || [] } catch (e) {} }
  }
  // the screen corners the far-corner slime patches sit in, and the one the
  // dock melts into when it's pushed to that end of its edge ("" none)
  function patchCorner(i) {
    var e = oppositeEdge, v = e === "left" || e === "right"
    return v ? (i ? "bottom" : "top") + "-" + e : e + "-" + (i ? "right" : "left")
  }
  // the dock melting into the bar at one of its ends: how far along the bar
  // (from its start, x / its end, y) the bar leaves off its drips there
  readonly property vector4d dockBracketVec: {
    var v = dockEdgeEff === "left" || dockEdgeEff === "right"
    if (!dockEnabled || !slimeSkin || v === vertical) return Qt.vector4d(0, 0, 0, 0)
    var barEnd = v ? (position === "top" ? "start" : position === "bottom" ? "end" : "")
                   : (position === "left" ? "start" : position === "right" ? "end" : "")
    if (barEnd === "" || dockAlign !== barEnd) return Qt.vector4d(0, 0, 0, 0)
    var reach = dockIconSize + 20 + 70
    var atStart = dockEdgeEff === "left" || dockEdgeEff === "top"
    return Qt.vector4d(atStart ? reach : 0, atStart ? 0 : reach, 0, 0)
  }
  readonly property string dockCorner: {
    if (!dockEnabled || !cornerSlime || dockAlign === "center") return ""
    var e = dockEdgeEff, v = e === "left" || e === "right", first = dockAlign === "start"
    var c = v ? (first ? "top" : "bottom") + "-" + e : e + "-" + (first ? "left" : "right")
    return c === patchCorner(0) || c === patchCorner(1) ? c : ""
  }

  // cava drip style (Settings → Motion, shown while it's picked)
  property string cavaStyle: "drips"        // drips (bars) | ripple (the goo's wall swells)
  property int cavaBars: 80                 // bars across the whole bar
  property bool cavaMirror: false           // bass in the middle, treble out to both ends
  property int cavaSens: 0                  // 0 auto, else cava's sensitivity %
  property real cavaReach: 1.0              // how far the loudest bar hangs
  property real cavaWidth: 1.0              // bar thickness
  property int cavaSmooth: 55               // cava's noise_reduction
  property real ccFontScale: 1.0            // command centre text size (0.8 – 1.4)
  property bool ccSidebarCollapsed: false   // command centre's tab sidebar folded to icons
  readonly property var monsterHues: ["bright_green", "bright_cyan", "bright_magenta", "bright_yellow", "bright_blue", "bright_red",
    "green", "cyan", "magenta", "yellow"]
  function monsterBodyFor(i) {
    if (monsterColor === "gradient") return slimeColor
    if (monsterColor === "theme") {
      if (i < 0) return slimePalette.accent || slimeColor2
      for (var k = 0; k < monsterHues.length; k++) {
        var c = slimePalette[monsterHues[(i + k) % monsterHues.length]]
        if (c) return c
      }
      return slimeColor2
    }
    return monsterBody
  }
  function monsterBody2For(i) { return monsterColor === "gradient" ? slimeColor2 : monsterBodyFor(i) }

  // 0 = paused. 30 by default: the goo moves slowly enough that 60 looks
  // much the same and costs roughly a third more CPU.
  property int slimeFps: 30
  property real dripAmount: 1.0
  property int shadingStyle: 3       // 0 soft, 1 anime, 2 manga, 3 print, 4 cel, 5 sketch
  property string slimeLayer: "above" // "above" windows, or "behind" them
  // Clock order everywhere (bar widget and command centre): time before date.
  property bool clockTimeFirst: false
  // Detritus drifting in the bar (off for a cleaner look).
  property bool barDebris: true
  // Physical shape of the bar: "classic" strip, "pills" (one per widget),
  // "islands" (one per section), "notch" (centre hangs from the edge) or
  // "blob" (the three sections huddled together in the middle, one slime).
  property string barShape: "classic"
  // What the bar is made of: "slime", "sinew", "bone" or "plain". Bone and
  // plain don't drip; plain also drops the floating debris.
  property string material: "slime"
  // How the drips move: "drip" (default), "honey" (slow, thick), "rain" (fast,
  // thin, many), "tar" (crawling, fat, few), "frozen" (hang still),
  // "stringy" (hang by several strands that snap as the drop falls),
  // "lava" (lava lamp: blobs bud off, pinch apart and sink),
  // "gelatinous" (the body jiggles; only the odd small bead is shaken loose).
  // dripAmount -1 means "variable" (each drip waxes and wanes).
  property string dripStyle: "drip"

  // ---- Easter egg: now and then a little adventurer (gnome, goblin,
  // skeleton, knight, wizard or priest) gets stuck in a fat drip, struggles,
  // and falls off with it. Any of them on any material. ~4% every 20 s.
  property vector4d eggDrip: Qt.vector4d(0, 0, 0, 0)   // x, edge y, start, active
  property string eggKind: "gnome"
  readonly property var eggKinds: ["gnome", "goblin", "skeleton", "knight", "wizard", "priest"]
  function startEgg(kind) {
    if (!slimeSkin || eggDrip.w > 0) return
    var rects = barShape === "pills" ? sharedBulbRects : (barShape === "classic" ? [] : sharedGroupRects)
    rects = rects.filter(function(r) { return r && r.z > 0 })
    var x, edge
    if (rects.length > 0) {
      var r = rects[Math.floor(Math.random() * rects.length)]
      x = r.x + r.z * (0.25 + Math.random() * 0.5)
      edge = r.y + r.w + (barShape === "notch" && r === sharedGroupRects[1] ? 7 : 3.85)
    } else {
      x = 120 + Math.random() * Math.max(100, eggSpan - 240)
      edge = barSize
    }
    eggKind = eggKinds.indexOf(kind) >= 0 ? kind : eggKinds[Math.floor(Math.random() * eggKinds.length)]
    eggDrip = Qt.vector4d(x, edge, animTime, 1)
  }
  property real eggSpan: 1920       // bar length, set by the bar window
  Timer {
    interval: 20000
    repeat: true
    running: root.slimeSkin && root.effectiveFps > 0
    onTriggered: if (Math.random() < 0.04) root.startEgg("")
  }
  // where the creature is, in bar space (matches eggShape() in the shader)
  readonly property var eggTip: {
    if (eggDrip.w < 1) return null
    var t = animTime - eggDrip.z
    if (t > 14) { Qt.callLater(function() { root.eggDrip = Qt.vector4d(0, 0, 0, 0) }); return null }
    var e = Math.max(0, Math.min(1, t / 6))
    var len = 44 * e * e * (3 - 2 * e)
    var f = Math.max(0, t - 10.6) / 3
    return { x: eggDrip.x, y: eggDrip.y + len + 300 * f * f }
  }
  readonly property vector4d dripStyleVec: {
    switch (dripStyle) {
    case "honey": return Qt.vector4d(0.45, 1.45, 0, 0.9)
    case "rain": return Qt.vector4d(2.4, 0.55, 0, 1.35)
    case "tar": return Qt.vector4d(0.22, 1.8, 0, 0.6)
    case "frozen": return Qt.vector4d(1, 1, 1, 1)
    case "stringy": return Qt.vector4d(0.75, 1, 0, 1.3)
    case "lava": return Qt.vector4d(0.45, 1.15, 0, 0.8)
    case "gelatinous": return Qt.vector4d(1.4, 1, 0, 0.9)
    case "cava": return Qt.vector4d(1, 1, 0, 1)
    default: return Qt.vector4d(1, 1, 0, 1)
    }
  }
  readonly property real materialId: Math.max(0, materialNames.indexOf(material))
  // every material drips (bone and plain included) with the chosen amount
  readonly property real dripLevel: dripAmount < 0 ? 1.2 : dripAmount
  readonly property vector4d dripExtraVec: Qt.vector4d(dripStyle === "stringy" ? 1 : dripStyle === "lava" ? 2 : dripStyle === "gelatinous" ? 3 : dripStyle === "cava" ? (cavaStyle === "ripple" ? 5 : 4) : 0, dripAmount < 0 ? 1 : 0, 0, 0)

  // ---- cava drip style: the drips are an audio visualizer ----
  // the shared ooze visualizer's cava (ui/SlimeCava), run only while the
  // style is picked; it's never drawn itself, the shader draws the drips
  property vector4d cava0: Qt.vector4d(0, 0, 0, 0)
  property vector4d cava1: Qt.vector4d(0, 0, 0, 0)
  property vector4d cava2: Qt.vector4d(0, 0, 0, 0)
  property vector4d cava3: Qt.vector4d(0, 0, 0, 0)
  readonly property vector4d cavaOpts: Qt.vector4d(cavaBars, cavaMirror ? 1 : 0, cavaReach, cavaWidth)
  SlimeCava {
    id: dripCava
    active: root.dripStyle === "cava"
    bars: 16
    sensitivity: root.cavaSens
    smoothing: root.cavaSmooth
    width: 0; height: 0
    onLevelsChanged: {
      var v = levels
      function n(i) { return v[i] || 0 }
      root.cava0 = Qt.vector4d(n(0), n(1), n(2), n(3))
      root.cava1 = Qt.vector4d(n(4), n(5), n(6), n(7))
      root.cava2 = Qt.vector4d(n(8), n(9), n(10), n(11))
      root.cava3 = Qt.vector4d(n(12), n(13), n(14), n(15))
    }
  }
  readonly property var shapeNames: ["classic", "pills", "islands", "notch", "blob"]
  readonly property var materialNames: ["slime", "sinew", "bone", "plain", "muscle"]
  readonly property var dripNames: ["drip", "honey", "rain", "tar", "frozen", "stringy", "lava", "gelatinous", "cava"]
  // (an unknown name, from an old or hand-edited skin.json, draws as the default)
  readonly property real barShapeId: barShape === "blob" ? 6 : Math.max(0, ["classic", "pills", "islands", "notch"].indexOf(barShape))
  // Latest left/centre/right section extents, for overlays (see sharedBulbRects).
  property var sharedGroupRects: []

  // ---- Skin settings persistence -----------------------------------------
  // Saved to ~/.config/omarchy/slime-shell/skin.json, loaded on start and
  // written (debounced) whenever one of these changes.
  readonly property var skinKeys: ["slimeRole", "gradientRole", "shadingStyle", "slimeFps", "dripAmount",
    "slimeLayer", "ccTab", "ccSections", "fontStyle", "clockTimeFirst", "barDebris", "barShape", "material", "dripStyle", "monsterColor",
    "desktopCorners", "cornerSlime", "ccKeyboard", "ccSidebarCollapsed", "ccFontScale",
    "cavaStyle", "cavaBars", "cavaMirror", "cavaSens", "cavaReach", "cavaWidth", "cavaSmooth",
    "dockEnabled", "dockEdge", "dockAlign", "dockAutoHide", "dockIconSize", "motionWall",
    "wallAuto", "wallShuffle", "wallPool", "wallSort"]
  property bool skinLoaded: false
  // A layer change made while the bar surface is still being set up is lost,
  // so "behind" only takes effect once the bar has been mapped for a moment.
  property bool layerReady: false
  Timer { interval: 800; running: root.skinLoaded; onTriggered: root.layerReady = true }

  function loadSkin(raw) {
    var saved = {}
    try { saved = JSON.parse(raw || "{}") } catch (e) { saved = {} }
    for (var i = 0; i < skinKeys.length; i++) {
      var key = skinKeys[i]
      if (saved[key] !== undefined && saved[key] !== null && typeof saved[key] === typeof root[key]) root[key] = saved[key]
    }
    if (!skinLoaded && motionWall !== "") motionSettle.begin()
    skinLoaded = true
  }

  function saveSkin() {
    if (!skinLoaded) return
    var out = {}
    for (var i = 0; i < skinKeys.length; i++) out[skinKeys[i]] = root[skinKeys[i]]
    skinFile.setText(JSON.stringify(out, null, 2) + "\n")
  }

  FileView {
    id: skinFile
    path: root.omarchyConfigDir + "/slime-shell/skin.json"
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadSkin(text())
    onLoadFailed: root.loadSkin("{}")
  }
  Timer { id: skinSaveTimer; interval: 400; onTriggered: root.saveSkin() }
  onSlimeRoleChanged: skinSaveTimer.restart()
  onGradientRoleChanged: skinSaveTimer.restart()
  onShadingStyleChanged: skinSaveTimer.restart()
  onSlimeFpsChanged: skinSaveTimer.restart()
  onDripAmountChanged: skinSaveTimer.restart()
  onSlimeLayerChanged: skinSaveTimer.restart()
  onFontStyleChanged: skinSaveTimer.restart()
  onClockTimeFirstChanged: skinSaveTimer.restart()
  onBarDebrisChanged: skinSaveTimer.restart()
  onBarShapeChanged: { skinSaveTimer.restart(); bulbsDirty() }
  onMonsterColorChanged: skinSaveTimer.restart()
  onDesktopCornersChanged: skinSaveTimer.restart()
  onCornerSlimeChanged: skinSaveTimer.restart()
  onCcKeyboardChanged: skinSaveTimer.restart()
  onCcFontScaleChanged: skinSaveTimer.restart()
  onCavaBarsChanged: skinSaveTimer.restart()
  onCavaStyleChanged: skinSaveTimer.restart()
  onCavaMirrorChanged: skinSaveTimer.restart()
  onCavaSensChanged: skinSaveTimer.restart()
  onCavaReachChanged: skinSaveTimer.restart()
  onCavaWidthChanged: skinSaveTimer.restart()
  onCavaSmoothChanged: skinSaveTimer.restart()
  onDockEnabledChanged: skinSaveTimer.restart()
  onDockEdgeChanged: skinSaveTimer.restart()
  onDockAlignChanged: skinSaveTimer.restart()
  onDockAutoHideChanged: skinSaveTimer.restart()
  onDockIconSizeChanged: skinSaveTimer.restart()
  onMotionWallChanged: skinSaveTimer.restart()
  onWallAutoChanged: skinSaveTimer.restart()
  onWallShuffleChanged: skinSaveTimer.restart()
  onWallPoolChanged: skinSaveTimer.restart()
  onWallSortChanged: skinSaveTimer.restart()
  onCcSidebarCollapsedChanged: skinSaveTimer.restart()
  // the edge across from the bar (for the corner patches)
  readonly property string oppositeEdge: ({ top: "bottom", bottom: "top", left: "right", right: "left" })[position] || "bottom"
  onMaterialChanged: skinSaveTimer.restart()
  onDripStyleChanged: skinSaveTimer.restart()
  onCcTabChanged: skinSaveTimer.restart()
  onCcSectionsChanged: skinSaveTimer.restart()
  property bool commandCenterOpen: false
  // Slime-Tasks as a pop-out in the middle of the screen, over everything
  // (omarchy-shell slime-shell tasks)
  property bool tasksPopOpen: false
  // The window a hovered media widget has borrowed the keyboard for (space
  // to play/pause, m to mute: SlimeMediaKeys), or null.
  property var hoverKeysWindow: null
  // Latest widget bulb rects, for overlays drawn outside the bar window
  // (notification toasts) so their slime lines up with the bar's.
  property var sharedBulbRects: []
  readonly property double slimeT0: Date.now()
  property real animTime: 0
  // The animation only runs when someone can see it: it stops while the bar
  // is hidden or every screen is showing a fullscreen window, and drops to
  // 15 fps after a couple of idle minutes (full speed again on any input).
  IdleMonitor { id: slimeIdle; timeout: 120; respectInhibitors: false }
  readonly property bool allFullscreen: {
    var ms = Hyprland.monitors.values
    if (!ms || ms.length === 0) return false
    for (var i = 0; i < ms.length; i++) {
      var ws = ms[i].activeWorkspace
      if (!ws || !ws.hasFullscreen) return false
    }
    return true
  }
  readonly property bool animUnseen: barHidden || allFullscreen
  readonly property int effectiveFps: animUnseen ? 0 : slimeIdle.isIdle ? Math.min(slimeFps, 15) : slimeFps
  Timer {
    interval: root.effectiveFps > 0 ? Math.round(1000 / root.effectiveFps) : 1000
    repeat: true
    running: root.slimeSkin && root.effectiveFps > 0
    onTriggered: root.animTime = (Date.now() - root.slimeT0) / 1000
  }
  function bob(phase) { return slimeSkin ? Math.sin(animTime * 1.3 + phase) * 1.6 : 0 }
  function sway(phase) { return slimeSkin ? Math.sin(animTime * 0.9 + phase * 1.7) * 1.8 : 0 }

  // when a click on the bar just closed it (see the bar's catcher), the same
  // click reaching the clock shouldn't open it straight back up
  property real ccClosedByBar: 0
  function toggleCommandCenter() {
    if (!slimeSkin) return
    if (!commandCenterOpen && Date.now() - ccClosedByBar < 600) return
    commandCenterOpen = !commandCenterOpen
  }

  // ...and the command centre opening closes whichever widget panel is open.
  onCommandCenterOpenChanged: {
    if (commandCenterOpen) tasksPopOpen = false
    if (!commandCenterOpen || !activePopout) return
    if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
    else if ("close" in activePopout) activePopout.close()
  }

  IpcHandler {
    target: "slime-shell"
    function toggle(): void { root.toggleCommandCenter() }
    function open(): void { root.commandCenterOpen = root.slimeSkin }
    function close(): void { root.commandCenterOpen = false }
    function shading(style: int): void { root.shadingStyle = style }
    function gradient(role: string): void { root.gradientRole = role }
    function color(role: string): void { root.slimeRole = role }
    // (each checked: these are saved to skin.json, and a typo would stay)
    function fps(n: int): void { root.slimeFps = Math.max(5, Math.min(144, n)) }
    // Draw the slime "above" windows or "behind" them.
    function shape(name: string): void { if (root.shapeNames.indexOf(name) >= 0) root.barShape = name }
    function material(name: string): void { if (root.materialNames.indexOf(name) >= 0) root.material = name }
    function drip(style: string): void { if (root.dripNames.indexOf(style) >= 0) root.dripStyle = style }
    // the cava drip style's look: drips | ripple
    function cava(style: string): void { root.cavaStyle = style === "ripple" ? "ripple" : "drips" }
    // SlimeS-Dock: toggle | on | off | apps (the add-apps panel) |
    // top / bottom / left / right (its edge) | start / center / end (along it) |
    // autohide / pinned
    // the next wallpaper (as the Wallpapers tab's switching would pick it)
    function nextWallpaper(): void { root.nextWallpaper() }
    // a wallpaper: a still (set as the background) or a video / gif (played)
    function wallpaper(path: string): void {
      if (root.isMotion(path)) root.setMotionWall(path)
      else { root.clearMotionWall(); Quickshell.execDetached(["omarchy-theme-bg-set", path]) }
    }
    // Desktop styling: slime in the far corners, on | off | toggle
    function corners(action: string): void { root.cornerSlime = action === "toggle" ? !root.cornerSlime : action === "on" }
    function dock(action: string): void {
      if (action === "toggle") root.dockEnabled = !root.dockEnabled
      else if (action === "on" || action === "off") root.dockEnabled = action === "on"
      else if (action === "apps") { root.dockEnabled = true; root.dockPanelRequest++ }
      else if (["top", "bottom", "left", "right"].indexOf(action) >= 0) root.dockEdge = action
      else if (["start", "center", "end"].indexOf(action) >= 0) root.dockAlign = action
      else if (action === "autohide" || action === "pinned") root.dockAutoHide = action === "autohide"
    }
    // (shh) summon the easter egg now
    function egg(): void { root.startEgg("") }
    function eggAs(kind: string): void { root.startEgg(kind) }
    function layer(where: string): void { root.slimeLayer = where === "behind" ? "behind" : "above" }
    function toggleLayer(): void { root.slimeLayer = root.slimeLayer === "behind" ? "above" : "behind" }
    // Open the command centre on a tab: home, system, wallpapers, tasks, startup, settings.
    function tab(name: string): void { root.ccTab = name; root.commandCenterOpen = root.slimeSkin }
    // Keybind-friendly: open on that tab, or close if it's already showing it.
    // Slime-Tasks pop-out, centred on the focused screen
    function tasks(): void { root.tasksPopOpen = !root.tasksPopOpen }
    function toggleTab(name: string): void {
      if (root.commandCenterOpen && root.ccTab === name) { root.commandCenterOpen = false; return }
      root.ccTab = name
      root.commandCenterOpen = root.slimeSkin
    }
  }

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  // Pills: dropping a widget on the middle of another joins their pills
  // (entry flag pillJoin = "shares a pill with the next widget").
  property bool barDragMerge: false
  // Pills: dragging a pill-mate to its pill's far end — {kind: "swap" |
  // "split", side: -1 | 1, other: outermost slot, marker} — or null.
  property var barDragEdge: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []
  // Something on the bar moved or resized (a slot, a section row, the
  // layout): each bar window recomputes its widget bulbs once, next frame.
  // Recomputing them every animation tick instead cost ~30% of a core.
  signal bulbsDirty()
  onBarConfigSerialChanged: bulbsDirty()   // pills joined/split, widgets added/removed
  property var pluginBarApis: ({})
  property var pluginObjectOwners: []

  Component {
    id: pluginBarApiComponent
    PluginBarApi { }
  }

  function publicLayoutConfig() {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  function bindPluginBarApi(api) {
    if (!api) return
    // Third-party widgets draw their own (dark, stock) popup panels in
    // `foreground`; on Slime that's the ink meant for text on the goo, which
    // vanishes on those panels. Give them the theme's normal text colour and
    // keep the ink in `barForeground`, which is what bar icons use.
    api.foreground = Qt.binding(function() { return root.slimeSkin ? Color.foreground : root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    api.centerSectionRevealHeld = Qt.binding(function() { return root.centerSectionRevealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    root.syncPluginBarApiObjects(api)
  }

  function syncPluginBarApiObjects(api) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = root.publicLayoutConfig()
  }

  function pluginObjectRecord(target) {
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (record && record.target === target) return record
    }
    return null
  }

  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var existing = pluginObjectOwners[i]
      if (!existing || existing.target !== target) next.push(existing)
    }
    var updated = record || { target: target, pluginId: key, clickTarget: false, popout: false }
    updated[role] = true
    next.push(updated)
    pluginObjectOwners = next
    return true
  }

  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (!record || record.target !== target || record.pluginId !== key) {
        next.push(record)
        continue
      }
      record[role] = false
      if (record.clickTarget || record.popout) next.push(record)
    }
    pluginObjectOwners = next
  }

  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target)) out.push(target)
    }
    return out
  }

  function syncAllPluginBarApiObjects() {
    for (var id in pluginBarApis) root.syncPluginBarApiObjects(pluginBarApis[id])
  }

  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }

  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
  }

  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
  }

  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null

    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function") {
      // Only the trusted built-in bar receives ShellRoot and can request a
      // service-capable facade for the widget it is instantiating.
      pluginShell = root.shell.pluginShellForId(moduleName)
    } else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function") {
      // Replacement bars receive a service-less entry facade. Giving an
      // untrusted bar a generic facade factory would let it retrieve another
      // third-party plugin's live service object.
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    }

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "")
          ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api) return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId) return true
    }
    return false
  }

  function releasePluginObjects(pluginId) {
    var owned = pluginObjectOwners.slice()
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
    }
    pluginObjectOwners = pluginObjectOwners.filter(function(record) {
      return record && record.pluginId !== pluginId
    })
  }

  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: syncAllPluginBarApiObjects()
  onClickTargetsChanged: syncAllPluginBarApiObjects()
  onLayoutConfigChanged: syncAllPluginBarApiObjects()
  onModuleSlotsChanged: { Qt.callLater(prunePluginBarApis); bulbsDirty() }

  Component.onDestruction: {
    SlimeHub.unregister(root)
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragMerge = false
    barDragEdge = null
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    // One dropdown at a time: a widget panel opening closes the command centre.
    if (commandCenterOpen) commandCenterOpen = false
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  // "Behind windows": while any panel is out (a widget's panel, a hover card,
  // the command centre) the bar comes up above windows so the panel can be
  // seen, and sinks back once it has finished closing.
  property int hoverPeeks: 0
  readonly property bool panelWantsTop: activePopout !== null || hoverPeeks > 0
  property bool panelRaised: false
  onPanelWantsTopChanged: {
    if (panelWantsTop) { panelLower.stop(); panelRaised = true }
    else panelLower.restart()
  }
  Timer { id: panelLower; interval: 450; onTriggered: root.panelRaised = root.panelWantsTop }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: slimeSkin ? slimeBarSize : (vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      var id = entryId(change.entry)
      var list = layoutConfig[change.region]
      list[change.index] = change.entry
      var settings = entrySettings(change.entry)
      // Slime: a widget can be on the bar several times (spacers), so patch
      // only the one at this position: the k-th slot with this id in the
      // section, counted along the bar.
      var k = 0
      for (var j = 0; j < change.index; j++) if (list[j] && entryId(list[j]) === id) k++
      var same = moduleSlots.filter(function(sl) { return sl && sl.region === change.region && sl.moduleName === id })
      same.sort(function(a, b) {
        try { var pa = a.mapToItem(null, 0, 0), pb = b.mapToItem(null, 0, 0); return vertical ? pa.y - pb.y : pa.x - pb.x }
        catch (e) { return 0 }
      })
      // one copy per monitor: patch the k-th of each monitor's run
      var perScreen = {}
      for (var s = 0; s < same.length; s++) {
        var key = slotScreenName(same[s])
        perScreen[key] = (perScreen[key] || 0) + 1
        if (perScreen[key] - 1 !== k) continue
        var item = same[s].activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  // Which layout entry a slot shows, as an index into layoutEntries(region).
  // A widget can be on the bar more than once (spacers), so match by rank:
  // the k-th slot with this id along the bar (on its monitor) is the k-th
  // entry with that id. Name lookups alone always found the first copy.
  function slotLayoutIndex(slot) {
    if (!slot) return -1
    var win = slotWindow(slot)
    var same = moduleSlots.filter(function(sl) {
      return sl && sl.region === slot.region && sl.moduleName === slot.moduleName && sameWindow(slotWindow(sl), win)
    })
    same.sort(function(a, b) { return slotAlong(a) - slotAlong(b) })
    var k = same.indexOf(slot)
    var entries = layoutEntries(slot.region)
    for (var i = 0, seen = 0; i < entries.length; i++) {
      if (!entries[i] || entryId(entries[i]) !== slot.moduleName) continue
      if (seen === k) return i
      seen++
    }
    return -1
  }

  function slotAlong(slot) {
    try { var p = slot.mapToItem(null, 0, 0); return vertical ? p.y : p.x } catch (e) { return 0 }
  }
  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: {
    applyBarConfig()
    SlimeHub.register(root)
    // your own wallpapers: the Wallpapers tab lists whatever is dropped in here
    Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/Pictures/SlimeS-Wallpapers"])
  }

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  // The centre's hover (it reveals the indicators that are off) counts only
  // on or just beside the indicators widget: the centre's hover area spans the
  // whole bar, and with the blob shape the whole bar is goo you can hover.
  readonly property real indicatorRevealReach: 26
  function pointerNearIndicators(item, pos) {
    var slots = moduleSlots
    for (var i = 0; i < slots.length; i++) {
      var sl = slots[i]
      if (!sl || sl.moduleName !== "slime.indicators" || !sl.visible || sl.width <= 0) continue
      var p = item.mapToItem(sl, pos.x, pos.y), r = indicatorRevealReach
      if (p.x > -r && p.x < sl.width + r && p.y > -r && p.y < sl.height + r) return true
    }
    return false
  }
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      // a widget dragged somewhere normally leaves any joined pill it was in
      detachFromPill(config, source.region, source.moduleName)
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
      if (changed) {
        var list = rawLayoutSection(config, toRegion), i = rawEntryIndex(list, source.moduleName)
        if (i > 0 && list[i - 1].pillJoin) delete list[i - 1].pillJoin   // don't land inside a joined pill
      }
    })
    return changed
  }

  // ---- joined pills ------------------------------------------------------------
  // Take entry `name` out of whatever joined pill it's in, keeping the rest of
  // that pill joined around the gap it leaves.
  function detachFromPill(config, region, name) {
    var list = rawLayoutSection(config, region), i = rawEntryIndex(list, name)
    if (i < 0) return
    if (i > 0 && list[i - 1].pillJoin) {
      if (list[i].pillJoin) list[i - 1].pillJoin = true
      else delete list[i - 1].pillJoin
    }
    delete list[i].pillJoin
  }

  // Dropped on the middle half of another widget, in pills mode.
  function pillMergeAt(targetSlot, scenePoint) {
    if (barShape !== "pills" || !targetSlot) return false
    try {
      var p = targetSlot.mapFromItem(null, scenePoint.x, scenePoint.y)
      var f = vertical ? p.y / targetSlot.height : p.x / targetSlot.width
      return f > 0.25 && f < 0.75
    } catch (e) { return false }
  }

  function mergeMarkerRect(slot) {
    try {
      var p = barDragScreenPoint(slot.mapToItem(null, 0, 0))
      return { x: p.x, y: p.y + slot.height - 3, width: slot.width, height: 3 }
    } catch (e) { return null }
  }

  // The joined pill run (first and last layout index) that entry `i` is in.
  function pillRun(entries, i) {
    var a = i, b = i
    while (a > 0 && entries[a - 1] && entries[a - 1].pillJoin) a--
    while (b < entries.length - 1 && entries[b] && entries[b].pillJoin) b++
    return { start: a, end: b }
  }
  // Re-link a run after its members were shuffled: all joined but the last.
  function relinkPill(entries, start, end) {
    for (var i = start; i <= end; i++) {
      if (i < end) entries[i].pillJoin = true
      else delete entries[i].pillJoin
    }
  }
  // The slot showing layout entry `index` of `region` on `win`'s bar.
  function slotAtLayoutIndex(region, index, win) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var sl = moduleSlots[i]
      if (sl && sl.region === region && sameWindow(slotWindow(sl), win) && slotLayoutIndex(sl) === index) return sl
    }
    return null
  }

  // Dragging a pill-mate out to either end of its pill. Two drop spots on
  // each side: a marker just inside the pill swaps it with the outermost
  // widget there (the pill stays together), a marker just past the pill's
  // end splits it off into a pill of its own beside the group.
  function pillEdgeDrop(source, scenePoint) {
    if (barShape !== "pills" || !source) return null
    var fi = slotLayoutIndex(source)
    if (fi < 0) return null
    var run = pillRun(layoutEntries(source.region), fi)
    if (run.end <= run.start) return null
    var win = slotWindow(source)
    var members = []
    for (var i = run.start; i <= run.end; i++) {
      var sl = slotAtLayoutIndex(source.region, i, win)
      if (!sl || !sl.visible || sl.width <= 0) continue
      var p = sl.mapToItem(null, 0, 0)
      members.push({ slot: sl, at: vertical ? p.y : p.x, len: vertical ? sl.height : sl.width, cross: vertical ? p.x : p.y, thick: vertical ? sl.width : sl.height })
    }
    if (members.length < 2) return null
    members.sort(function(a, b) { return a.at - b.at })
    var first = members[0], last = members[members.length - 1]
    var g0 = first.at, g1 = last.at + last.len
    var a = vertical ? scenePoint.y : scenePoint.x
    var reach = 36                                      // how far past the end still splits
    var side = 0, kind = ""
    if (a >= g0 - reach && a < g0 + 3) { side = -1; kind = "split" }
    else if (a >= g0 + 3 && a < g0 + Math.min(first.len * 0.4, 22)) { side = -1; kind = "swap" }
    else if (a > g1 - 3 && a <= g1 + reach) { side = 1; kind = "split" }
    else if (a > g1 - Math.min(last.len * 0.4, 22) && a <= g1 - 3) { side = 1; kind = "swap" }
    if (!side) return null
    var outer = side < 0 ? first : last
    if (kind === "swap" && outer.slot === source) return null   // already the outermost
    // the marker: inside the pill for a swap, out in the gap for a split
    var along = kind === "swap" ? (side < 0 ? g0 + 5 : g1 - 5) : (side < 0 ? g0 - 9 : g1 + 9)
    var t = Style.spacing.xs
    var sp = barDragScreenPoint(vertical ? { x: outer.cross, y: along } : { x: along, y: outer.cross })
    var marker = vertical ? { x: sp.x, y: sp.y - t / 2, width: outer.thick, height: t }
                          : { x: sp.x - t / 2, y: sp.y, width: t, height: outer.thick }
    return { kind: kind, side: side, other: outer.slot, marker: marker }
  }

  // Take `source` out of its pill into one of its own, just before (side -1)
  // or after (side 1) the rest of the group.
  function splitFromPill(source, side) {
    if (!source || !root.shell || typeof root.shell.mutateShellConfig !== "function") return
    var fi = slotLayoutIndex(source)
    if (fi < 0) return
    root.shell.mutateShellConfig(function(config) {
      var e = rawLayoutSection(config, source.region)
      if (!e[fi] || Util.canonicalWidgetId(e[fi].id) !== source.moduleName) return
      var run = pillRun(e, fi)
      if (run.end <= run.start) return
      var moved = e.splice(fi, 1)[0]
      delete moved.pillJoin
      relinkPill(e, run.start, run.end - 1)
      e.splice(side < 0 ? run.start : run.end, 0, moved)
    })
  }

  function samePill(source, target) {
    if (barShape !== "pills" || !source || !target || source.region !== target.region) return false
    var fi = slotLayoutIndex(source), ti = slotLayoutIndex(target)
    if (fi < 0 || ti < 0 || fi === ti) return false
    var run = pillRun(layoutEntries(source.region), fi)
    return run.end > run.start && ti >= run.start && ti <= run.end
  }

  // Join `source` onto `target`'s pill: it moves in right after the target
  // (widgets keep their normal spacing; only the pill underneath merges).
  function mergePills(source, target) {
    if (!source || !target || source === target || !root.shell || typeof root.shell.mutateShellConfig !== "function") return
    var fi = slotLayoutIndex(source), ti = slotLayoutIndex(target)
    if (fi < 0 || ti < 0) return
    // dropped on a pill-mate: the two swap places, the pill stays as it was
    if (samePill(source, target)) {
      root.shell.mutateShellConfig(function(config) {
        var e = rawLayoutSection(config, source.region)
        if (!e[fi] || !e[ti] || Util.canonicalWidgetId(e[fi].id) !== source.moduleName) return
        var run = pillRun(e, fi)
        var t = e[fi]; e[fi] = e[ti]; e[ti] = t
        relinkPill(e, run.start, run.end)
      })
      return
    }
    root.shell.mutateShellConfig(function(config) {
      var from = rawLayoutSection(config, source.region)
      if (!from[fi] || Util.canonicalWidgetId(from[fi].id) !== source.moduleName) return
      if (fi > 0 && from[fi - 1].pillJoin) {
        if (from[fi].pillJoin) from[fi - 1].pillJoin = true
        else delete from[fi - 1].pillJoin
      }
      var moved = from.splice(fi, 1)[0]
      delete moved.pillJoin
      var to = rawLayoutSection(config, target.region)
      if (source.region === target.region && fi < ti) ti -= 1
      if (!to[ti]) return
      if (to[ti].pillJoin) moved.pillJoin = true     // slot into the middle of a longer pill
      to[ti].pillJoin = true
      to.splice(ti + 1, 0, moved)
    })
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot || !root.shell || typeof root.shell.mutateShellConfig !== "function") return false
    var from = slotLayoutIndex(sourceSlot), target = slotLayoutIndex(targetSlot)
    if (from < 0 || target < 0) return false
    var fromRegion = sourceSlot.region, toRegion = targetSlot.region
    var to = afterTarget ? target + 1 : target
    if (fromRegion === toRegion && (to === from || to === from + 1)) return false
    var shuffle = samePill(sourceSlot, targetSlot)

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      var fromEntries = rawLayoutSection(config, fromRegion)
      var toEntries = rawLayoutSection(config, toRegion)
      if (!fromEntries[from] || Util.canonicalWidgetId(fromEntries[from].id) !== sourceSlot.moduleName) return
      // dropped on a pill-mate: reorder inside the pill and keep it whole
      if (shuffle) {
        var run = pillRun(fromEntries, from)
        var m = fromEntries.splice(from, 1)[0]
        var at = from < to ? to - 1 : to
        fromEntries.splice(Math.max(run.start, Math.min(run.end, at)), 0, m)
        relinkPill(fromEntries, run.start, run.end)
        changed = true
        return
      }
      // a widget dragged somewhere normally leaves any joined pill it was in
      if (from > 0 && fromEntries[from - 1].pillJoin) {
        if (fromEntries[from].pillJoin) fromEntries[from - 1].pillJoin = true
        else delete fromEntries[from - 1].pillJoin
      }
      var moved = fromEntries.splice(from, 1)[0]
      delete moved.pillJoin
      if (fromRegion === toRegion && from < to) to -= 1
      to = Math.max(0, Math.min(toEntries.length, to))
      toEntries.splice(to, 0, moved)
      if (to > 0 && toEntries[to - 1].pillJoin) delete toEntries[to - 1].pillJoin   // don't land inside a joined pill
      changed = true
    })
    return changed
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    if (/^#[0-9A-Fa-f]{6}$/.test(root.foregroundOverride)) {
      root.foregroundAnimationEnabled = false
      root.transparentForeground = root.foregroundOverride
      root.useTransparentForeground = true
      root.transparent = true
      root.restoreForegroundAnimation()
      return
    }

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: {
    scheduleTransparentForegroundRefresh()
    if (dockEdge === position) dockEdge = oppositeEdge     // the dock moves across
  }
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()
  onForegroundOverrideChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }

    // Lets a bar-widget/service plugin that paints its own chrome behind the
    // transparent bar supply a foreground color matched to that chrome,
    // instead of the wallpaper-sampled default. Empty string clears it.
    function setForegroundOverride(hex: string): void {
      root.foregroundOverride = hex
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        root: barRoot
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        root: barRoot
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        root: barRoot
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }
}
