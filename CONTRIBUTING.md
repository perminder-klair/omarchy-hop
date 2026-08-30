# Contributing

## Working on it locally

Clone the repository wherever you keep your projects, then symlink it into
Omarchy's plugin directory so the shell loads your working copy:

```bash
ln -s ~/Projects/hop ~/.config/omarchy/plugins/co.klair.hop
omarchy-shell shell rescanPlugins
omarchy plugin enable co.klair.hop right
```

Saving a file under `~/.config/omarchy/plugins/` hot-reloads the plugin code.
An already-loaded panel instance is **not** rebuilt, though, so run
`omarchy-restart-shell` after changing `Panel.qml` — otherwise you will be
looking at the old panel and wondering why your edit did nothing.

## How it fits together

| File | What it owns |
|------|--------------|
| `manifest.json` | Plugin id, kinds, bar-widget metadata. |
| `Service.qml` | The machine list, the bounded store poll, the `hop` IPC target. |
| `BarWidget.qml` | The bar icon and the panel loader. |
| `Panel.qml` | List mode and the add/edit form. |
| `bin/hop` | Every store operation and launch. |
| `bin/hop-read-store` | Descriptor-safe, size-capped, field-validated store reads. |

The QML never touches the store or builds an `ssh` command itself — it shells
out to `bin/hop`. That way the panel, a keybinding and a terminal all mutate
the same file the same way, and the long-lived shell process is not the
authority on what a valid entry looks like. Add behaviour to `bin/hop` first,
then expose it in the panel.

## Before opening a pull request

```bash
bash -n bin/hop
bash tests/store-reader.sh
bash tests/detach.sh
omarchy plugin validate .
```

`omarchy plugin validate` runs the same checks the shell does at load time:
schema version, required fields, entry points that exist, and no symlinks
inside the plugin folder.

## Things worth knowing

- **Sessions are detached before they are handed off.** The bar spawns
  `hop connect` as its own child and keeps a handle on that pid. `setsid`
  alone does not break the link — it forks only when it is already a process
  group leader, which a child of the bar is not — so `bin/hop` forks
  explicitly through `detach()`. Without it the terminal inherits hop's pid
  and the bar takes your session down on the next reload, update, or machine
  you open. `tests/detach.sh` guards this.

- **The store is rewritten by atomic rename.** `Service.qml` deliberately
  polls through `bin/hop`; it never opens or watches the predictable path.
  `bin/hop-read-store` opens with `O_NONBLOCK | O_NOFOLLOW`, validates the
  held descriptor with `fstat`, and caps input and parsed output at one MiB.
- **The store is untrusted content, not just an untrusted shape.** Any process
  running as the user can replace that file, so `bin/hop-read-store` caps the
  machine count and checks every field for type, length and range before the
  shell sees it; a malformed entry is dropped on read and refused on write
  (`--check`). A host or user beginning with `-` is rejected outright, because
  `ssh` has no `--` and would read one as an option. Add a field to the
  validator in the same change that adds it to the store.
- **Nothing store-derived is spliced into a string a parser will read.** QML
  `Text` elements showing store data set `Text.PlainText`, and the one place
  that needs a shell pipeline passes its values as argv (`"$0"`, `"$1"`) rather
  than interpolating them into the script.
- **ssh runs remote commands in a non-login, non-interactive shell.** Startup
  scripts go through `$SHELL -lc` for this reason; see the comment in
  `ssh_argv`.
- **No credentials, ever.** Sessions get a real tty in the user's own terminal
  so ssh can prompt there. Please do not add a password field.
