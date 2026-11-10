#!/usr/bin/env bash
# =============================================================================
# heavy.sh — run a heavy command only when a machine-wide slot is free, so
# parallel agents take turns instead of all running it at once.
# =============================================================================
#
# WHY THIS EXISTS
#   capacity.sh decides how many agents start. But once started, several
#   agents may all reach "run the full test suite" or "build the app" at the
#   same moment. Each of those can use every core on its own. Wrapping them
#   in heavy.sh makes them queue: with 1 slot, only one runs at a time across
#   the whole machine, whichever agent, worktree or project it comes from.
#
#   Use it for: full test suites, whole-repo type checks, native builds
#   (xcodebuild, gradle, `expo run:ios`), UI-test runs on a simulator.
#   Don't use it for: single test files, git, grep, lint of a few files.
#
# USAGE
#   heavy.sh [--slots N] [--name POOL] [--timeout SECS] -- COMMAND [ARGS...]
#
#   --slots    How many may run at once in this pool. Default:
#              $AI_TEAM_HEAVY_SLOTS, or 1.
#   --name     Pool name. Commands in different pools don't block each other,
#              e.g. "heavy" (default) for test suites and "build" for native
#              builds. Every caller must use the same --slots for a pool.
#   --timeout  Give up waiting after SECS seconds (default 3600), exit 75.
#   --         Everything after this is the command, run exactly as given.
#
# EXAMPLES
#   heavy.sh -- npm test -- --maxWorkers=2
#   heavy.sh --name build -- npx expo run:ios --device "iPhone 17"
#
# EXIT CODES
#   The command's own exit code once it runs; 75 (EX_TEMPFAIL) if the wait
#   timed out; 2 if no command was given.
#
# HOW THE LOCK WORKS
#   Each slot is a directory: $TMPDIR/ai-team-locks/<pool>/slot-<i>.
#   `mkdir` is atomic: when several processes try to create the same
#   directory, exactly one succeeds. So "mkdir succeeded" = "I own this slot".
#   The owner writes its PID into slot-<i>/pid, and removes the directory on
#   exit (including Ctrl-C or kill). If an owner dies without cleaning up
#   (kill -9, crash, machine reboot without clearing /tmp), the next waiter
#   sees the PID is no longer alive and takes the slot over, so a dead agent
#   never leaves the pool locked forever.
# =============================================================================

# Exit on errors and unset variables; fail a pipeline if any part fails.
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
slots="${AI_TEAM_HEAVY_SLOTS:-1}"   # concurrent runs allowed in the pool
name="heavy"                        # pool name
timeout=3600                        # max seconds to wait for a slot
while [ $# -gt 0 ]; do
  case "$1" in
    --slots) slots="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --timeout) timeout="$2"; shift 2 ;;
    --) shift; break ;;                       # the command starts after --
    -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1' "$0"; exit 0 ;; # print the header comment
    *) break ;;                               # no --: treat the rest as the command
  esac
done
[ $# -gt 0 ] || { echo "heavy.sh: no command given" >&2; exit 2; }

# ---------------------------------------------------------------------------
# 2. Claim a slot
# ---------------------------------------------------------------------------
# All pools live under the user's temp dir, which every agent on this machine
# shares (they all run as the same user).
dir="${TMPDIR:-/tmp}/ai-team-locks/$name"
mkdir -p "$dir"
slot=""              # path of the slot we end up owning
waited=0             # 1 once we've printed the "waiting" message
start=$(date +%s)    # for the timeout and the "waited Ns" message

# claim: try every slot once; return 0 and set $slot if one was taken,
# return 1 if all are busy.
claim() {
  local i d pid
  for i in $(seq 0 $((slots-1))); do
    d="$dir/slot-$i"
    # Fast path: the slot directory doesn't exist, so mkdir creates it and
    # we own it. Record our PID so others can tell whether we're alive.
    if mkdir "$d" 2>/dev/null; then
      echo $$ > "$d/pid"; slot="$d"; return 0
    fi
    # The slot exists. Read who owns it.
    pid=$(cat "$d/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      # `kill -0` sends no signal; it only checks the process exists.
      # The owner is gone without cleaning up: remove the stale slot and
      # race to re-create it. If another waiter wins that race, mkdir fails
      # and we just carry on to the next slot.
      rm -rf "$d"
      if mkdir "$d" 2>/dev/null; then echo $$ > "$d/pid"; slot="$d"; return 0; fi
    elif [ -z "$pid" ]; then
      # Directory exists but has no PID file yet. Usually another process
      # created it a moment ago and is about to write its PID. If it has
      # been like this for over 30 s, the creator crashed between mkdir and
      # writing the PID: treat the slot as stale. (stat -f %m is macOS/BSD,
      # stat -c %Y is Linux; both give the modification time in seconds.)
      local age
      age=$(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || stat -c %Y "$d" 2>/dev/null || date +%s) ))
      [ "$age" -gt 30 ] && rm -rf "$d"
    fi
    # Otherwise the owner is alive: the slot is genuinely busy.
  done
  return 1
}

# Keep trying every 5 seconds until a slot frees up or we time out.
until claim; do
  if [ "$waited" = 0 ]; then
    # Say once that we're waiting (to stderr, so it doesn't mix with the
    # command's own output), so an agent knows why nothing is happening.
    echo "heavy.sh: waiting for a free '$name' slot ($slots allowed)..." >&2
    waited=1
  fi
  if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
    echo "heavy.sh: gave up after ${timeout}s waiting for '$name'" >&2
    exit 75
  fi
  sleep 5
done

# ---------------------------------------------------------------------------
# 3. Run the command, then release the slot
# ---------------------------------------------------------------------------
# Release the slot however we exit: normal end, error, Ctrl-C (INT) or kill
# (TERM). Only kill -9 skips this, and the stale-PID check above covers that.
trap 'rm -rf "$slot"' EXIT INT TERM
[ "$waited" = 1 ] && echo "heavy.sh: got '$name' slot after $(( $(date +%s) - start ))s" >&2
# Run the command as given, with its arguments intact. Under `set -e`, a
# failing command makes the script exit with that same exit code (and the
# EXIT trap still releases the slot).
"$@"
