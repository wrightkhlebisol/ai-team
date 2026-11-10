#!/usr/bin/env bash
# capacity.sh: how many ai-team subagents can start now without pushing the
# machine past a target share of its CPU and RAM.
#
# Usage:
#   capacity.sh [--target PCT] [--costs FILE] [--json] ROLE[=COUNT] ...
#
#   ROLE is a cost profile name (see DEFAULT COSTS below, or --costs FILE).
#   Roles are admitted in the order given, so list the most important first.
#   --target  share of total CPU and RAM the machine may reach (default 50)
#   --costs   extra/override profiles, one per line: "name ram_gb cpu_cores"
#             ('#' starts a comment). Later lines win.
#   --json    machine-readable output only
#
# Example:
#   capacity.sh --target 50 qa-sim=4 code-reviewer=3 software-engineer=1
#
# The measure: CPU in use = 1-minute load average; RAM in use = what the OS
# reports as not available (macOS: 100 - memory_pressure free %, Linux:
# MemTotal - MemAvailable). Budget = target x total - in use. A profile is the
# expected PEAK of the commands that role runs (tests, builds, simulators),
# not of the agent itself, which runs inside the Claude Code process.
set -euo pipefail

target=50
costs_file=""
json=0
requests=()

while [ $# -gt 0 ]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --target=*) target="${1#*=}"; shift ;;
    --costs) costs_file="$2"; shift 2 ;;
    --costs=*) costs_file="${1#*=}"; shift ;;
    --json) json=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) requests+=("$1"); shift ;;
  esac
done

# DEFAULT COSTS: name ram_gb cpu_cores (expected peak while the role works).
# Assumes test runners are capped (e.g. Jest --maxWorkers=2) and only one
# full test suite or native build runs at a time (see heavy.sh).
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

costs="$default_costs"
if [ -n "$costs_file" ]; then
  [ -f "$costs_file" ] || { echo "costs file not found: $costs_file" >&2; exit 2; }
  costs="$costs
$(cat "$costs_file")"
fi

cost_of() { # name -> "ram cpu" (last definition wins)
  printf '%s\n' "$costs" | sed 's/#.*//' | awk -v n="$1" '$1==n {r=$2; c=$3} END {if (r!="") print r, c}'
}

# ---- measure the machine ----
os=$(uname -s)
if [ "$os" = "Darwin" ]; then
  cores=$(sysctl -n hw.ncpu)
  ram_total_gb=$(awk -v b="$(sysctl -n hw.memsize)" 'BEGIN {printf "%.1f", b/1073741824}')
  load1=$(sysctl -n vm.loadavg | awk '{print $2}')
  free_pct=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}')
  [ -n "$free_pct" ] || free_pct=50
  ram_used_gb=$(awk -v t="$ram_total_gb" -v f="$free_pct" 'BEGIN {printf "%.1f", t*(100-f)/100}')
  sims=$(xcrun simctl list devices booted 2>/dev/null | grep -c '(Booted)' || true)
else
  cores=$(nproc)
  ram_total_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1048576}' /proc/meminfo)
  ram_used_gb=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%.1f", (t-a)/1048576}' /proc/meminfo)
  load1=$(awk '{print $1}' /proc/loadavg)
  sims=0
fi
emulators=$(pgrep -f 'qemu-system|emulator64' 2>/dev/null | wc -l | tr -d ' ' || true)

read -r cpu_budget ram_budget <<EOF
$(awk -v c="$cores" -v l="$load1" -v t="$ram_total_gb" -v u="$ram_used_gb" -v p="$target" \
  'BEGIN {printf "%.2f %.2f", c*p/100 - l, t*p/100 - u}')
EOF

# ---- admit requests in order ----
admitted=()
queued=()
unknown=()
cpu_left=$cpu_budget
ram_left=$ram_budget
for req in "${requests[@]+"${requests[@]}"}"; do
  role="${req%%=*}"
  count=1
  [ "$req" != "$role" ] && count="${req#*=}"
  c=$(cost_of "$role")
  if [ -z "$c" ]; then unknown+=("$role"); continue; fi
  read -r r cp <<<"$c"
  fit=0
  for _ in $(seq 1 "$count"); do
    ok=$(awk -v rl="$ram_left" -v cl="$cpu_left" -v r="$r" -v cp="$cp" 'BEGIN {print (rl>=r && cl>=cp) ? 1 : 0}')
    if [ "$ok" = 1 ]; then
      fit=$((fit+1))
      read -r ram_left cpu_left <<EOF
$(awk -v rl="$ram_left" -v cl="$cpu_left" -v r="$r" -v cp="$cp" 'BEGIN {printf "%.2f %.2f", rl-r, cl-cp}')
EOF
    fi
  done
  [ "$fit" -gt 0 ] && admitted+=("$role=$fit")
  [ $((count-fit)) -gt 0 ] && queued+=("$role=$((count-fit))")
done

cpu_pct=$(awk -v l="$load1" -v c="$cores" 'BEGIN {printf "%.0f", 100*l/c}')
ram_pct=$(awk -v u="$ram_used_gb" -v t="$ram_total_gb" 'BEGIN {printf "%.0f", 100*u/t}')
over=0
awk -v a="$cpu_budget" -v b="$ram_budget" 'BEGIN {exit !(a<0 || b<0)}' && over=1

join() { local IFS=,; echo "$*"; }
if [ "$json" = 1 ]; then
  q() { local out="" x; for x in "$@"; do out="$out\"$x\","; done; echo "[${out%,}]"; }
  printf '{"target_pct":%s,"cores":%s,"load1":%s,"cpu_pct":%s,"ram_total_gb":%s,"ram_used_gb":%s,"ram_pct":%s,"simulators_booted":%s,"emulators":%s,"cpu_budget_cores":%s,"ram_budget_gb":%s,"over_target":%s,"launch":%s,"queue":%s,"unknown_roles":%s}\n' \
    "$target" "$cores" "$load1" "$cpu_pct" "$ram_total_gb" "$ram_used_gb" "$ram_pct" "$sims" "$emulators" \
    "$cpu_budget" "$ram_budget" "$([ $over = 1 ] && echo true || echo false)" \
    "$(q "${admitted[@]+"${admitted[@]}"}")" "$(q "${queued[@]+"${queued[@]}"}")" "$(q "${unknown[@]+"${unknown[@]}"}")"
  exit 0
fi

echo "Machine:  $cores cores, $ram_total_gb GB RAM"
echo "Now:      CPU ${cpu_pct}% (load $load1), RAM ${ram_pct}% ($ram_used_gb GB), simulators booted: $sims, emulators: $emulators"
echo "Budget:   to ${target}%: $cpu_budget cores, $ram_budget GB"
[ "$over" = 1 ] && echo "WARNING:  already over the ${target}% target; launch nothing heavy until it drops"
[ ${#requests[@]} -gt 0 ] || exit 0
echo "Launch:   $( [ ${#admitted[@]} -gt 0 ] && join "${admitted[@]}" || echo none)"
echo "Queue:    $( [ ${#queued[@]} -gt 0 ] && join "${queued[@]}" || echo none)"
[ ${#unknown[@]} -gt 0 ] && echo "Unknown:  $(join "${unknown[@]}") (add them with --costs)"
exit 0
