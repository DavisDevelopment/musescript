# Agent 02 — EMA Trend Architect

**Mandate:** EMA crossover systems with trend filters and position management.

**Seed ideas:**
- EMA 8/34, 8/89, 13/34
- SMA trend gate (55, 89)
- Time stops + trailing equity stops via `onPosition`

**Edge hypothesis:** Slower EMA pairs generalize across symbols better than micro SMA when filtered by regime.
