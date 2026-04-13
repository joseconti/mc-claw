# Failover Forensics (Chaos Edition)

When provider failover starts bouncing between CLIs, this is the fastest way to quantify the blast radius.

## 1) Generate a chaos score

```bash
./scripts/failover-chaos-score.sh ~/.mcclaw/logs/mcclaw.log
```

The script reports:
- failover count
- ping-pong flips (`A -> B` followed by `B -> A`)
- CLI abort count
- weighted chaos score + severity tier

## 2) Why this exists

Raw failover logs are useful but noisy. A single score gives maintainers and reporters a shared triage language:
- low score: likely transient provider blip
- medium score: unstable provider routing
- high score: repeated loop / abort storm

## 3) Pair with radar output

For transition-level detail, also run:

```bash
./scripts/failover-loop-radar.sh ~/.mcclaw/logs/mcclaw.log
```

Use both outputs in bug reports for faster root-cause isolation.

