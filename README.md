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

## Remove

```bash
omarchy plugin disable io.github.labrat-0.omasift
omarchy plugin remove io.github.labrat-0.omasift
```

That deletes the checkout and the bar entry. The cached catalog is the only
thing left outside the plugin directory, so remove it too if you want nothing
behind:

```bash
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/omasift"
```

## Keys

| Key | Action |
|---|---|
| type | search name, id, tags, author, description |
| <kbd>↑</kbd> <kbd>↓</kbd> | move · <kbd>PgUp</kbd>/<kbd>PgDn</kbd> jump · <kbd>Home</kbd>/<kbd>End</kbd> ends |
| <kbd>Tab</kbd> | cycle review state (<kbd>Shift</kbd>+<kbd>Tab</kbd> back) |
| <kbd>←</kbd> <kbd>→</kbd> | cycle category |
| <kbd>F2</kbd> | cycle sort — stars (default), relevance, updated, added, name |
| <kbd>Enter</kbd> | copy the install command |
| <kbd>Shift</kbd>+<kbd>Enter</kbd> | copy the repo URL |
| <kbd>Alt</kbd>+<kbd>Enter</kbd> | open the repo in a browser |
| <kbd>F5</kbd> | refresh the catalog |
| <kbd>Esc</kbd> | clear the search, then close |

Every letter you press goes into the search box, so the filters use keys you
cannot type: <kbd>Tab</kbd>, the arrows, and the function keys. No modifier
chords.

The footer chips are also buttons — left-click one to step it forward,
right-click to step back.

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

## How it works

`bin/omasift-fetch` downloads the marketplace's published `site/catalog.json`
(~5 MB), reduces it to the ~1.3 MB the UI needs, and writes it atomically to
`$XDG_STATE_HOME/omasift/catalog.json`, owner-readable. The shell only ever
parses the reduced file — a 5 MB JSON parse does not belong in the process that
draws your desktop.

`bin/omasift-doctor` checks the dependencies and reports catalog freshness.

Nothing is sent anywhere. The only network request is a GET for the public
catalog over HTTPS.

### On the security of this plugin

Plugins run unsandboxed inside `omarchy-shell`, so it is fair to ask what this
one actually does:

- **No shell strings are ever composed.** The two commands it can run —
  `wl-copy` and `xdg-open` — go through `Util.execArgv`, which passes arguments
  as positional parameters so catalog text stays literal.
- **It never installs anything.** <kbd>Enter</kbd> copies a command for you to
  read and run yourself. There is no `sudo`, no package manager, no `systemctl`,
  and no privileged helper.
- **The download is data, never code.** `bin/omasift-fetch` is pure Python with
  no shell and no `curl`. It refuses a non-HTTPS URL, caps the response, parses
  it as JSON, and writes only the reduced result. Nothing downloaded is ever
  written somewhere a later command executes.
- **URLs are checked before they reach a handler.** Any repo URL that is not
  `https://` is dropped at fetch time and refused again before `xdg-open`.
- **No binaries, no symlinks, no post-install hooks.**

## Requirements

External dependencies, all standard on Omarchy:

| Dependency | Used for |
|---|---|
| `python3` | fetching and reducing the catalog |
| `wl-copy` (wl-clipboard) | copying the install command and repo URL |
| `xdg-open` (xdg-utils) | opening a repo in your browser (optional) |

Run `bin/omasift-doctor` to check them.

## License

MIT
