# Omassh

Your SSH machines, in the Omarchy bar. Pick one and it opens in your default
terminal, runs the startup script you gave it, and leaves you at a prompt.

## What it does

- A bar icon listing every machine you have saved.
- Click one and `ssh` runs in the terminal `xdg-terminal-exec` would pick —
  the same one every other Omarchy launcher uses.
- Each machine can carry a **startup script**: a shell snippet that runs the
  moment you arrive (`cd /srv/app && docker compose ps`, `tmux attach`,
  whatever). When it finishes you are dropped into a normal login shell
  rather than disconnected.
- Adding, editing and removing machines happens in the panel, or from the
  `omassh` CLI, or by editing one JSON file.

## What it deliberately does not do

**It never stores a password.** The terminal it opens gets a real tty, so ssh
prompts you there exactly as it would if you had typed the command yourself.
That keeps keys, agents, `ProxyJump`, `Match` blocks and everything else in
`~/.ssh/config` working, and it means this plugin has no secret to leak — the
machine list is just hostnames.

If you want passwordless logins, the answer is `ssh-copy-id`, not a plugin
holding your password inside a long-lived desktop process.

## Install

```bash
omarchy plugin add https://github.com/<you>/omassh.git --enable
```

Or, working on it locally:

```bash
git clone https://github.com/<you>/omassh.git ~/Projects/omassh
ln -s ~/Projects/omassh ~/.config/omarchy/plugins/co.klair.omassh
omarchy-shell shell rescanPlugins
omarchy plugin enable co.klair.omassh right
```

## Using it

Click the 󰒋 icon in the bar. **Add machine** opens the form:

| Field | Notes |
|-------|-------|
| Name | What the bar shows. Defaults to the host. |
| Host | Hostname, IP, or a `Host` alias from `~/.ssh/config`. |
| User | Leave empty to let `ssh_config` decide. |
| Port | 22 unless you say otherwise. |
| Identity file | Optional `-i`. `~` is expanded. |
| Startup script | Runs on arrival, then hands you a login shell. |
| Forward ssh agent | `-A`. Off by default — only turn it on for machines you trust. |

In the list, the pencil edits a machine and the second icon copies the exact
`ssh` command to your clipboard.

## From the terminal

Everything the panel does goes through `bin/omassh`, so it is all available
without the bar:

```bash
omassh list
omassh add --host 10.0.0.5 --name "Prod web" --user deploy --init 'cd /srv/app'
omassh set <id> --port 2222
omassh connect "Prod web"      # opens a terminal, same as clicking
omassh command "Prod web"      # prints the ssh command instead of running it
omassh rm "Prod web"
```

`--init-file some-script.sh` is there for startup scripts long enough that you
would rather keep them in a file.

## From a keybinding

The shell exposes an IPC target, so a machine is one hotkey away:

```
bindd = SUPER SHIFT, S, Prod web, exec, omarchy-shell omassh connect "Prod web"
```

## Window rules

Sessions launch with app-id `org.omarchy.omassh`, so Hyprland can treat them
differently from an ordinary terminal:

```
windowrule = workspace 4, class:^(org\.omarchy\.omassh)$
```

## Where things live

| Path | What |
|------|------|
| `~/.config/omassh/hosts.json` | The machine list. Plain JSON, safe to edit or sync. |
| `bin/omassh` | The CLI the panel drives. |

The store holds no secrets, but it is created `0600` inside a `0700`
directory anyway — a list of which machines you have and who you log in as is
not something to hand out either.

## License

MIT.
