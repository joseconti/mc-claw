---
name: Bug Report
about: Report a bug to help improve McClaw
title: "[Bug] "
labels: bug
assignees: ''
---

**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What you expected to happen.

**Screenshots**
If applicable, add screenshots.

**Log file**
Please attach the McClaw log file to help us diagnose the issue:
1. Open McClaw → Settings → General → Enable "Diagnostic Logging"
2. Reproduce the bug
3. The log file is saved at `~/.mcclaw/logs/mcclaw.log`
4. Attach the log file to this issue (or paste the relevant lines)

**Failover loop radar (optional, super helpful for provider ping-pong)**
If your logs show repeated `Failover: providerA → providerB` lines, run:

```bash
./scripts/failover-loop-radar.sh ~/.mcclaw/logs/mcclaw.log
```

Paste the output here so maintainers can see transition counts and loop intensity quickly.

**Environment:**
- macOS version: [e.g. 15.2]
- McClaw version: [e.g. 0.8.0]
- AI CLI: [e.g. Claude Code 1.0, Ollama 0.5]

**Additional context**
Any other context about the problem.
