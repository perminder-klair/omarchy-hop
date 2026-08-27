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
| `Service.qml` | The machine list, the store poll, the `hop` IPC target. |
| `BarWidget.qml` | The bar icon and the panel loader. |
| `Panel.qml` | List mode and the add/edit form. |
| `bin/hop` | Every read, write and launch. |

The QML never touches the store or builds an `ssh` command itself — it shells
out to `bin/hop`. That way the panel, a keybinding and a terminal all mutate
the same file the same way, and the long-lived shell process is not the
authority on what a valid entry looks like. Add behaviour to `bin/hop` first,
then expose it in the panel.

## Before opening a pull request

```bash
bash -n bin/hop
omarchy plugin validate .
```

`omarchy plugin validate` runs the same checks the shell does at load time:
schema version, required fields, entry points that exist, and no symlinks
inside the plugin folder.

## Things worth knowing

- **The store is rewritten by atomic rename.** A `FileView` watcher alone
  misses those, because the rename swaps out the inode it is holding — hence
  the poll in `Service.qml` alongside the watcher.
- **ssh runs remote commands in a non-login, non-interactive shell.** Startup
  scripts go through `$SHELL -lc` for this reason; see the comment in
  `ssh_argv`.
- **No credentials, ever.** Sessions get a real tty in the user's own terminal
  so ssh can prompt there. Please do not add a password field.
