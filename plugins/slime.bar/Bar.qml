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

// Slime Shell bar: a clone of the Omarchy bar engine (layout, widget slots,
// drag/reorder, popouts, IPC all unchanged) with the slime skin painted by a
// shader behind the widgets. Widgets float in the ooze, each sagging a bulb of
// slime beneath it, and the slime.clock-weather widget drips the command
// centre open. The skin draws on a top bar; other positions fall back to the
// stock Omarchy look.
Item {
  id: root

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
  property var palette: ({})
  function parsePalette(raw) {
    var out = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6,8})"/)
      if (m) out[m[1]] = m[2]
    }
    palette = out
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
  readonly property color slimeInk: palette.background || Color.background
  property string slimeRole: "accent"
  readonly property color slimeColor: palette[slimeRole] || Color.accent
  readonly property color paperColor: {
    var fg = Qt.color(palette.foreground || Color.foreground)
    var bg = Qt.color(palette.background || Color.background)
    return fg.hslLightness >= bg.hslLightness ? fg : bg
  }
  // "auto" picks the palette colour whose hue sits roughly 100° away from the
  // slime colour, for an anime-style complementary sweep.
  property string gradientRole: "auto"
  readonly property var hueRoles: ["red", "yellow", "green", "cyan", "blue", "magenta",
    "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]
  readonly property color slimeColor2: {
    if (gradientRole === "none") return slimeColor
    if (gradientRole !== "auto") return palette[gradientRole] || slimeColor
    var h1 = slimeColor.hsvHue
    if (h1 < 0) return palette.accent || slimeColor
    var best = slimeColor, bestScore = 1e9
    for (var i = 0; i < hueRoles.length; i++) {
      if (!palette[hueRoles[i]]) continue
      var c = Qt.color(palette[hueRoles[i]])
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
  readonly property color monsterBlush: palette.bright_magenta || palette.magenta || "#ff6fa8"
  // How the slime icons (workspaces, agents, launcher) are coloured:
  //   paper     pale paper tinted with the gradient partner (default: pops off the ooze)
  //   theme     the theme's own colours; workspace slimes each take a different hue
  //   gradient  shaded top to bottom like the bar: slime colour into its partner
  property string monsterColor: "paper"
  // ---- Desktop styling ----
  property int desktopCorners: 0            // rounded screen corners: radius in px, 0 = off
  property bool cornerSlime: false          // slime patches in the corners across from the bar
  property bool ccKeyboard: true            // command centre keyboard navigation
  property real ccFontScale: 1.0            // command centre text size (0.8 – 1.4)
  property bool ccSidebarCollapsed: false   // command centre's tab sidebar folded to icons
  readonly property var monsterHues: ["bright_green", "bright_cyan", "bright_magenta", "bright_yellow", "bright_blue", "bright_red",
    "green", "cyan", "magenta", "yellow"]
  function monsterBodyFor(i) {
    if (monsterColor === "gradient") return slimeColor
    if (monsterColor === "theme") {
      if (i < 0) return palette.accent || slimeColor2
      for (var k = 0; k < monsterHues.length; k++) {
        var c = palette[monsterHues[(i + k) % monsterHues.length]]
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
  // "islands" (one per section) or "notch" (centre hangs from the edge).
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
    default: return Qt.vector4d(1, 1, 0, 1)
    }
  }
  readonly property real materialId: ["slime", "sinew", "bone", "plain"].indexOf(material)
  // every material drips (bone and plain included) with the chosen amount
  readonly property real dripLevel: dripAmount < 0 ? 1.2 : dripAmount
  readonly property vector4d dripExtraVec: Qt.vector4d(dripStyle === "stringy" ? 1 : dripStyle === "lava" ? 2 : dripStyle === "gelatinous" ? 3 : 0, dripAmount < 0 ? 1 : 0, 0, 0)
  readonly property real barShapeId: ["classic", "pills", "islands", "notch"].indexOf(barShape)
  // Latest left/centre/right section extents, for overlays (see sharedBulbRects).
  property var sharedGroupRects: []

  // ---- Skin settings persistence -----------------------------------------
  // Saved to ~/.config/omarchy/slime-shell/skin.json, loaded on start and
  // written (debounced) whenever one of these changes.
  readonly property var skinKeys: ["slimeRole", "gradientRole", "shadingStyle", "slimeFps", "dripAmount",
    "slimeLayer", "ccTab", "ccSections", "fontStyle", "clockTimeFirst", "barDebris", "barShape", "material", "dripStyle", "monsterColor",
    "desktopCorners", "cornerSlime", "ccKeyboard", "ccSidebarCollapsed", "ccFontScale"]
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

  function toggleCommandCenter() {
    if (!slimeSkin) return
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
    function fps(n: int): void { root.slimeFps = n }
    // Draw the slime "above" windows or "behind" them.
    function shape(name: string): void { root.barShape = name }
    function material(name: string): void { root.material = name }
    function drip(style: string): void { root.dripStyle = style }
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
  }

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
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
  onPositionChanged: scheduleTransparentForegroundRefresh()
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
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
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
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  // The slime scene (one SDF shader for bar, drips, bulbs, command centre):
  // the bar window draws the strip, the skin window everything past it. Both
  // share every uniform, so the goo runs seamlessly across the seam.
  component SlimeScene: ShaderEffect {
    required property var win
    fragmentShader: Qt.resolvedUrl("shaders/slime.frag.qsb")
    // every shader uniform set explicitly: unset ones are not guaranteed to be 0
    property vector4d cullRect: Qt.vector4d(0, 0, 0, 0)
    property real clipTop: -100000
    property real poolDepth: 0
    property vector2d origin: Qt.vector2d(0, 0)
    property real blobMode: 0
    property real orient: root.orientId
    property vector2d screenSize: win.screen ? Qt.vector2d(win.screen.width, win.screen.height) : Qt.vector2d(0, 0)

    property real time: root.animTime
    property real barHeight: root.barSize
    property real openProgress: win.ccProgress
    property real dripAmount: root.dripLevel
    property real shadingStyle: root.shadingStyle
    property vector2d resolution: Qt.vector2d(width, height)
    property vector4d panelRect: Qt.vector4d(win.ccPanelX, 0, win.ccAlong, win.ccAway)
    property color slimeColor: root.slimeColor
    property color slimeColor2: root.slimeColor2
    property color paperColor: root.paperColor
    property real barShape: root.barShapeId
    property real material: root.materialId
    property vector4d dripStyle: root.dripStyleVec
    // drip-zone depth: falling goo shrinks away before it, and past it only
    // the command centre's column is drawn (the window is taller while it's open)
    property vector4d dripExtra: Qt.vector4d(root.dripExtraVec.x, root.dripExtraVec.y,
      root.barSize + win.dripRoom, root.barSize + win.dripRoom)
    property vector4d eggDrip: root.eggDrip
    property vector4d group0: win.groupRects[0] || win.noBulb
    property vector4d group1: win.groupRects[1] || win.noBulb
    property vector4d group2: win.groupRects[2] || win.noBulb
    property vector4d bulb0: win.bulbRects[0] || win.noBulb
    property vector4d bulb1: win.bulbRects[1] || win.noBulb
    property vector4d bulb2: win.bulbRects[2] || win.noBulb
    property vector4d bulb3: win.bulbRects[3] || win.noBulb
    property vector4d bulb4: win.bulbRects[4] || win.noBulb
    property vector4d bulb5: win.bulbRects[5] || win.noBulb
    property vector4d bulb6: win.bulbRects[6] || win.noBulb
    property vector4d bulb7: win.bulbRects[7] || win.noBulb
    property vector4d bulb8: win.bulbRects[8] || win.noBulb
    property vector4d bulb9: win.bulbRects[9] || win.noBulb
    property vector4d bulb10: win.bulbRects[10] || win.noBulb
    property vector4d bulb11: win.bulbRects[11] || win.noBulb
    property vector4d bulb12: win.bulbRects[12] || win.noBulb
    property vector4d bulb13: win.bulbRects[13] || win.noBulb
    property vector4d bulb14: win.bulbRects[14] || win.noBulb
    property vector4d bulb15: win.bulbRects[15] || win.noBulb
    property vector4d bulb16: win.bulbRects[16] || win.noBulb
    property vector4d bulb17: win.bulbRects[17] || win.noBulb
    property vector4d bulb18: win.bulbRects[18] || win.noBulb
    property vector4d bulb19: win.bulbRects[19] || win.noBulb
    property vector4d bulb20: win.bulbRects[20] || win.noBulb
    property vector4d bulb21: win.bulbRects[21] || win.noBulb
    property vector4d bulb22: win.bulbRects[22] || win.noBulb
    property vector4d bulb23: win.bulbRects[23] || win.noBulb
    }

  component BarPanel: PanelWindow {
    id: barWindow

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
      var fall = root.dripStyle === "stringy" || root.dripStyle === "lava" || root.dripStyle === "gelatinous" ? 110 : 60
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
          var eid = entryId(entry)
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
      avoid: barWindow.bulbRects
      within: root.barShape === "classic" ? [] : (root.barShape === "pills" ? barWindow.bulbRects : barWindow.groupRects)
      bits: {
        var out = [], kinds = root.material === "sinew" ? ["eye", "tooth", "sword", "eye", "axe", "tooth", "eye", "skull"]
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
        visible: barWindow.visible
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
        pal: root.palette
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
      readonly property real dripDepth: Math.min(barWindow.dripRoom, depth)
      SlimeScene {
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
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0
    onXChanged: root.bulbsDirty()
    onYChanged: root.bulbsDirty()
    onWidthChanged: root.bulbsDirty()
    onVisibleChanged: root.bulbsDirty()

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property real bobPhase: {
      var h = 0
      for (var i = 0; i < moduleName.length; i++) h = (h * 31 + moduleName.charCodeAt(i)) % 997
      return h / 997 * 6.283
    }
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    onXChanged: root.bulbsDirty()
    onYChanged: root.bulbsDirty()
    onWidthChanged: root.bulbsDirty()
    onHeightChanged: root.bulbsDirty()
    onVisibleChanged: root.bulbsDirty()
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      // Floating in the ooze: each widget bobs and sways on its own phase.
      transform: Translate { y: root.bob(slot.bobPhase) }
      rotation: root.sway(slot.bobPhase)
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      // Floating in the ooze: each widget bobs and sways on its own phase.
      transform: Translate { y: root.bob(slot.bobPhase) }
      rotation: root.sway(slot.bobPhase)
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      // Floating in the ooze: each widget bobs and sways on its own phase.
      transform: Translate { y: root.bob(slot.bobPhase) }
      rotation: root.sway(slot.bobPhase)
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var edge = root.pillEdgeDrop(slot, scenePoint)
          root.barDragEdge = edge
          var drop = edge ? { slot: edge.other, after: edge.side > 0 } : root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragMerge = !edge && !!drop && root.pillMergeAt(drop.slot, scenePoint)
          root.barDragTargetGeometry = edge ? edge.marker : !drop ? null
            : root.barDragMerge ? root.mergeMarkerRect(drop.slot) : root.dropMarkerRect(drop.slot, drop.after)
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter
        var merge = root.barDragMerge
        var edge = root.barDragEdge

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && edge) {
          if (edge.kind === "swap") root.mergePills(slot, edge.other)   // pill-mates: swaps them
          else root.splitFromPill(slot, edge.side)
          mouse.accepted = true
        } else if (wasDragging && targetSlot) {
          if (merge) root.mergePills(slot, targetSlot)
          else root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      // Slime widgets are clones of the built-ins, so they get the full bar
      // host exactly like the originals do.
      var trusted = firstParty || moduleName.indexOf("slime.") === 0
      if ("bar" in target) target.bar = trusted
        ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
