# Strategy kinds — MuseScript surfaces for the hardened type lattice

These examples are intentionally different *kinds* of strategy logic, not
variations on MA-cross. Each leans on builtins/types from the Dict/Set +
type-hardening work, plus optimize/tune and primitive ML surfaces.

| File | Kind | Surface |
|------|------|---------|
| `01_macd_hist_bbands.ms` | momentum + bands | typed `macd` / `bbands` fields |
| `02_regression_channel.ms` | trend channel | `stat_regression` object |
| `03_window_rank_breakout.ms` | time-series rank | `stat_percentile_rank` + `sort` |
| `04_ewm_vol_regime.ms` | vol regime | `ewm_stdev` + `stat_kurtosis` |
| `05_signal_set_compose.ms` | multi-signal | `set_*` tagging |
| `06_risk_window_sortino.ms` | risk exit | `sortino` / `max_drawdown` |
| `07_stoch_kd_cross.ms` | oscillator cross | typed `stoch.k` / `stoch.d` |
| `08_autocorr_revert.ms` | mean reversion | `stat_autocorr` |
| `09_argsort_tail_pressure.ms` | order-stat pressure | `argsort` |
| `10_dict_scorecard.ms` | scored gates | `dict_*` scorecard |
| `11_atr_mom_thrust.ms` | vol-scaled thrust | `mom` / `atr` / `roc` |
| `12_skew_kurt_filter.ms` | distribution filter | `stat_skewness` + kurtosis |
| `13_bbands_squeeze_release.ms` | squeeze release | band width from object fields |
| `14_ema_spread_impulse.ms` | EMA spread pulse | series arithmetic + `window`/`avg` |
| `15_ewm_var_breakout.ms` | compressed-vol breakout | `ewm_var` vs `stat_variance` |
| `16_set_jaccard_regime.ms` | regime overlap | `set_jaccard` |
| `17_vector_zscore_gate.ms` | z-score gate | `stat_zscore` vector index |
| `18_signed_return_thrust.ms` | signed-return thrust | `sci_diff` / `sum` / `count` |
| `19_take_drop_pulse.ms` | recent-vs-older pulse | `take` / `drop` |
| `20_rank_sortino_combo.ms` | rank × risk | percentile + sortino |
| `21_zip_spread_impulse.ms` | spread via zip | hscript `zipWith` + lambda |
| `22_filter_count_momentum.ms` | signed-count momentum | hscript `filter` / `count` |
| `23_tune_sma_cross.ms` | param search | `tune` / `optimize` macro + grid |
| `24_search_ema_grid.ms` | typed pipeline search | `pipeline` + EMA cross |
| `25_sigmoid_mom_gate.ms` | logistic gate | `ml_sigmoid` on vol-scaled mom |
| `26_softmax_regime.ms` | regime pick | `ml_softmax` over score vector |
| `27_ridge_linear_neuron.ms` | one-layer fit | `ml_ridge_fit` + `ml_linear_predict` |
| `28_two_layer_toy_nn.ms` | tiny MLP | stacked `ml_dot` + `ml_sigmoid` |
| `29_dot_mse_confidence.ms` | alignment gate | `ml_dot` + `ml_mse` |
| `30_tune_sigmoid_gate.ms` | tune × NN gate | grid-search over sigmoid threshold |
| `31_mom_universe_scan.ms` | panel momentum scan | `scan_top` / `rebalance_equal` |
| `32_bag_pair_sleeve.ms` | bag + pair sleeve | `bag_equal` / `bag_pair` |
| `33_computed_bag.ms` | computed bag sleeve | `bag_rank_mom` rematerialize |
| `34_arrow_lambdas.ms` | HOF arrows | `r => …` / `(a,b) => …` |
| `35_per_instrument_regime.ms` | per-instrument logic | `asset_is` / `asset_in` (tape asset/symbol) |
| `36_confirmation_vote.ms` | N-of-M confirmation | `count_true` / `any_of` / `all_of` |
| `37_atr_trailing_stop.ms` | volatility ratchet | `trail(k*atr)` + `return_since_entry` |
| `38_regime_strength_gate.ms` | trend-strength gate | `slope` / `zscore_roll` / `percent_rank` |
| `39_candle_reversal.ms` | candle-shape pattern | `candle_dir` / `candle_body_abs` / wicks |
| `40_setup_memory.ms` | setup memory | `bars_since(cond)` |
| `41_donchian_breakout.ms` | channel breakout | `donchian(n).upper/.lower/.mid` |
| `42_tagged_exits.ms` | exit-layer diagnostics | `flat("label")` → `exitTags` fire counts |
| `43_param_value_sweep.ms` | explicit grid sweep | `param x { values: [...] }` + `--optimize` |

Kinds `01`–`20` use the strategy surface. `21`–`22` and `23`/`30` use hscript
`@strategy` blocks to exercise that parse path. The typed surface itself now
supports fat-arrow lambdas (`r => r > 0`, `(a, b) => a - b`), the longer
`function(a, b) return a - b` form, `{ field: … }` object literals, `return`
statements, and `param x = v { min, max, step, tune }` grids — the hscript
block is a choice, not a workaround.
`24` keeps the typed `pipeline` + `strategy` surface. Example 10 runs a
`PlanRunner` optimize pass whenever a macro/pipeline is present.

Run:

```powershell
.\run.ps1 10
```
