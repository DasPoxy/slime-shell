.pragma library
// Fuzzy matching for the Slime launcher: every query character must appear in
// order; matches score higher at the start of the text, at word starts, and in
// consecutive runs. Returns -1 for no match.

function isBoundary(ch) { return ch === " " || ch === "-" || ch === "_" || ch === "." || ch === "/" || ch === "›" }

function score(query, text) {
  var q = String(query || "").toLowerCase().replace(/\s+/g, "")
  var t = String(text || "").toLowerCase()
  if (q === "") return 0
  if (t === "") return -1
  var s = 0, ti = 0, run = 0, first = -1
  for (var qi = 0; qi < q.length; qi++) {
    var ch = q[qi], found = -1
    // prefer the next occurrence at a word boundary within reach, else the next one
    for (var k = ti; k < t.length; k++) {
      if (t[k] !== ch) continue
      if (found < 0) found = k
      if (k === 0 || isBoundary(t[k - 1])) { found = k; break }
      if (k - ti > 12) break
    }
    if (found < 0) return -1
    if (first < 0) first = found
    var boundary = found === 0 || isBoundary(t[found - 1])
    run = found === ti && qi > 0 ? run + 1 : 0
    s += 1 + (boundary ? 6 : 0) + run * 4 - Math.min(3, (found - ti) * 0.3)
    ti = found + 1
  }
  if (t.indexOf(q) === 0) s += 15
  else if (t.indexOf(q) > 0) s += 6
  return s - first * 0.2 - t.length * 0.02
}

// Best score over several fields, the first weighted fully, the rest less.
function best(query, fields) {
  var top = -1
  for (var i = 0; i < fields.length; i++) {
    var v = score(query, fields[i])
    if (v < 0) continue
    v = i === 0 ? v : v * 0.6
    if (v > top) top = v
  }
  return top
}
