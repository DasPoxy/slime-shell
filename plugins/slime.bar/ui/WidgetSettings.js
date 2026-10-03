.pragma library

// A bar widget's settings, saved into its entry in the bar layout
// (shell.json). The entry never carries "source": the bar loads the widget
// from it, so a saved one pins the widget to that path (a stale checkout, a
// moved install). "id" is set here.

function entry(id, settings, changes) {
  var e = { id: id }
  for (var k in settings) if (k !== "id" && k !== "source") e[k] = settings[k]
  for (var c in changes) e[c] = changes[c]
  return e
}

// save(widget, changes[, id]): applied to widget.settings at once (so it
// changes on the click), then written through the bar's shell.
function save(widget, changes, id) {
  id = id || widget.moduleName
  var e = entry(id, widget.settings, changes)
  widget.settings = e
  var shell = widget.bar && widget.bar.shell
  if (shell && typeof shell.updateEntryInline === "function") shell.updateEntryInline(id, e)
  return e
}

// A widget that can be on the bar more than once (the spacer): written to the
// entry at its own place ({region, index}), not the first with its id.
function saveAt(widget, changes, at) {
  var e = entry(widget.moduleName, widget.settings, changes)
  widget.settings = e
  var shell = widget.bar && widget.bar.shell
  if (!at || !shell || typeof shell.mutateShellConfig !== "function") return e
  shell.mutateShellConfig(function(config) {
    var list = config.bar && config.bar.layout ? config.bar.layout[at.region] : null
    if (list && list[at.index] && list[at.index].id === widget.moduleName) list[at.index] = e
  })
  return e
}

// one setting: save(widget, one("key", value))
function one(key, value) {
  var c = {}
  c[key] = value
  return c
}
