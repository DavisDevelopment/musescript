# Graph Report - .  (2026-07-20)

## Corpus Check
- 461 files · ~183,210 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1156 nodes · 1317 edges · 109 communities (102 shown, 7 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 28 edges (avg confidence: 0.74)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25
- Community 26
- Community 27
- Community 28
- Community 29
- Community 30
- Community 31
- Community 32
- Community 33
- Community 34
- Community 35
- Community 36
- Community 37
- Community 38
- Community 39
- Community 40
- Community 41
- Community 42
- Community 43
- Community 44
- Community 45
- Community 46
- Community 47
- Community 48
- Community 49
- Community 50
- Community 51
- Community 52
- Community 53
- Community 54
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62
- Community 63
- Community 64
- Community 65
- Community 66
- Community 67
- Community 68
- Community 69
- Community 70
- Community 71
- Community 72
- Community 73
- Community 74
- Community 75
- Community 76
- Community 78
- Community 79
- Community 80
- Community 89
- Community 100
- Community 101
- Community 103
- Community 107

## God Nodes (most connected - your core abstractions)
1. `ohlc` - 19 edges
2. `deliverables` - 14 edges
3. `MuseBacktestCore` - 14 edges
4. `repository` - 14 edges
5. `main()` - 13 edges
6. `KestrGraalServer` - 12 edges
7. `stmt_templates_live` - 11 edges
8. `official` - 11 edges
9. `BTCUSD` - 11 edges
10. `binance` - 11 edges

## Surprising Connections (you probably didn't know these)
- `main()` --calls--> `load_strategy_module()`  [INFERRED]
  tools/kestrel_wasm_proof.py → tools/muse_math_runtime.py
- `build_tapes()` --references--> `tapes`  [EXTRACTED]
  examples/strategy-tournament/harness/crypto_fx_lab.py → examples/strategy-tournament/tapes/manifest.json
- `main()` --calls--> `evaluate()`  [INFERRED]
  tools/corpus_batch.py → tools/corpus_lab.py
- `main()` --calls--> `run_backtest()`  [INFERRED]
  tools/corpus_batch.py → tools/corpus_lab.py
- `main()` --calls--> `split_spy()`  [INFERRED]
  tools/corpus_batch.py → tools/corpus_lab.py

## Import Cycles
- None detected.

## Communities (109 total, 7 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.09
Nodes (20): BacktestReply, BacktestRequest, Context, Engine, Value, KestrGraalServer, BacktestResult, Bar (+12 more)

### Community 1 - "Community 1"
Cohesion: 0.04
Nodes (46): bars, end, path, start, bars, end, path, start (+38 more)

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (42): agent, best_score, best_vs_bh, best_wf, deliverables, domain, eval_window, calendar_months (+34 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (42): agent, best_candidate, best_rsi_entry_candidate, deliverables, plan, strategies, wishlist, domain (+34 more)

### Community 4 - "Community 4"
Cohesion: 0.05
Nodes (39): ms, comment, patterns, comment, patterns, comment, patterns, patterns (+31 more)

### Community 5 - "Community 5"
Cohesion: 0.13
Nodes (28): main(), main(), annotate_file(), append_ledger(), ensure_dirs(), evaluate(), format_annotation(), main() (+20 more)

### Community 6 - "Community 6"
Cohesion: 0.08
Nodes (28): build_eval_tapes(), buy_hold_source(), eval_all_agents(), eval_strategy(), eval_walkforward(), main(), Metrics, Path (+20 more)

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (28): agent, best_candidate, composite_tie, eval_window, end, start, field_winner, agent (+20 more)

### Community 8 - "Community 8"
Cohesion: 0.08
Nodes (22): asm, bars, bytes, cp, d1, d2, d3, dfull (+14 more)

### Community 9 - "Community 9"
Cohesion: 0.08
Nodes (23): agent, best_candidate, best_score, deliverables, plan, strategies, wishlist, domain (+15 more)

### Community 10 - "Community 10"
Cohesion: 0.10
Nodes (20): agent, best_all_sym, file, mean_d_sharpe, mean_sharpe, median_mdd, score, vs_field_winner (+12 more)

### Community 11 - "Community 11"
Cohesion: 0.10
Nodes (20): agent, best_all_sym, file, mean_d_sharpe, mean_sharpe, median_mdd, score, vs_field_winner (+12 more)

### Community 12 - "Community 12"
Cohesion: 0.10
Nodes (19): agent, best_all_sym, file, mean_d_sharpe, mean_sharpe, median_mdd, r1_delta_mean_sharpe, best_spy_3m (+11 more)

### Community 13 - "Community 13"
Cohesion: 0.11
Nodes (17): agent, best_all_sym, file, mean_d_sharpe, mean_sharpe, median_mdd, r3_delta_score, score (+9 more)

### Community 14 - "Community 14"
Cohesion: 0.24
Nodes (16): annotate_activity(), build_tapes(), _buy_hold_source(), eval_strategy(), eval_walkforward(), _fetch_rows(), main(), Metrics (+8 more)

### Community 15 - "Community 15"
Cohesion: 0.11
Nodes (17): classPath, contributors, dependencies, hxnodejs, utest, description, license, name (+9 more)

### Community 16 - "Community 16"
Cohesion: 0.21
Nodes (14): main(), _host_get(), _instantiate_strategy(), load_numba(), load_python(), load_strategy_module(), load_strategy_on_bar(), load_wasm() (+6 more)

### Community 17 - "Community 17"
Cohesion: 0.22
Nodes (15): Connection, DuckDBPyConnection, build_panel(), _equities_symbols(), _facts_for_cik(), _forward_fill_onto_bars(), _growth_series(), _load_bars() (+7 more)

### Community 18 - "Community 18"
Cohesion: 0.12
Nodes (15): agent, best_score, file, score, domain, eval_window, execution, BTCUSD (+7 more)

### Community 19 - "Community 19"
Cohesion: 0.13
Nodes (14): agent, best_mean_3m_sharpe, d_sharpe, file, sharpe, eval_window, key_innovation, primary_bet (+6 more)

### Community 20 - "Community 20"
Cohesion: 0.13
Nodes (14): agent, best_score, beats_champion_by, file, score, champion_score, eval_window, key_innovation (+6 more)

### Community 21 - "Community 21"
Cohesion: 0.13
Nodes (14): agent, domain, eval_window, execution, flagship, s01.ms, s02.ms, s03.ms (+6 more)

### Community 22 - "Community 22"
Cohesion: 0.14
Nodes (13): agent, best_spy_3m_sharpe, d_sharpe, file, sharpe, eval_window, key_innovation, primary_bet (+5 more)

### Community 23 - "Community 23"
Cohesion: 0.14
Nodes (13): agent, best_score, file, score, domain, equity_baseline_note, equity_baseline_score, eval_window (+5 more)

### Community 24 - "Community 24"
Cohesion: 0.32
Nodes (13): close(), _cross_validate(), _extract_params(), main(), make_request(), perf_backtest_throughput(), Path, Unit + perf test for the KestrGraal gRPC server (graal/KestrGraalServer.java). (+5 more)

### Community 25 - "Community 25"
Cohesion: 0.15
Nodes (12): domain, eval_window, calendar_months, end, start, execution, fill, mode (+4 more)

### Community 26 - "Community 26"
Cohesion: 0.17
Nodes (11): Programming Languages, categories, contributes, grammars, languages, description, displayName, engines (+3 more)

### Community 27 - "Community 27"
Cohesion: 0.18
Nodes (10): agent, best_spy_3m, d_sharpe_vs_bh, file, mdd, sharpe, eval_window, mandate (+2 more)

### Community 28 - "Community 28"
Cohesion: 0.18
Nodes (11): stmt_templates_live, AtrChandelierExit, DualMacdConfirm, DualRsiScalpExit, EquityHardStop, ProfitLock, StagedDonchianExit, StagedProfitLock (+3 more)

### Community 29 - "Community 29"
Cohesion: 0.18
Nodes (11): asset, bars, causal, end, nonflat_bars, path, provenances, sources (+3 more)

### Community 30 - "Community 30"
Cohesion: 0.18
Nodes (11): asset, bars, causal, end, nonflat_bars, path, provenances, sources (+3 more)

### Community 31 - "Community 31"
Cohesion: 0.18
Nodes (11): asset, bars, causal, end, nonflat_bars, path, provenances, sources (+3 more)

### Community 32 - "Community 32"
Cohesion: 0.18
Nodes (11): XRPUSD, asset, bars, causal, end, nonflat_bars, path, provenances (+3 more)

### Community 33 - "Community 33"
Cohesion: 0.20
Nodes (9): agent, files, s01.ms, s02.ms, s03.ms, s04.ms, s05.ms, round (+1 more)

### Community 34 - "Community 34"
Cohesion: 0.20
Nodes (9): agent, files, s01.ms, s02.ms, s03.ms, s04.ms, s05.ms, round (+1 more)

### Community 35 - "Community 35"
Cohesion: 0.20
Nodes (9): agent, files, s01.ms, s02.ms, s03.ms, s04.ms, s05.ms, round (+1 more)

### Community 36 - "Community 36"
Cohesion: 0.20
Nodes (9): agent, files, s01.ms, s02.ms, s03.ms, s04.ms, s05.ms, round (+1 more)

### Community 37 - "Community 37"
Cohesion: 0.20
Nodes (9): agent, files, s01.ms, s02.ms, s03.ms, s04.ms, s05.ms, round (+1 more)

### Community 38 - "Community 38"
Cohesion: 0.20
Nodes (9): deliverables, PLAN-R7.md, round-07/s01.ms, round-07/s02.ms, round-07/s03.ms, round-07/s04.ms, round-07/s05.ms, WISHLIST.md (+1 more)

### Community 39 - "Community 39"
Cohesion: 0.20
Nodes (9): agent, files, s01.ms, s02.ms, s03.ms, s04.ms, s05.ms, round (+1 more)

### Community 40 - "Community 40"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, sources, start (+2 more)

### Community 41 - "Community 41"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 42 - "Community 42"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 43 - "Community 43"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 44 - "Community 44"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 45 - "Community 45"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 46 - "Community 46"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 47 - "Community 47"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 48 - "Community 48"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 49 - "Community 49"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, provenances, start (+2 more)

### Community 50 - "Community 50"
Cohesion: 0.20
Nodes (10): asset, bars, causal, end, nonflat_bars, path, sources, start (+2 more)

### Community 51 - "Community 51"
Cohesion: 0.20
Nodes (10): SOLUSD, asset, bars, causal, end, nonflat_bars, path, provenances (+2 more)

### Community 52 - "Community 52"
Cohesion: 0.20
Nodes (10): USDCAD, asset, bars, causal, end, nonflat_bars, path, sources (+2 more)

### Community 53 - "Community 53"
Cohesion: 0.22
Nodes (8): agent, best_spy_3m_sharpe, file, sharpe, eval_window, round, self_test_symbol, strategies

### Community 54 - "Community 54"
Cohesion: 0.22
Nodes (8): agent, best_score, domain, execution, flagship, mandate, round, strategies

### Community 55 - "Community 55"
Cohesion: 0.22
Nodes (9): BTCUSD, EURUSD, self_test, full_basket, harness, probe_count, symbols_spot_check, ADAUSD (+1 more)

### Community 56 - "Community 56"
Cohesion: 0.22
Nodes (9): asset, bars, causal, end, nonflat_bars, path, start, symbol (+1 more)

### Community 57 - "Community 57"
Cohesion: 0.22
Nodes (9): USDJPY, asset, bars, causal, end, nonflat_bars, path, start (+1 more)

### Community 58 - "Community 58"
Cohesion: 0.28
Nodes (8): _ensure_kalshi_advisor_on_path(), fit_and_serialize_cloud(), fit_and_serialize_cloud_json(), Any, kestrel_bridge.py — fits a `ProbabilityCloud` from raw OHLCV candles and seriali, `fit_and_serialize_cloud` + `json.dumps` — the direct callable a Haxe     `#if p, Adds kalshi-ai-advisor/python to sys.path, sibling to this repo     (kalshai/mus, Fit a ProbabilityCloud from raw candles and return the JSON-safe dict     `ProbC

### Community 59 - "Community 59"
Cohesion: 0.25
Nodes (7): agent, best_spy_3m_sharpe, file, sharpe, eval_window, self_test_symbol, strategies

### Community 60 - "Community 60"
Cohesion: 0.29
Nodes (7): r7_lessons, Donchian21 entry too slow for crypto next-open gap risk — Donchian8 wins probes, EURUSD Don8+EMA8 never fires — 0 trades beats FX drift (+3.26 d-Sharpe), falling(x, n, minBars) replaces bars_in_trade && falling(...) boilerplate, Maximalist layers s03-s05 no-op when s02 fall-gated rail is correct, RSI72 cascade beats RSI75 on crypto mean-revert spikes, TrailingStop(0.08) stmt template expands cleanly in gene-runner (P0 wish closed)

### Community 61 - "Community 61"
Cohesion: 0.29
Nodes (7): sources, sources, sources, sources, sources, sources, yahoo

### Community 62 - "Community 62"
Cohesion: 0.29
Nodes (7): sources, sources, sources, sources, sources, sources, binance

### Community 63 - "Community 63"
Cohesion: 0.33
Nodes (6): provenances, provenances, provenances, provenances, provenances, ohlc

### Community 64 - "Community 64"
Cohesion: 0.33
Nodes (6): bars, end, path, start, AMD, eval_3m

### Community 65 - "Community 65"
Cohesion: 0.53
Nodes (5): bench(), main(), make_request(), Concurrency scaling benchmark for KestrGraal -- how much does wall-clock through, run_calls()

### Community 66 - "Community 66"
Cohesion: 0.40
Nodes (5): bars, end, path, start, AAPL

### Community 67 - "Community 67"
Cohesion: 0.40
Nodes (5): bars, end, path, start, AMZN

### Community 68 - "Community 68"
Cohesion: 0.40
Nodes (5): GOOGL, bars, end, path, start

### Community 69 - "Community 69"
Cohesion: 0.40
Nodes (5): IWM, bars, end, path, start

### Community 70 - "Community 70"
Cohesion: 0.40
Nodes (5): META, bars, end, path, start

### Community 71 - "Community 71"
Cohesion: 0.40
Nodes (5): MSFT, bars, end, path, start

### Community 72 - "Community 72"
Cohesion: 0.40
Nodes (5): NVDA, bars, end, path, start

### Community 73 - "Community 73"
Cohesion: 0.40
Nodes (5): QQQ, bars, end, path, start

### Community 74 - "Community 74"
Cohesion: 0.40
Nodes (5): SPY, bars, end, path, start

### Community 75 - "Community 75"
Cohesion: 0.50
Nodes (4): eval_window, end, note, start

### Community 78 - "Community 78"
Cohesion: 0.67
Nodes (3): eval_strategy(), main(), Path

### Community 89 - "Community 89"
Cohesion: 0.67
Nodes (3): r6_equity_baseline, note, score

## Knowledge Gaps
- **701 isolated node(s):** `agent`, `round`, `eval_window`, `self_test_symbol`, `strategies` (+696 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `tapes` connect `Community 6` to `Community 64`, `Community 1`, `Community 14`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **Why does `walkforward` connect `Community 25` to `Community 40`, `Community 41`, `Community 42`, `Community 43`, `Community 44`, `Community 45`, `Community 29`, `Community 30`, `Community 31`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Why does `official` connect `Community 25` to `Community 32`, `Community 46`, `Community 47`, `Community 48`, `Community 49`, `Community 50`, `Community 51`, `Community 52`, `Community 56`, `Community 57`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `main()` (e.g. with `evaluate()` and `run_backtest()`) actually correct?**
  _`main()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `agent`, `round`, `eval_window` to the rest of the system?**
  _701 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08571428571428572 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.043478260869565216 - nodes in this community are weakly interconnected._