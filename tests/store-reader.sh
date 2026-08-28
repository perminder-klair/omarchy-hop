#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HOP="$ROOT/bin/hop"
SCRATCH=$(mktemp -d)
STORE="$SCRATCH/hosts.json"

cleanup() {
  rm -rf -- "$SCRATCH"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

clear_store() {
  if [[ -L $STORE || -f $STORE || -p $STORE ]]; then
    unlink "$STORE"
  elif [[ -d $STORE ]]; then
    rmdir "$STORE"
  fi
}

expect_rejected_without_blocking() {
  local case_name="$1" status
  set +e
  timeout 2s env HOP_CONFIG_DIR="$SCRATCH" "$HOP" list \
    >"$SCRATCH/stdout" 2>"$SCRATCH/stderr"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "$case_name was accepted"
  [[ $status -ne 124 ]] || fail "$case_name blocked"
  [[ ! -s $SCRATCH/stdout ]] || fail "$case_name returned data"
}

# Missing is the normal initial state and must not create a file just to read.
[[ $(env HOP_CONFIG_DIR="$SCRATCH" "$HOP" list) == "[]" ]] \
  || fail "missing store did not return an empty list"
[[ ! -e $STORE ]] || fail "a read created the missing store"

# Ordinary mutations still round-trip through the hardened reader.
id=$(env HOP_CONFIG_DIR="$SCRATCH" "$HOP" add --host example.com --name Prod)
[[ -f $STORE && ! -L $STORE ]] || fail "add did not create a regular store"
[[ $(stat -c '%a' "$STORE") == "600" ]] || fail "store mode is not 0600"
[[ $(env HOP_CONFIG_DIR="$SCRATCH" "$HOP" list | jq -r '.[0].id') == "$id" ]] \
  || fail "added host did not round-trip"
env HOP_CONFIG_DIR="$SCRATCH" "$HOP" set "$id" --port 2222
[[ $(env HOP_CONFIG_DIR="$SCRATCH" "$HOP" show "$id" | jq -r '.port') == "2222" ]] \
  || fail "updated host did not round-trip"
env HOP_CONFIG_DIR="$SCRATCH" "$HOP" rm "$id"
[[ $(env HOP_CONFIG_DIR="$SCRATCH" "$HOP" list) == "[]" ]] \
  || fail "removed host remained in the store"

clear_store
mkfifo "$STORE"
expect_rejected_without_blocking "FIFO store"

clear_store
printf '{"version":1,"hosts":[]}\n' >"$SCRATCH/target.json"
ln -s "$SCRATCH/target.json" "$STORE"
expect_rejected_without_blocking "symlink store"

clear_store
mkdir "$STORE"
expect_rejected_without_blocking "directory store"

clear_store
truncate -s 1048577 "$STORE"
expect_rejected_without_blocking "oversized store"

clear_store
printf '{not json}\n' >"$STORE"
expect_rejected_without_blocking "malformed store"

# ---- validation of what a store may contain --------------------------------

hop() {
  env HOP_CONFIG_DIR="$SCRATCH" "$HOP" "$@"
}

write_hosts() {
  clear_store
  printf '{"version":1,"hosts":%s}\n' "$1" >"$STORE"
}

# A hostile entry is dropped, and the machines beside it survive.
expect_dropped() {
  local case_name="$1" entry="$2" out
  write_hosts "[$entry,{\"id\":\"good\",\"host\":\"example.com\",\"name\":\"Good\"}]"
  out=$(hop list 2>/dev/null)
  [[ $(jq -r 'length' <<<"$out") == "1" ]] || fail "$case_name was not dropped"
  [[ $(jq -r '.[0].id' <<<"$out") == "good" ]] || fail "$case_name took the good entry with it"
}

expect_dropped "dash host" '{"id":"e","host":"-oProxyCommand=touch /tmp/hop-pwn"}'
expect_dropped "dash user" '{"id":"e","host":"example.com","user":"-oProxyCommand=x"}'
expect_dropped "shell metacharacter id" '{"id":"$(touch /tmp/hop-pwn)","host":"example.com"}'
expect_dropped "non-integer port" '{"id":"e","host":"example.com","port":"22 -oX"}'
expect_dropped "out-of-range port" '{"id":"e","host":"example.com","port":70000}'
expect_dropped "boolean port" '{"id":"e","host":"example.com","port":true}'
expect_dropped "non-string name" '{"id":"e","host":"example.com","name":{}}'
expect_dropped "newline in name" '{"id":"e","host":"example.com","name":"a\nb"}'
expect_dropped "entry that is not an object" '"not an object"'

# Only the known keys reach the shell, whatever else the file carries.
write_hosts '[{"id":"good","host":"example.com","name":"Good","surprise":"extra"}]'
[[ $(hop list | jq -r '.[0] | keys_unsorted | join(",")') \
  == "id,name,host,user,port,identity,path,init,forwardAgent" ]] \
  || fail "unexpected keys reached the shell"

# An over-long field is a dropped entry, not a truncated one.
long=$(python3 -c 'print("a" * 200)')
expect_dropped "over-long name" "{\"id\":\"e\",\"host\":\"example.com\",\"name\":\"$long\"}"

# The host count is capped for the whole store rather than per entry.
python3 - "$STORE" <<'PY_STORE'
import json, sys
hosts = [
    {"id": f"h{i}", "host": "example.com", "name": f"m{i}"}
    for i in range(300)
]
with open(sys.argv[1], "w") as handle:
    json.dump({"version": 1, "hosts": hosts}, handle)
PY_STORE
expect_rejected_without_blocking "oversized host count"

# Writes are held to the same rules, so nothing unreadable is ever stored.
clear_store
set +e
hop add --host example.com --port 99999 >/dev/null 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail "an out-of-range port was accepted"
[[ ! -e $STORE ]] || fail "a rejected write created a store"

clear_store
set +e
hop add --host "-oProxyCommand=touch /tmp/hop-pwn" >/dev/null 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail "an option-shaped host was accepted"
[[ ! -e $STORE ]] || fail "a rejected write created a store"

# Nothing above may have run anything.
[[ ! -e /tmp/hop-pwn ]] || fail "a store value executed"

# A machine that survives validation still produces the ssh command it should.
clear_store
id=$(hop add --host example.com --name Prod --user deploy --port 2222)
[[ $(hop command "$id") == "ssh -t -p 2222 deploy@example.com "* ]] \
  || fail "a valid machine did not produce its ssh command"

printf 'store reader tests passed\n'
