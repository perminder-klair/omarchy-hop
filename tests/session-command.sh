#!/bin/bash
#
# The remote command is quoted three deep — a login shell holding a tmux
# invocation holding a second login shell holding the startup script — so it is
# worth running rather than reading.
#
# The far side is simulated. `$SHELL` is a stub standing in for the remote login
# shell, because the real one sources /etc/profile and rebuilds PATH: useful in
# life, and the reason a test cannot hide tmux merely by emptying PATH. The stub
# takes its PATH from the test instead, so both "tmux is there" and "tmux is
# not" are decided here rather than by the machine the suite runs on.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HOP="$ROOT/bin/hop"
SCRATCH=$(mktemp -d)

cleanup() {
  rm -rf -- "$SCRATCH"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$SCRATCH/bin" "$SCRATCH/empty" "$SCRATCH/home" "$SCRATCH/work" \
  "$SCRATCH/marks"

# The startup script spans lines, so the record is NUL-separated.
cat >"$SCRATCH/bin/tmux" <<STUB
#!/bin/bash
printf '%s\0' "\$@" >"$SCRATCH/marks/tmux-argv"
STUB

cat >"$SCRATCH/bin/login-shell" <<'STUB'
#!/bin/bash
export PATH="${FAR_PATH:-}"
case "${1:-}" in
-lc) exec /bin/bash -c "$2" ;;
-l) exec /bin/bash ;;
*) exec /bin/bash "$@" ;;
esac
STUB
chmod +x "$SCRATCH/bin/tmux" "$SCRATCH/bin/login-shell"

hop() {
  env HOP_CONFIG_DIR="$SCRATCH/config" "$HOP" "$@"
}

# Quotes, spaces and a variable the far side has to expand itself.
INIT=$(cat <<INIT_SCRIPT
printf "it 'ran' \$USER\n" >"$SCRATCH/marks/init"
pwd >"$SCRATCH/marks/cwd"
INIT_SCRIPT
)

remote_command() {
  local argv=()
  eval "argv=( $(hop command "$1") )"
  printf '%s' "${argv[-1]}"
}

# $2 is run the way the far side would run it, with tmux reachable only when
# $1 says so.
run_remote() {
  local far_path="$1" body="$2"
  rm -f "$SCRATCH/marks/init" "$SCRATCH/marks/cwd" "$SCRATCH/marks/tmux-argv"
  env -i HOME="$SCRATCH/home" USER=tester FAR_PATH="$far_path" \
    SHELL="$SCRATCH/bin/login-shell" PATH="$far_path" \
    /bin/bash -c "$body" </dev/null
}

id=$(hop add --host box --path "$SCRATCH/work" --init "$INIT" --persist)

# ---- with tmux on the far side ---------------------------------------------

run_remote "$SCRATCH/bin" "$(remote_command "$id")"

[[ -f $SCRATCH/marks/tmux-argv ]] || fail "tmux was never reached"
mapfile -d '' -t targv <"$SCRATCH/marks/tmux-argv"

[[ ${targv[0]} == "new-session" ]] || fail "not a new-session: ${targv[0]}"
printf '%s\n' "${targv[@]}" | grep -qx -- "-A" \
  || fail "lost -A, so an existing session would not be reused"
printf '%s\n' "${targv[@]}" | grep -qx -- "-D" \
  || fail "lost -D, so a client stranded by a dead terminal keeps the session"

session=""
for i in "${!targv[@]}"; do
  [[ ${targv[$i]} == "-s" ]] && session="${targv[$((i + 1))]}"
done
[[ $session == "hop-$id" ]] \
  || fail "session is not named for the machine: $session"
[[ ! -f $SCRATCH/marks/init ]] \
  || fail "the startup script also ran outside tmux"

# What tmux was handed, run the way tmux runs it: one argument to a shell.
run_remote "$SCRATCH/bin" "${targv[-1]}"
[[ -f $SCRATCH/marks/init ]] || fail "the startup script never ran inside tmux"
[[ $(cat "$SCRATCH/marks/init") == "it 'ran' tester" ]] \
  || fail "the startup script arrived mangled: $(cat "$SCRATCH/marks/init")"
[[ $(cat "$SCRATCH/marks/cwd") == "$SCRATCH/work" ]] \
  || fail "the session did not start in the machine's path"

# ---- without tmux on the far side ------------------------------------------

run_remote "$SCRATCH/empty" "$(remote_command "$id")"
[[ -f $SCRATCH/marks/init ]] \
  || fail "no fallback session without tmux on the far side"
[[ ! -f $SCRATCH/marks/tmux-argv ]] || fail "tmux ran despite being absent"

# ---- persistence is opt-in --------------------------------------------------

plain=$(hop add --host box --path "$SCRATCH/work" --init "$INIT")
remote_command "$plain" | grep -q tmux \
  && fail "a machine without --persist was wrapped in tmux"
run_remote "$SCRATCH/bin" "$(remote_command "$plain")"
[[ -f $SCRATCH/marks/init ]] || fail "the plain session lost its startup script"
[[ ! -f $SCRATCH/marks/tmux-argv ]] || fail "a plain session reached tmux"

# A machine with nothing to run still has to reach tmux, where before there was
# no remote command at all.
bare=$(hop add --host box --persist)
run_remote "$SCRATCH/bin" "$(remote_command "$bare")"
[[ -f $SCRATCH/marks/tmux-argv ]] \
  || fail "a machine with no startup script was not persisted"

# --no-persist puts it back.
hop set "$id" --no-persist
remote_command "$id" | grep -q tmux && fail "--no-persist left the tmux wrapper"

echo "PASS: sessions persist in tmux and reattach"
