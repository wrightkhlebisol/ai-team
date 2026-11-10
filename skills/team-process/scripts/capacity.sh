#!/usr/bin/env bash
# =============================================================================
# capacity.sh — how many ai-team subagents can start right now without pushing
# the machine past a target share of its CPU and RAM.
# =============================================================================
#
# WHY THIS EXISTS
#   The orchestrator can launch many subagents in parallel. The agents
#   themselves are cheap (they run inside the Claude Code process), but the
#   commands they run are not: test suites, type checks, native builds, dev
#   servers, iOS simulators, Android emulators. Launching too many at once
#   has frozen and crashed the machine, losing every agent's work. This script
#   is the "admission control" step: measure what is free, compare it with
#   what the requested agents are expected to use, and say which to launch
#   now and which to queue.
#
# USAGE
#   capacity.sh [--target PCT] [--costs FILE] [--json] ROLE[=COUNT] ...
#
#   ROLE        A cost profile name (see DEFAULT COSTS below, or --costs FILE).
#               "qa-sim=4" asks for four of that role; a bare "pm" means one.
#               Roles are admitted in the order given, so put the most
#               important first (e.g. blocking fixes before new work).
#   --target    Share of total CPU and RAM the machine may reach, in percent
#               (default 50). Budget = target x total - what is in use now.
#   --costs     A file of extra or overriding profiles, one per line:
#                   name  ram_gb  cpu_cores     # comment
#               Later lines win, so a project file can override a default.
#   --json      Print one JSON object instead of the human summary.
#
# EXAMPLE
#   capacity.sh --target 50 qa-sim=4 code-reviewer=3 software-engineer=1
#     Machine:  12 cores, 24.0 GB RAM
#     Now:      CPU 18% (load 2.10), RAM 41% (9.8 GB), simulators booted: 1
#     Budget:   to 50%: 3.90 cores, 2.20 GB
#     Launch:   code-reviewer=3
#     Queue:    qa-sim=4,software-engineer=1
#
# HOW IT MEASURES
#   CPU in use  = the 1-minute load average (runnable processes). Compared
#                 with the core count, so load 6 on 12 cores = 50%.
#   RAM in use  = what the OS says is NOT available:
#                   macOS: 100 - "System-wide memory free percentage"
#                          from memory_pressure (counts reclaimable cache as free)
#                   Linux: MemTotal - MemAvailable from /proc/meminfo
#   A profile is the expected PEAK of what that role runs, not an average:
#   it is better to under-admit and queue than to overshoot and crash.
#
# EXIT CODES
#   0 always on success (the answer is in the output, not the exit code);
#   2 for a bad argument or a missing costs file.
# =============================================================================

# Stop on any error (-e), on use of an unset variable (-u), and on a failure
# anywhere in a pipeline (-o pipefail), so a broken measurement can't silently
# produce a wrong answer.
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Parse arguments
# ---------------------------------------------------------------------------
target=50        # percent of the machine we allow ourselves to reach
costs_file=""    # optional project-specific profiles
json=0           # 1 = machine-readable output
requests=()      # the ROLE[=COUNT] arguments, in priority order

while [ $# -gt 0 ]; do
  case "$1" in
    # Accept both "--target 50" and "--target=50" styles.
    --target) target="$2"; shift 2 ;;
    --target=*) target="${1#*=}"; shift ;;
    --costs) costs_file="$2"; shift 2 ;;
    --costs=*) costs_file="${1#*=}"; shift ;;
    --json) json=1; shift ;;
    # Print the usage block from the header comment above (lines 2–52).
    -h|--help) sed -n '2,52p' "$0"; exit 0 ;;
    # Anything else is a role request, kept in the order given.
    *) requests+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------------------
# 2. Cost profiles
# ---------------------------------------------------------------------------
# DEFAULT COSTS — columns: name  ram_gb  cpu_cores (expected peak while the
# role is working). These assume the limits the orchestrator puts in every
# prompt: test runners capped (e.g. Jest --maxWorkers=2) and only one full
# test suite or native build at a time machine-wide (see heavy.sh). Without
# those limits real usage is several times higher.
#
#   pm, product-designer, code-reviewer
#       mostly read files, run git/grep, call the model: light.
#   software-engineer
#       runs the project's tests (capped), the type checker, maybe a dev server.
#   engineer-native
#       compiles a native app (xcodebuild / gradle): many cores, lots of RAM.
#   qa-engineer
#       runs the checks and the app without a device simulator.
#   qa-sim
#       QA that drives a simulator or emulator: the device itself, the app
#       in it, a UI-test runner and the capped test suite.
#   simulator
#       one extra booted simulator/emulator that nobody is driving.
default_costs='
pm                 0.3 0.25
product-designer   0.5 0.5
code-reviewer      0.4 0.5
software-engineer  2.0 2.0
engineer-native    5.0 6.0
qa-engineer        2.0 2.0
qa-sim             3.5 3.0
simulator          2.0 1.0
'

