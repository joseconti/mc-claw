#!/usr/bin/env bash
# failover-loop-radar.sh — quick diagnostics for provider failover storms
#
# Usage:
#   ./scripts/failover-loop-radar.sh /path/to/logfile.log
#   ./scripts/failover-loop-radar.sh ~/Library/Logs/McClaw/mcclaw.log
#
# This script scans McClaw logs for:
# - total failover events
# - most common provider transitions
# - "ping-pong" loops (A -> B immediately followed by B -> A)
# - CLI process abort count

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

echo "=== McClaw Failover Loop Radar ==="
echo "Log file: $LOG_FILE"
echo

failover_count=$(grep -c "Failover:" "$LOG_FILE" || true)
abort_count=$(grep -c "CLI process aborted" "$LOG_FILE" || true)

echo "Total failovers: $failover_count"
echo "CLI aborts:      $abort_count"
echo

if [[ "$failover_count" -eq 0 ]]; then
    echo "No failover events detected."
    exit 0
fi

echo "Top failover transitions:"
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

echo
echo "Ping-pong detector (A -> B then B -> A on next failover line):"
awk '
  /Failover:/ {
    split($0, parts, "Failover: ");
    transition = parts[2];
    gsub(/[[:space:]]+/, "", transition);
    split(transition, p, "→");
    from = p[1];
    to = p[2];
    if (last_from == to && last_to == from) {
      pingpong++;
    }
    last_from = from;
    last_to = to;
  }
  END {
    printf "Ping-pong flips: %d\n", pingpong + 0;
  }
' "$LOG_FILE"

echo
echo "Recent failover lines:"
grep "Failover:" "$LOG_FILE" | tail -n 15 || true

