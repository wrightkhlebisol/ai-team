#!/usr/bin/env bash
# heavy.sh: run a heavy command (full test suite, native build, simulator UI
# run) only when one of a few machine-wide slots is free, so parallel agents
# queue instead of all running it at once.
#
# Usage:
#   heavy.sh [--slots N] [--name POOL] [--timeout SECS] -- COMMAND [ARGS...]
#
#   --slots    concurrent runs allowed in this pool (default $AI_TEAM_HEAVY_SLOTS or 1)
#   --name     pool name; commands in different pools don't block each other
#              (default "heavy"; e.g. "build" for xcodebuild/gradle)
#   --timeout  give up waiting after SECS (default 3600); exit code 75
#
# A slot whose owner process is gone is reclaimed, so a killed agent never
# leaves the pool locked. Prints a line when it waits and when it starts.
set -euo pipefail

slots="${AI_TEAM_HEAVY_SLOTS:-1}"
name="heavy"
timeout=3600
while [ $# -gt 0 ]; do
  case "$1" in
    --slots) slots="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "heavy.sh: no command given" >&2; exit 2; }

dir="${TMPDIR:-/tmp}/ai-team-locks/$name"
mkdir -p "$dir"
slot=""
waited=0
start=$(date +%s)

claim() {
  local i d pid
  for i in $(seq 0 $((slots-1))); do
    d="$dir/slot-$i"
    if mkdir "$d" 2>/dev/null; then
      echo $$ > "$d/pid"; slot="$d"; return 0
    fi
    pid=$(cat "$d/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$d"   # owner is gone; reclaim
      if mkdir "$d" 2>/dev/null; then echo $$ > "$d/pid"; slot="$d"; return 0; fi
    elif [ -z "$pid" ]; then
      # just created by another claimer, or a crash between mkdir and pid write
      local age; age=$(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || date +%s) ))
      [ "$age" -gt 30 ] && rm -rf "$d"
    fi
  done
  return 1
}

until claim; do
  if [ "$waited" = 0 ]; then
    echo "heavy.sh: waiting for a free '$name' slot ($slots allowed)..." >&2
    waited=1
  fi
  if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
    echo "heavy.sh: gave up after ${timeout}s waiting for '$name'" >&2
    exit 75
  fi
  sleep 5
done

trap 'rm -rf "$slot"' EXIT INT TERM
[ "$waited" = 1 ] && echo "heavy.sh: got '$name' slot after $(( $(date +%s) - start ))s" >&2
"$@"
