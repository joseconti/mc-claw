#!/usr/bin/env bash
# failover-chaos-score.sh — rate provider failover turbulence on a chaos scale
#
# Usage:
#   ./scripts/failover-chaos-score.sh /path/to/mcclaw.log
#
# Output:
# - failover count
# - ping-pong flips
# - CLI abort count
# - chaos score + severity tier

set -euo pipefail

LOG_FILE="${1:-}"

if [[ -z "$LOG_FILE" ]]; then
    echo "Usage: $0 /path/to/mcclaw.log"
    exit 1
fi

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

failovers=$(grep -c "Failover:" "$LOG_FILE" || true)
aborts=$(grep -c "CLI process aborted" "$LOG_FILE" || true)

pingpong=$(
awk '
  /Failover:/ {
    split($0, parts, "Failover: ");
    transition = parts[2];
    gsub(/[[:space:]]+/, "", transition);
    split(transition, p, "→");
    from = p[1];
    to = p[2];
    if (last_from == to && last_to == from) {
      pp++;
    }
    last_from = from;
    last_to = to;
  }
  END { print pp + 0 }
' "$LOG_FILE"
)

# Weighted score tuned for noisy provider loop incidents.
score=$(( failovers * 2 + pingpong * 5 + aborts * 8 ))

tier="calm seas"
if (( score >= 50 )); then
    tier="ELDER CHAOS"
elif (( score >= 25 )); then
    tier="goblin mode"
elif (( score >= 10 )); then
    tier="spicy loop"
elif (( score >= 1 )); then
    tier="mild turbulence"
fi

echo "=== McClaw Failover Chaos Score ==="
echo "log:             $LOG_FILE"
echo "failovers:       $failovers"
echo "ping-pong flips: $pingpong"
echo "cli aborts:      $aborts"
echo "chaos score:     $score"
echo "tier:            $tier"
echo
echo "Top transitions:"
if (( failovers == 0 )); then
    echo "  (none)"
else
    awk '
      /Failover:/ {
        split($0, parts, "Failover: ");
        transition = parts[2];
        counts[transition]++;
      }
      END {
        for (t in counts) {
          printf "%7d  %s\n", counts[t], t;
        }
      }
    ' "$LOG_FILE" | sort -nr | head -n 10
fi