# The project's file is appended after the defaults, so its lines win (see
# cost_of: the last matching line is the one used).
costs="$default_costs"
if [ -n "$costs_file" ]; then
  [ -f "$costs_file" ] || { echo "costs file not found: $costs_file" >&2; exit 2; }
  costs="$costs
$(cat "$costs_file")"
fi

# cost_of NAME -> prints "ram_gb cpu_cores" for that profile, or nothing if
# the name is unknown. Comments ('#' to end of line) are stripped first, and
# because awk keeps overwriting r and c, the LAST definition of a name wins.
cost_of() {
  printf '%s\n' "$costs" | sed 's/#.*//' \
    | awk -v n="$1" '$1==n {r=$2; c=$3} END {if (r!="") print r, c}'
}

# ---------------------------------------------------------------------------
# 3. Measure the machine
# ---------------------------------------------------------------------------
os=$(uname -s)
if [ "$os" = "Darwin" ]; then
  # --- macOS ---
  cores=$(sysctl -n hw.ncpu)
  # hw.memsize is bytes; convert to GB (1 GB = 1073741824 bytes).
  ram_total_gb=$(awk -v b="$(sysctl -n hw.memsize)" 'BEGIN {printf "%.1f", b/1073741824}')
  # vm.loadavg looks like "{ 5.92 6.10 7.30 }"; field 2 is the 1-minute load.
  load1=$(sysctl -n vm.loadavg | awk '{print $2}')
  # memory_pressure ends with "System-wide memory free percentage: 32%".
  # That figure already treats reclaimable cache as free, which is what we want.
  free_pct=$(memory_pressure 2>/dev/null \
    | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}')
  # If memory_pressure is missing or its output changed, assume 50% free
  # rather than failing: the CPU side still gives a useful answer.
  [ -n "$free_pct" ] || free_pct=50
  ram_used_gb=$(awk -v t="$ram_total_gb" -v f="$free_pct" 'BEGIN {printf "%.1f", t*(100-f)/100}')
  # Booted iOS simulators are the usual heavy hitters; report how many are up
  # so the orchestrator can shut down idle ones before launching more.
  # (`|| true` because grep -c exits 1 when it counts zero.)
  sims=$(xcrun simctl list devices booted 2>/dev/null | grep -c '(Booted)' || true)
else
  # --- Linux ---
  cores=$(nproc)
  # /proc/meminfo values are in kB; 1 GB = 1048576 kB.
  ram_total_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo)
  # MemAvailable is the kernel's own estimate of memory usable without
  # swapping (it includes reclaimable cache), so "in use" = total - available.
  ram_used_gb=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%.1f", (t-a)/1048576}' /proc/meminfo)
  # First field of /proc/loadavg is the 1-minute load.
  load1=$(awk '{print $1}' /proc/loadavg)
  sims=0   # no iOS simulators on Linux
fi
# Android emulators run as qemu-system-* or emulator64-*; count them on any OS.
emulators=$(pgrep -f 'qemu-system|emulator64' 2>/dev/null | wc -l | tr -d ' ' || true)

# Budget = what we may still add before reaching the target:
#   cpu_budget = cores x target% - current load        (in cores)
#   ram_budget = total RAM x target% - RAM in use      (in GB)
# Either can be negative, meaning we are already over the target.
# (A heredoc feeds awk's output to `read` so both values land in this shell.)
read -r cpu_budget ram_budget <<EOF
$(awk -v c="$cores" -v l="$load1" -v t="$ram_total_gb" -v u="$ram_used_gb" -v p="$target" \
  'BEGIN {printf "%.2f %.2f", c*p/100 - l, t*p/100 - u}')
EOF

