# MuseScript Evolution Adapter (Haxe)

Strongly typed MuseGene IR + evolutionary operators authored in Haxe
(`musescript/evo/`), with Jenetics 8.3.0 available on the JVM classpath for
production population lifecycle.

```
StrategyGenome (Haxe enums)
  → Variation.mutate / crossover   (typed, no repair)
  → Expand.expand()                → MuseScript source
  → Fitness.evaluate()             → MuseCompiler (js/wasm/interp)
  → EvolutionEngine                → selection / elitism
```

Jenetics (`io.jenetics:jenetics:8.3.0`, Java 21) is the preferred host for
Engine/selection when deploying on JVM; the Haxe `EvolutionEngine` is the
reference / proof implementation so the pipeline is testable without hand-written Java.

## Build / run proof

```powershell
haxe build-evo.hxml
node build/js/evo-proof.js

haxe build-evo-jvm.hxml
java -jar build/jvm/evo-proof.jar
```

Proof checks: seeded population, typed mutation, elitism non-regression,
deterministic re-evaluation of the champion.

## JIT-audited runs (standing practice)

Any evaluation run against a `build/jvm/*.jar` evo entry point (`EvoBench`,
`CorpusEvoRun`, `EvoProof`, ...) should go through `scripts/jit_audit_run.sh`
instead of a bare `java -jar`, so a run that's silently losing throughput to
failed inlining or deopt storms shows up in a log instead of just "feeling
slower":

```bash
scripts/jit_audit_run.sh build/jvm/evo-bench.jar musescript.evo.graal.EvoBench --pop 40 --gens 10
```

Writes `build/graal/jit-audit/<mainClass>_<timestamp>/summary.txt` with top
inlining-rejection reasons and top deopting methods (musescript/haxe.jvm sites
called out separately, since those are the ones actually worth fixing vs.
JDK/Truffle internals). Never point it at `build/jvm/corpus-evo.jar` while a
background corpus-evo run has that same jar open (see `PLAN_EVO_SPEED.md`'s
hard rule) -- check `wmic process where "name='java.exe'" get CommandLine`
first.

## Layout

| module | role |
|---|---|
| `SeriesNode` / `ScalarNode` / `BoolNode` | typed IR |
| `StrategyGenome` / `EvoParam` | genome schema |
| `Palette` | closed primitive set |
| `Expand` | genome → MuseScript |
| `Canonical` | structural key + node count |
| `Variation` | grow / mutate / crossover |
| `Fitness` | compile + backtest |
| `EvolutionEngine` | tournament + elitism |
| `EvoProof` | seeded demonstration |
| `jenetics/JeneticsNotes` | classpath contract |
