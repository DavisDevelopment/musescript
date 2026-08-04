# MuseScript post-run diagnostics (`muse.diag`)

**Status:** shipped — ACF / “kiss the curve” chart pack.  
**Not** on WASM per-bar hot path — Metrics + `ChartSink` only.

## Product

After a backtest equity curve exists, paint:

1. **Kiss the peak** — equity + running-max overlay  
2. **Underwater** — drawdown fraction + `hline(0)`  
3. **ACF of returns** — lags `1…maxLag` via `stat_autocorr` / `StatsBuiltins.autocorr`  
4. **Optional** lag-1 rolling ACF strip  

## API

### Haxe harness

```haxe
import musescript.harness.DiagPack;
import musescript.harness.ChartSink;

var chart = new ChartSink();
var r = DiagPack.emit(chart, equity, {
  maxLag: 20,
  rollingWindow: 40,   // 0 = skip rolling strip
  prefix: "diag"
});
// r.lag1, r.maxDrawdown, r.acf, r.commandsAdded, …
// chart.commands → Studio / Flex charts
```

Helpers: `runningMax`, `drawdownSeries`, `acf`, `rollingAcf`, `emitKiss`, `emitUnderwater`, `emitAcf`.

### `muse.diag` (interp / JS; WASM → host_eval)

| Method | Flat | Role |
|--------|------|------|
| `running_max(eq)` | `diag_running_max` | vector |
| `drawdown(eq)` | `diag_drawdown` | underwater fraction |
| `acf(rets, maxLag?)` | `diag_acf` | ACF vector |
| `rolling_acf(rets, win?, lag?)` | `diag_rolling_acf` | rolling strip |
| `kiss(eq?)` | `diag_kiss` | emit equity+peak; summary object |
| `underwater(eq?)` | `diag_underwater` | emit dd + zero line |
| `pack(eq?, maxLag?, rollWin?)` | `diag_pack` | full pack |

Omit `eq` → current `harness.orders.equity`.

### MuseRuntime

```js
// Standalone (after any equity array):
MuseRuntime.diagPack(equity, { maxLag: 20, rollingWindow: 40 })
// → { ok, summary, chart: ChartCommand[] }

// Opt-in on run:
MuseRuntime.run(src, bars, { diag: true })
MuseRuntime.run(src, bars, { diag: { maxLag: 30, rollingWindow: 50 } })
// → result.diag summary; result.chart includes pack commands
```

## Sample chart commands

Labels (prefix `"diag"`):

| kind | label | barIndex | meaning |
|------|-------|----------|---------|
| plot | `diag.equity` | bar i | equity |
| plot | `diag.peak` | bar i | running max (“kiss”) |
| plot | `diag.dd` | bar i | underwater fraction |
| hline | `diag.dd.zero` | — | 0 |
| plot | `diag.acf` | lag (1…N) | return ACF |
| hline | `diag.acf.zero` | — | 0 |
| plot | `diag.acf.roll1` | return index | rolling lag-1 ACF |

Colors default: peak `#f39c12`, dd `#c0392b`, acf `#2980b9`, roll `#8e44ad`.

## Capabilities

Emitters (`diag_kiss` / `diag_underwater` / `diag_pack`) require **chart** (same as `plot`).  
Pure vector helpers stay **compute**.

## Anti-goals

- Per-bar full ACF inside WASM native HostABI  
- Forking Sharpe / `Metrics.maxDrawdown` arithmetic  
- Replacing Studio Truth Report — this is an optional visual pack  

## Tests

`haxe build-diag-tests.hxml` → `node build/js/tests-diag.js`
