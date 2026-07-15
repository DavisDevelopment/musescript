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
