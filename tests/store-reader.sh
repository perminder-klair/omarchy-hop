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

printf 'store reader tests passed\n'
