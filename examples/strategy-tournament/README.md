# Strategy Tournament

Six blind agents, five strategies each, one winner.

## Quick start

```powershell
# Build 3-month eval tapes
python examples/strategy-tournament/harness/tournament_lab.py --build-tapes

# Agent self-test (3 months only!)
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-01/strategies/s01.ms --symbol SPY

# Organizer: score everyone after lock
python examples/strategy-tournament/harness/tournament_lab.py --score-all
```

See `RULES.md` for sequestration and scoring.
