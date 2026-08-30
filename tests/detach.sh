#!/bin/bash
#
# The bar spawns `hop connect` as its own child and holds on to that pid. If
# the terminal ends up sharing it, the bar kills the session whenever it drops
# the handle: on a shell reload, on an Omarchy update, or on the next machine
# you open. `hop` must therefore fork before it hands off, and must be gone by
# the time the terminal is up.
#
# The launcher is stubbed so the assertion is about what hop guarantees on its
# own, not about the fork that `omarchy-launch-tui` happens to do further down.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HOP="$ROOT/bin/hop"
SCRATCH=$(mktemp -d)

cleanup() {
  if [[ -s $SCRATCH/pid ]]; then
    kill "$(cat "$SCRATCH/pid")" 2>/dev/null || true
  fi
  rm -rf -- "$SCRATCH"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$SCRATCH/bin"
for stub in omarchy-launch-tui nautilus; do
  cat >"$SCRATCH/bin/$stub" <<'STUB'
#!/bin/bash
echo "$PPID" >"$OUT/ppid"
echo "$$" >"$OUT/pid"
printf '%s\n' "$@" >"$OUT/argv"
sleep 30
STUB
  chmod +x "$SCRATCH/bin/$stub"
done

export HOP_CONFIG_DIR="$SCRATCH/config"
export OUT="$SCRATCH"
export PATH="$SCRATCH/bin:$PATH"

"$HOP" add --host example.invalid --name target >/dev/null

# `exec` so the pid recorded here is the pid hop itself runs as — the pid the
# bar would be holding.
run_detached() {
  rm -f "$SCRATCH/ppid" "$SCRATCH/pid" "$SCRATCH/argv" "$SCRATCH/runner"
  local status=0
  timeout 5 bash -c 'echo $$ >"$OUT/runner"; exec "$1" "$2" target' \
    _ "$HOP" "$1" || status=$?
  ((status != 124)) \
    || fail "$1: hop never returned, so the launcher is still running as hop"
  ((status == 0)) || fail "$1: hop exited $status"

  local waited=0
  while [[ ! -s $SCRATCH/ppid ]]; do
    ((waited++ < 40)) || fail "$1: the launcher never ran"
    sleep 0.1
  done
}

check_detached() {
  local what="$1" runner ppid pid
  runner=$(cat "$SCRATCH/runner")
  ppid=$(cat "$SCRATCH/ppid")
  pid=$(cat "$SCRATCH/pid")

  [[ $ppid != "$runner" ]] \
    || fail "$what runs as a child of hop, so the bar can kill it"
  kill -0 "$runner" 2>/dev/null \
    && fail "$what left hop's pid alive, so the bar still holds a handle"
  kill -0 "$pid" 2>/dev/null \
    || fail "$what did not outlive hop"
  kill "$pid" 2>/dev/null || true
}

run_detached connect
grep -qx -- "--app-id=org.omarchy.hop" "$SCRATCH/argv" \
  || fail "connect lost the app id"
grep -q "^ssh$" "$SCRATCH/argv" || fail "connect did not launch ssh"
check_detached "the terminal"

run_detached files
grep -q "^sftp://" "$SCRATCH/argv" || fail "files lost the sftp uri"
check_detached "the file manager"

echo "PASS: sessions are detached from the process that opened them"