# ---------------------------------------------------------------------------
# 4. Admit requests in priority order
# ---------------------------------------------------------------------------
# Greedy, in the order given: for each requested agent, if its RAM AND CPU
# cost both fit in what is left, admit it and subtract its cost; otherwise
# queue it. A later, smaller role can still be admitted after a bigger one
# was queued (e.g. reviewers fit when a simulator QA doesn't). That is on
# purpose: light work keeps moving while heavy work waits.
admitted=()      # "role=N" entries to launch now
queued=()        # "role=N" entries to launch later
unknown=()       # role names with no profile
cpu_left=$cpu_budget
ram_left=$ram_budget
# "${requests[@]+...}" expands to nothing when the array is empty; without
# the guard, `set -u` treats an empty array as unset on older bash (macOS 3.2).
for req in "${requests[@]+"${requests[@]}"}"; do
  role="${req%%=*}"                         # text before '=' (or all of it)
  count=1
  [ "$req" != "$role" ] && count="${req#*=}" # text after '=', if there was one
  c=$(cost_of "$role")
  if [ -z "$c" ]; then unknown+=("$role"); continue; fi
  read -r r cp <<<"$c"                      # r = RAM GB, cp = CPU cores
  fit=0
  # Try to admit each of the COUNT agents one at a time.
  for _ in $(seq 1 "$count"); do
    # Bash can't compare decimals, so awk does it and prints 1 (fits) or 0.
    ok=$(awk -v rl="$ram_left" -v cl="$cpu_left" -v r="$r" -v cp="$cp" \
      'BEGIN {print (rl>=r && cl>=cp) ? 1 : 0}')
    if [ "$ok" = 1 ]; then
      fit=$((fit+1))
      # Subtract this agent's cost from what is left.
      read -r ram_left cpu_left <<EOF
$(awk -v rl="$ram_left" -v cl="$cpu_left" -v r="$r" -v cp="$cp" 'BEGIN {printf "%.2f %.2f", rl-r, cl-cp}')
EOF
    fi
  done
  [ "$fit" -gt 0 ] && admitted+=("$role=$fit")
  [ $((count-fit)) -gt 0 ] && queued+=("$role=$((count-fit))")
done

# ---------------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------------
# Current usage as whole percentages, for the summary line.
cpu_pct=$(awk -v l="$load1" -v c="$cores" 'BEGIN {printf "%.0f", 100*l/c}')
ram_pct=$(awk -v u="$ram_used_gb" -v t="$ram_total_gb" 'BEGIN {printf "%.0f", 100*u/t}')
# over=1 when either budget is negative, i.e. the machine is already past the
# target before we launch anything. (awk's exit status is the test here.)
over=0
awk -v a="$cpu_budget" -v b="$ram_budget" 'BEGIN {exit !(a<0 || b<0)}' && over=1

# join A B C -> "A,B,C"
join() { local IFS=,; echo "$*"; }

if [ "$json" = 1 ]; then
  # q A B -> ["A","B"]; role names are plain words, so no escaping is needed.
  q() { local out="" x; for x in "$@"; do out="$out\"$x\","; done; echo "[${out%,}]"; }
  printf '{"target_pct":%s,"cores":%s,"load1":%s,"cpu_pct":%s,"ram_total_gb":%s,"ram_used_gb":%s,"ram_pct":%s,"simulators_booted":%s,"emulators":%s,"cpu_budget_cores":%s,"ram_budget_gb":%s,"over_target":%s,"launch":%s,"queue":%s,"unknown_roles":%s}\n' \
    "$target" "$cores" "$load1" "$cpu_pct" "$ram_total_gb" "$ram_used_gb" "$ram_pct" "$sims" "$emulators" \
    "$cpu_budget" "$ram_budget" "$([ $over = 1 ] && echo true || echo false)" \
    "$(q "${admitted[@]+"${admitted[@]}"}")" "$(q "${queued[@]+"${queued[@]}"}")" "$(q "${unknown[@]+"${unknown[@]}"}")"
  exit 0
fi

# Human summary.
echo "Machine:  $cores cores, $ram_total_gb GB RAM"
echo "Now:      CPU ${cpu_pct}% (load $load1), RAM ${ram_pct}% ($ram_used_gb GB), simulators booted: $sims, emulators: $emulators"
echo "Budget:   to ${target}%: $cpu_budget cores, $ram_budget GB"
[ "$over" = 1 ] && echo "WARNING:  already over the ${target}% target; launch nothing heavy until it drops"
# With no roles requested, the script is just a "how busy is the machine" check.
[ ${#requests[@]} -gt 0 ] || exit 0
echo "Launch:   $( [ ${#admitted[@]} -gt 0 ] && join "${admitted[@]}" || echo none)"
echo "Queue:    $( [ ${#queued[@]} -gt 0 ] && join "${queued[@]}" || echo none)"
[ ${#unknown[@]} -gt 0 ] && echo "Unknown:  $(join "${unknown[@]}") (add them with --costs)"
exit 0
