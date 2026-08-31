.pragma library

// Pure catalog logic: parsing, filtering, ranking, and the small bits of
// formatting the surfaces share. No side effects and no QML types, so this
// stays testable with a plain JS runtime.

var SORTS = ["relevance", "stars", "updated", "added", "name"]

function parseIndex(raw) {
  if (!raw) return emptyIndex()
  try {
    var doc = JSON.parse(raw)
    if (!doc || doc.v !== 1 || !Array.isArray(doc.plugins)) return emptyIndex()
    return {
      ok: true,
      fetchedAt: String(doc.fetchedAt || ""),
      generatedAt: String(doc.generatedAt || ""),
      count: doc.plugins.length,
      plugins: doc.plugins
    }
  } catch (e) {
    return emptyIndex()
  }
}

function emptyIndex() {
  return { ok: false, fetchedAt: "", generatedAt: "", count: 0, plugins: [] }
}

// --------------------------------------------------------------- statistics

function summarize(plugins) {
  var s = { total: 0, verified: 0, stale: 0, unreviewed: 0, builtin: 0,
            manual: 0, unstarred: 0 }
  for (var i = 0; i < plugins.length; i++) {
    var p = plugins[i]
    s.total += 1
    if (s[p.trust] !== undefined) s[p.trust] += 1
    if (p.status === "Manual setup") s.manual += 1
    if (!p.stars) s.unstarred += 1
  }
  return s
}

function categories(plugins) {
  var seen = {}
  for (var i = 0; i < plugins.length; i++) {
    var c = plugins[i].cat
    if (c) seen[c] = (seen[c] || 0) + 1
  }
  var out = []
  for (var k in seen) out.push({ name: k, count: seen[k] })
  out.sort(function (a, b) { return b.count - a.count })
  return out
}

function kinds(plugins) {
  var seen = {}
  for (var i = 0; i < plugins.length; i++) {
    var k = plugins[i].kind
    if (k) seen[k] = (seen[k] || 0) + 1
  }
  var out = []
  for (var key in seen) out.push({ name: key, count: seen[key] })
  out.sort(function (a, b) { return b.count - a.count })
  return out
}

// ------------------------------------------------------------------ search

// Terms are ANDed: every term must land somewhere in the record. Within a
// record the best field a term hits sets its weight, so a name match ranks
// above the same word buried in a description.
function score(plugin, terms) {
  if (terms.length === 0) return 1

  var name = (plugin.name || "").toLowerCase()
  var id = (plugin.id || "").toLowerCase()
  var author = (plugin.author || "").toLowerCase()
  var desc = (plugin.desc || "").toLowerCase()
  var tags = (plugin.tags || []).join(" ").toLowerCase()
  var cat = (plugin.cat || "").toLowerCase()

  var total = 0
  for (var i = 0; i < terms.length; i++) {
    var t = terms[i]
    var best = 0
    if (name === t) best = 120
    else if (name.indexOf(t) === 0) best = 90
    else if (name.indexOf(t) !== -1) best = 60
    else if (id.indexOf(t) !== -1) best = 45
    else if (tags.indexOf(t) !== -1) best = 35
    else if (cat.indexOf(t) !== -1) best = 25
    else if (author.indexOf(t) !== -1) best = 20
    else if (desc.indexOf(t) !== -1) best = 12
    if (best === 0) return 0      // every term has to match something
    total += best
  }
  return total
}

function terms(query) {
  var raw = String(query || "").toLowerCase().trim()
  if (!raw) return []
  return raw.split(/\s+/).filter(function (t) { return t.length > 0 })
}

function matchesFilters(p, f) {
  if (f.category && p.cat !== f.category) return false
  if (f.kind && p.kind !== f.kind) return false
  if (f.trust && p.trust !== f.trust) return false
  if (f.installableOnly && p.status === "Manual setup") return false
  return true
}

function search(plugins, query, filters, sort) {
  var ts = terms(query)
  var f = filters || {}
  var out = []

  for (var i = 0; i < plugins.length; i++) {
    var p = plugins[i]
    if (!matchesFilters(p, f)) continue
    var s = score(p, ts)
    if (s === 0) continue
    out.push({ p: p, s: s })
  }

  var mode = sort || "relevance"
  // With no query every relevance score is the flat 1 from `score`, which
  // would leave the list in whatever order the index happened to arrive in.
  // Fall back to stars so an empty search still opens on something useful.
  if (mode === "relevance" && ts.length === 0) mode = "stars"

  out.sort(function (a, b) {
    switch (mode) {
    case "stars":
      if (b.p.stars !== a.p.stars) return b.p.stars - a.p.stars
      break
    case "updated":
      if (b.p.updated !== a.p.updated) return b.p.updated < a.p.updated ? -1 : 1
      break
    case "added":
      if (b.p.added !== a.p.added) return b.p.added < a.p.added ? -1 : 1
      break
    case "name":
      break
    default:
      if (b.s !== a.s) return b.s - a.s
      if (b.p.stars !== a.p.stars) return b.p.stars - a.p.stars
      break
    }
    return a.p.name.toLowerCase() < b.p.name.toLowerCase() ? -1 : 1
  })

  var plain = []
  for (var j = 0; j < out.length; j++) plain.push(out[j].p)
  return plain
}

// --------------------------------------------------------------- formatting

function repoLabel(repo) {
  var s = String(repo || "")
  return s.replace(/^https?:\/\/(www\.)?github\.com\//, "").replace(/\.git$/, "")
}

function starLabel(n) {
  var v = Number(n) || 0
  if (v >= 1000) return (v / 1000).toFixed(1).replace(/\.0$/, "") + "k"
  return String(v)
}

// The one signal the marketplace site does not put in front of you: the
// listing was reviewed at one commit, and install clones HEAD.
function trustLabel(p) {
  if (!p) return ""
  switch (p.trust) {
  case "verified":   return "Verified"
  case "stale":      return "Verified, then moved"
  case "unreviewed": return "Never reviewed"
  case "builtin":    return "Built in"
  }
  return "Unknown"
}

// Row badges get the short form; the detail pane gets the sentence.
function trustShort(p) {
  if (!p) return ""
  switch (p.trust) {
  case "verified":   return "verified"
  case "stale":      return "moved"
  case "unreviewed": return "unreviewed"
  case "builtin":    return "built in"
  }
  return ""
}

function trustNote(p) {
  if (!p) return ""
  switch (p.trust) {
  case "verified":
    return "Reviewed, and upstream has not moved since. Install gets the reviewed code."
  case "stale":
    return "Reviewed once, but upstream has moved on. Install clones the newer commit, which nobody has reviewed."
  case "unreviewed":
    return "Nobody has reviewed this. Read the source before you enable it."
  case "builtin":
    return "Ships with Omarchy."
  }
  return ""
}

function ageDays(iso, nowMs) {
  if (!iso) return -1
  var t = Date.parse(iso + "T00:00:00Z")
  if (isNaN(t)) return -1
  return Math.floor((nowMs - t) / 86400000)
}

function ageLabel(iso, nowMs) {
  var d = ageDays(iso, nowMs)
  if (d < 0) return "unknown"
  if (d === 0) return "today"
  if (d === 1) return "yesterday"
  if (d < 30) return d + "d ago"
  if (d < 365) return Math.floor(d / 30) + "mo ago"
  return Math.floor(d / 365) + "y ago"
}
