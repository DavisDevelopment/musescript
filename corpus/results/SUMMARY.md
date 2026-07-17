# MuseScript strategy corpus

Split: IS `<= 2018-12-31`, OOS `>= 2019-01-01` on SPY daily.

## Buy-hold baseline

- IS: sharpe=0.5579 mdd=0.5519 ret=8.1040 equity=910404.59
- OOS: sharpe=0.8533 mdd=0.3368 ret=1.9831 equity=298306.76

## Strategies (latest run)

| name | IS sharpe | OOS sharpe | OOS dSharpe | OOS MDD | transfers |
|---|---:|---:|---:|---:|---|
| 00_buy_hold | 0.558 | 0.853 | +0.000 | 0.337 | is_only |
| 01_golden_cross | 0.706 | 0.468 | -0.386 | 0.342 | is_only |
| 02_sma_cross_fast | 0.427 | 0.917 | +0.064 | 0.198 | oos_only |
| 03_rsi_mean_rev | 0.373 | 0.484 | -0.369 | 0.283 | no |
| 04_rsi_dip_trend | 0.124 | 0.410 | -0.444 | 0.116 | no |
| 05_donchian | 0.270 | 0.784 | -0.070 | 0.217 | no |
| 06_dual_ma_hard_stop | 0.420 | 0.722 | -0.131 | 0.264 | no |
| 07_ema_time_stop | 0.451 | 0.918 | +0.065 | 0.182 | yes |
| 08_macd_hist | 0.307 | 0.792 | -0.061 | 0.185 | no |
| 09_atr_squeeze | 0.097 | -0.369 | -1.222 | 0.134 | no |
| 10_sma_cross_trend | 0.252 | 0.704 | -0.149 | 0.128 | no |
| 11_sma_cross_mid | 0.546 | 0.807 | -0.047 | 0.193 | is_only |
| 12_sma_mid_stop | 0.546 | 0.807 | -0.047 | 0.193 | is_only |
| 13_donchian_trend | 0.252 | 0.152 | -0.701 | 0.142 | no |
| 14_macd_trend | 0.165 | 0.850 | -0.003 | 0.098 | no |
| 15_ema_trend_time | 0.154 | 0.616 | -0.237 | 0.116 | no |
| 16_fast_ema_time | 0.338 | 1.161 | +0.308 | 0.143 | oos_only |
| 17_sma_fast_time | 0.427 | 0.917 | +0.064 | 0.198 | oos_only |
| 18_macd_soft_trend | 0.233 | 0.891 | +0.038 | 0.071 | oos_only |
| 19_ema_time_hard | 0.451 | 0.918 | +0.065 | 0.182 | yes |
| 20_mid_ema_time | 0.394 | 1.117 | +0.263 | 0.123 | yes |
| 21_fast_ema_longtime | 0.338 | 1.161 | +0.308 | 0.143 | oos_only |
| 22_fast_ema_slow_exit | 0.343 | 1.115 | +0.262 | 0.185 | oos_only |
| 23_mid_ema_time55 | 0.394 | 1.117 | +0.263 | 0.123 | yes |
| 24_ema_1321_plain | 0.394 | 1.117 | +0.263 | 0.123 | yes |
| 25_ema_2134_time | 0.649 | 0.821 | -0.032 | 0.255 | is_only |
| 30_sma_8_13 | 0.124 | 1.272 | +0.419 | 0.126 | oos_only |
| 30_sma_8_13_tx | 0.124 | 1.272 | +0.419 | 0.126 | oos_only |
| 31_ema_8_13_ex21_tx | 0.326 | 1.265 | +0.411 | 0.173 | oos_only |
| 32_ema_8_13_tx | 0.189 | 1.241 | +0.387 | 0.170 | oos_only |
| 33_ema_8_34 | 0.376 | 1.175 | +0.322 | 0.118 | yes |
| 34_sma_5_13 | 0.027 | 1.061 | +0.208 | 0.162 | oos_only |
| 35_ema_8_89 | 0.660 | 1.099 | +0.246 | 0.202 | yes |
| 36_sma_5_21 | 0.266 | 1.230 | +0.377 | 0.161 | oos_only |

## OOS-transferring edges

- **07_ema_time_stop**: OOS sharpe 0.918 (Δ +0.065), MDD 0.182 — EMA 13/34 with 55-bar time stop
- **19_ema_time_hard**: OOS sharpe 0.918 (Δ +0.065), MDD 0.182 — EMA 13/34 time stop + 5% equity hard stop
- **20_mid_ema_time**: OOS sharpe 1.117 (Δ +0.263), MDD 0.123 — EMA 13/21 with 34-bar time stop
- **23_mid_ema_time55**: OOS sharpe 1.117 (Δ +0.263), MDD 0.123 — EMA 13/21 with 55-bar time stop
- **24_ema_1321_plain**: OOS sharpe 1.117 (Δ +0.263), MDD 0.123 — EMA 13/21 cross, no time stop
- **33_ema_8_34**: OOS sharpe 1.175 (Δ +0.322), MDD 0.118 — EMA 8/34 — best IS+OOS balance from sweep
- **35_ema_8_89**: OOS sharpe 1.099 (Δ +0.246), MDD 0.202 — EMA 8/89 slow trend cross
