# OmaSift

Search the Omarchy plugin marketplace from inside the shell, and see what has
actually been reviewed before you install it.

The marketplace has grown past the point where it can be browsed. OmaSift is a
fullscreen, keyboard-first finder over every listing, and it puts one thing in
front of you that a verified/unverified badge hides.

## The review states

The marketplace verifies a listing at a specific commit. `omarchy plugin add`
clones whatever upstream HEAD is now. Those are not always the same commit, and
a single "unverified" badge lumps together two very different situations:

| State | Meaning | Today |
|---|---|---|
| **Verified** | Reviewed, and upstream has not moved since. Install gets the reviewed code. | 1,346 |
| **Verified, then moved** | Reviewed once, but upstream has moved on. Install clones a newer commit nobody reviewed. | 387 |
| **Never reviewed** | Nobody has looked at this. | 226 |

Press <kbd>Tab</kbd> to filter by review state. Searching `bluetooth` returns
eight plugins; filtering to verified-only leaves one.

The list opens sorted by stars, most-starred first. The footer shows each
filter next to the key that cycles it, and lights that key up while it is
holding something back.

## Install

```bash
omarchy plugin add https://github.com/labrat-0/omarchy-omasift.git
omarchy plugin enable io.github.labrat-0.omasift --section right
```

Click the bar pill, or:

```bash
omarchy-shell shell toggle io.github.labrat-0.omasift '{}'
```

## Keys

| Key | Action |
|---|---|
| type | search name, id, tags, author, description |
| <kbd>↑</kbd> <kbd>↓</kbd> | move · <kbd>PgUp</kbd>/<kbd>PgDn</kbd> jump · <kbd>Home</kbd>/<kbd>End</kbd> ends |
| <kbd>Enter</kbd> | copy the install command |
| <kbd>Shift</kbd>+<kbd>Enter</kbd> | copy the repo URL |
| <kbd>Alt</kbd>+<kbd>Enter</kbd> | open the repo in a browser |
| <kbd>Tab</kbd> | cycle review state |
| <kbd>Ctrl</kbd>+<kbd>G</kbd> | cycle category |
| <kbd>Ctrl</kbd>+<kbd>S</kbd> | cycle sort — stars (default), relevance, updated, added, name |
| <kbd>Ctrl</kbd>+<kbd>R</kbd> | refresh the catalog |
| <kbd>Esc</kbd> | clear the search, then close |

## It copies, it does not install

<kbd>Enter</kbd> puts the install command on your clipboard. It does not run it.

`omarchy plugin add` already does that job properly: it warns you, shows you the
source, and lands the plugin disabled so you can read it before enabling. A
browser that shelled out to a package manager would also have to declare the
`installer` and `package-manager` capabilities — the same capabilities this
plugin exists to help you notice in other people's code.

## Settings

Set per bar-widget instance in `shell.json`, or through Setup › Plugins.

| Key | Default | Meaning |
|---|---|---|
| `refreshHours` | `24` | how often to refetch the catalog |
| `showCount` | `true` | show the listing count next to the bar icon |

## How it works

`bin/omasift-fetch` downloads the marketplace's published `site/catalog.json`
(~5 MB) with a bounded `curl`, reduces it to the ~1.3 MB the UI needs, and
writes it atomically to `$XDG_STATE_HOME/omasift/catalog.json`. The shell only
ever parses the reduced file — a 5 MB JSON parse does not belong in the process
that draws your desktop.

`bin/omasift-doctor` checks the dependencies and reports catalog freshness.

Nothing is sent anywhere. The only network request is a GET for the public
catalog.

## Requirements

`curl`, `python3`, `wl-copy` (wl-clipboard), and `xdg-open` for opening repos.

## License

MIT
