# MuseScript Tier-A bytecode VM

Portable stack VM (`musescript/vm/`) for the evo attribution-oracle hot path.
Design: `SPEC_BYTECODE_VM.md`. Execution checklist: `BYTECODE_VM_TODO.md`.

## Oracle enable

```
# CorpusEvoRun (JVM/Graal): after startup parity self-check, route Fitness.evaluate → evaluateVm
java … CorpusEvoRun … --vm

# Programmatic
Fitness.preferVm = true;   // evaluate() tries VM first; Expand→interp on VmUnsupported
```

`--vm` aborts if gen-0 seeds are not bit-identical trades/finalEquity vs interp.
Default remains OFF (V6: ~5% warm s/gen; unboxed stack is the miss-path leverage).

Escape hatches (always Expand→interp / NMA when armed):
- out-of-subset AST → `vm-unsupported` (deterministic whole-program boundary)
- panel genomes / host-projection refs → `vm-unsupported`
- `Fitness.preferNma` still runs first when set; VM is next in the chain

## Oracle-eligible (VM)

| Covered | Notes |
|---|---|
| `onBar` / `when` / `long`/`short`/`flat` | order ≤1 arg |
| locals, bar fields, arith/cmp/logic | `&&`/`\|\|` both sides (no short-circuit) |
| `if` / ternary | CMP_JZ fused |
| Prelude assigns + multiple onBars | before handlers each bar |
| `__cs` CROSS | crossover/crossunder/rising/falling |
| `CALL_BUILTIN` + `IND` static | 13 TB0 + slope/zscore_roll/percent_rank/ewm_*/hl2/hlc3/ohlc4/vwap |
| `__scr` SERIES | macd/bbands/stoch + EField |
| LOOKBACK | bar-field/`ident[n]` **and** call/expr lookback via `WITH_OFFSET` |

## Still tree-walk (Expand→interp)

arrays/objects/classes/match/loops/generators · multi-arg orders · method calls ·
user-`@indicator` `__cs` · locals shadowing bar fields · panel / host-projection genomes ·
opaque registry indicators stay `CALL_BUILTIN` (not `IND`) but still run on the VM

## Parity gates

- `TestBytecodeVmParity` / `TestVmParityCorpus` — diverged==0
- `DetParityDump` — `-- MuseVm vs MuseInterp … match=1` in golden
- JVM `--vm` startup `Fitness.vmParityCheck`
