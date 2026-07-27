# Pine corpus triage

Generated: `2026-07-27T06:14:42.840280+00:00`

## Green rate

- Files: **470** across **6** repos
- `CLEAN_EMIT` (parse-clean + zero unsupported): **243** (51.7%)
- `UNSUPPORTED`: **174**
- `PARSE_FAIL`: **53**
- Sense-making smoke (gene-runner ok): **6/417**

## Version histogram

- v4: 7
- v5: 25
- v6: 438

## Top unknown builtins

- `float` × 283
- `request.security` × 165
- `int` × 111
- `f2` × 102
- `cell` × 55
- `time` × 43
- `log.info` × 41
- `string` × 40
- `scr_cell_title` × 38
- `draw_line` × 33
- `cell_perform` × 32
- `scr_cell` × 31
- `math.round_to_mintick` × 27
- `str.format_time` × 26
- `draw_box` × 23

## Top unsupported / other notes

- else-if chain × 212
- switch-expression not yet lowered × 79
- ta.atr (approx) × 63
- break/continue in function not yet lowered × 52
- ta.rsi (approx) × 30
- `while` loop not yet lowered × 24
- user type not yet lowered × 19
- named args on `input.float` flattened positionally × 16
- strategy order id/args dropped × 11
- named args on `input.int` flattened positionally × 10
- strategy.close (approx) × 10
- named args on `input.bool` flattened positionally × 7
- strategy.exit (approx) × 4
- named args on `input.string` flattened positionally × 3
- strategy.flat (approx) × 2

## Top parse-error prefixes

- unexpected token , × 12
- unexpected token \n × 10
- unexpected token kw(type) × 9
- unexpected token op(:=) × 5
- unexpected token >INDENT × 4
- unexpected token op(<) × 4
- expected ')' × 4
- expected ']' × 3
- unexpected token kw(method) × 1
- expected '=' × 1

## SEO / GTM angles (non-retail)

Retail Pine import is the wedge; these pull people who distrust TradingView folklore:

1. **RepaintAudit as the product** — paste Pine; show where it was lying (lookahead / `request.security`). Before/after equity on the same tape.
2. **Falsifiable parity pages** — publish this green-rate + `PineCorpusParity` bit-exact tables. Receipts over vibes.
3. **DSP / signal-processing bridge** — FIR/IIR without `max_bars_back`; partner tone with rigorous indicator collections.
4. **Portfolio / universe escape hatch** — single-symbol TV tester → Muse `runPanel` multi-name.
5. **Evolve-after-import** — import → audit → NSGA-II/NMA walk-forward.
6. **Adjacent DSLs** — ThinkScript / NinjaScript / EasyLanguage later; same honesty story.
7. **Cross-domain rigor recruit** — chess/poker/robotics/CP: state machines + adversarial eval + never-silent approx (unsupported notes as a feature).
8. **Open methodology, closed edge** — open transliterator + these reports; keep Murmuration / live edge private.

Primary magnet: **public green corpus + honest gap list + one dramatic RepaintAudit demo**.

## Next fix target

**unexpected token ,** (`PARSE_FAIL`) — 12 hits. Fix in PineParser.hx / PineLexer.hx.
