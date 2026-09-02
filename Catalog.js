.pragma library

// Pure catalog logic: parsing, filtering, ranking, and the small bits of
// formatting the surfaces share. No side effects and no QML types, so this
// stays testable with a plain JS runtime.

// Limits mirrored from bin/omasift-fetch. The helper already enforces every one
// of these, but the shell must not trust a file on disk any more than the helper
// trusts the network — a cache written by something else still has to land
// inside these bounds before any of it reaches a delegate. Keep the two lists in
// step when either moves.
var LIMITS = {
  raw: 12 * 1024 * 1024,     // largest serialised index worth parsing at all
  plugins: 4000,
  tags: 24,
  id: 200, name: 200, desc: 500, author: 200, cat: 80, tag: 60,
  kind: 80, status: 80, repo: 500, ver: 80, cov: 80, license: 80,
  install: 400, note: 500, date: 10, stamp: 32,
  stars: 100000000,
  query: 128,                // characters taken from the search field
  terms: 12                  // terms actually scored
}

var SORTS = ["relevance", "stars", "updated", "added", "name"]

var TRUST = { verified: 1, stale: 1, unreviewed: 1, builtin: 1 }

// C0/C1 controls plus the zero-width and bidi characters that let a downloaded
// name reorder the text drawn around it.
var UNSAFE = /[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069\ufeff]/g
var ID_OK = /^[A-Za-z0-9][A-Za-z0-9._:+-]{0,199}$/
var DATE_OK = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/
// The same origin and owner/name path shape bin/omasift-fetch canonicalises to.
var REPO_OK = /^https:\/\/github\.com\/[A-Za-z0-9][A-Za-z0-9._-]{0,99}\/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$/

// --------------------------------------------------------------- validation

// Bound first, then scrub: never run a per-character pass over a hostile string
// before its length is capped.
function bounded(value, limit) {
  if (typeof value !== "string") return ""
  return value.slice(0, limit).replace(UNSAFE, " ").trim()
}

function counted(value, limit) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return 0
  n = Math.floor(n)
  return n > limit ? limit : n
}

function cleanRepo(value) {
  var s = bounded(value, LIMITS.repo)
  return REPO_OK.test(s) ? s : ""
}

function cleanDate(value) {
  var s = bounded(value, LIMITS.date)
  return DATE_OK.test(s) ? s : ""
}

function cleanRow(row) {
  if (!row || typeof row !== "object") return null

  // Checked before the cap is applied: truncating an over-long id would let two
  // distinct listings collapse onto one identity.
  var id = row.id
  if (typeof id !== "string" || id.length > LIMITS.id) return null
  id = bounded(id, LIMITS.id)
  if (!ID_OK.test(id)) return null

  var tags = []
  if (Array.isArray(row.tags)) {
    for (var i = 0; i < row.tags.length && tags.length < LIMITS.tags; i++) {
      var tag = bounded(row.tags[i], LIMITS.tag)
      if (tag) tags.push(tag)
    }
  }

  return {
    id: id,
    name: bounded(row.name, LIMITS.name) || id,
    desc: bounded(row.desc, LIMITS.desc),
    author: bounded(row.author, LIMITS.author),
    cat: bounded(row.cat, LIMITS.cat),
    tags: tags,
    kind: bounded(row.kind, LIMITS.kind),
    status: bounded(row.status, LIMITS.status),
    repo: cleanRepo(row.repo),
    ver: bounded(row.ver, LIMITS.ver),
    trust: TRUST[row.trust] === 1 ? row.trust : "unreviewed",
    cov: bounded(row.cov, LIMITS.cov),
    stars: counted(row.stars, LIMITS.stars),
    license: bounded(row.license, LIMITS.license),
    install: bounded(row.install, LIMITS.install),
    note: bounded(row.note, LIMITS.note),
    added: cleanDate(row.added),
    updated: cleanDate(row.updated)
  }
}

function parseIndex(raw) {
  if (typeof raw !== "string" || !raw) return emptyIndex()
  if (raw.length > LIMITS.raw) return emptyIndex()

  var doc
  try { doc = JSON.parse(raw) } catch (e) { return emptyIndex() }
  if (!doc || doc.v !== 1 || !Array.isArray(doc.plugins)) return emptyIndex()

  // Null-prototype: a listing whose id is "__proto__" would otherwise write the
  // object's prototype instead of a key.
  var seen = Object.create(null)
  var rows = []
  var limit = Math.min(doc.plugins.length, LIMITS.plugins)
  for (var i = 0; i < limit; i++) {
    var row = cleanRow(doc.plugins[i])
    if (!row || seen[row.id] === 1) continue
    seen[row.id] = 1
    rows.push(row)
  }

  return {
    ok: true,
    fetchedAt: bounded(doc.fetchedAt, LIMITS.stamp),
    generatedAt: cleanDate(doc.generatedAt),
    count: rows.length,
    plugins: rows
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
  var seen = Object.create(null)
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
  var seen = Object.create(null)
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

// The query is scored against every record on every keystroke, so both its
// length and the number of terms are bounded before any of that starts.
function terms(query) {
  if (typeof query !== "string") return []
  var raw = query.slice(0, LIMITS.query).replace(UNSAFE, " ").toLowerCase().trim()
  if (!raw) return []
  var parts = raw.split(/\s+/)
  var out = []
  for (var i = 0; i < parts.length && out.length < LIMITS.terms; i++) {
    if (parts[i].length > 0) out.push(parts[i])
  }
  return out
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
