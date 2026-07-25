package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.evo.EvolutionEngine;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.Canonical;
import musescript.harness.BarFeed;
import musescript.harness.Metrics;
import musescript.evo.BasketFitness;
import musescript.evo.MapElites;
import musescript.evo.MapElites.EliteArchive;
import musescript.evo.Rand;
import musescript.evo.SurrogateModel;
import musescript.evo.SymbolSelector;

/**
 * Regression + new-feature coverage for musescript.evo's Variation/EvolutionEngine/Expand --
 * previously UNCOVERED by the main test suite entirely (every prior verification of this
 * package was standalone EvoProof.hx runs and throwaway probes, never wired into
 * `node build/js/tests.js`). That gap is exactly why two real bugs (BTrend's dir string never
 * matching Expand's `dir == "up"` check, and the JVM-target Fitness.evaluate stub silently
 * ignoring `bars` and faking a nodeCount-derived result) went unnoticed for as long as they did
 * -- neither would have failed a single existing assertion.
 */
class TestEvoVariation extends Test {
	static function baseGenome(entryLong:BoolNode):StrategyGenome {
		return {
			entryLong: entryLong,
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)), // always false
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
	}

	// ── regression: BTrend dir must render to the RIGHT word ──────────────────────────────

	public function testBTrendOverRendersAsRising() {
		var s:SeriesNode = SInd("sma", "close", 8, null);
		var g = baseGenome(BTrend("over", s, 5));
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "rising("), 'expected "rising(" in: $src');
		Assert.isFalse(StringTools.contains(src, "falling("), 'did not expect "falling(" in: $src');
	}

	public function testBTrendUnderRendersAsFalling() {
		var s:SeriesNode = SInd("sma", "close", 8, null);
		var g = baseGenome(BTrend("under", s, 5));
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "falling("), 'expected "falling(" in: $src');
		Assert.isFalse(StringTools.contains(src, "rising("), 'did not expect "rising(" in: $src');
	}

	// ── regression: Fitness.evaluate must actually be sensitive to `bars` ─────────────────

	public function testFitnessEvaluateIsSensitiveToBars() {
		var g = baseGenome(BCross("over", SPrice("close"), SInd("sma", "close", 8, null)));
		var tapeA = BarFeed.synthetic(300, 1).all();
		var tapeB = BarFeed.synthetic(300, 99).all();
		var a = Fitness.evaluate(g, tapeA, "js", false);
		var b = Fitness.evaluate(g, tapeB, "js", false);
		Assert.isTrue(a.ok && b.ok);
		// Two DIFFERENT synthetic tapes (different seeds) must not produce byte-identical
		// trades/equity for a real crossover strategy -- this is exactly what the JVM
		// fake-fitness stub bug violated (identical output regardless of the bars passed in).
		Assert.isTrue(a.trades != b.trades || Math.abs(a.finalEquity - b.finalEquity) > 1e-6,
			'expected different tapes to produce different results: a=(${a.trades},${a.finalEquity}) b=(${b.trades},${b.finalEquity})');
	}

	// ── new: attribution-guided mutation prefers the low-impact node ──────────────────────

	public function testAttributedMutationPrefersTheRedundantNode() {
		// entryLong = criticalCross AND alwaysTrue -- the AND-with-true clause contributes
		// NOTHING (ablating it to "always true" changes nothing, since it already always
		// passes), while ablating the crossover condition to "always true" would make the
		// strategy enter on literally every bar -- a huge, real fitness difference. A sound
		// attribution mechanism should target the redundant `alwaysTrue` half far more often
		// than the real crossover half.
		var critical:BoolNode = BCross("over", SPrice("close"), SInd("sma", "close", 8, null));
		var redundant:BoolNode = BCmp(">", KConst(1.0), KConst(0.0)); // already always-true
		var g = baseGenome(BAnd(critical, redundant));

		var bars = BarFeed.synthetic(400, 7).all();
		var evalFn = (gn:StrategyGenome) -> Fitness.score(Fitness.evaluate(gn, bars, "js", false), 1);

		var v = new Variation(42);
		var criticalTouched = 0;
		var redundantTouched = 0;
		var trials = 60;
		for (i in 0...trials) {
			var mutated = v.attributedPointMutate(g, evalFn, 1);
			var src = Expand.expand(mutated);
			// A touched-critical mutation loses the crossover(...) call entirely from source;
			// a touched-redundant mutation keeps crossover(...) but the "1 > 0" tautology is
			// replaced by something else (or the same shape by chance).
			var stillHasCross = StringTools.contains(src, "crossover(");
			if (!stillHasCross) criticalTouched++;
			else redundantTouched++;
		}
		Assert.isTrue(redundantTouched > criticalTouched,
			'expected the redundant node to be mutated more often (redundant=$redundantTouched critical=$criticalTouched over $trials trials)');
	}

	// ── new: risk-managed exits are reachable from growth and actually execute ────────────

	/** `growRiskExit` (Variation.hx) is a new growBool terminal -- previously every genome's exit
	 * conditions could ONLY be signal-reversal shapes (BCross/BCmp/BTrend), never a stop-loss/
	 * take-profit/time-stop. Statistical reachability check (matches this file's established
	 * pattern for `testAttributedMutationPrefersTheRedundantNode`): over enough random genomes at
	 * a depth that reaches terminals, at least one must contain a risk-exit leaf in its rendered
	 * source, AND that genome must actually run without error through Fitness.evaluate -- growth
	 * alone proves reachability, evaluate() proves the render+compile+execute path is sound.
	 */
	public function testRiskManagedExitIsReachableFromGrowthAndExecutes() {
		var v = new Variation(7);
		var found = false;
		var bars = BarFeed.synthetic(300, 11).all();
		for (i in 0...80) {
			var g = v.randomGenome(3);
			var src = Expand.expand(g);
			if (StringTools.contains(src, "unrealized_pnl_pct()") || StringTools.contains(src, "bars_in_trade()")) {
				found = true;
				var r = Fitness.evaluate(g, bars, "js", false);
				Assert.isTrue(r.ok, 'risk-exit genome failed to evaluate: ${r.error}\n$src');
			}
		}
		Assert.isTrue(found, "expected at least one risk-managed-exit genome across 80 random draws");
	}

	/** `growMultiOutputField` (Variation.hx) -- macd/bbands/stoch field access, a scalar terminal.
	 * Same reachability + execution discipline as the risk-exit test above. These always take the
	 * JS-fallback path (no native WASM lowering for macd/bbands/stoch), so "js" is the only
	 * backend this needs to prove sound. */
	public function testMultiOutputFieldIsReachableFromGrowthAndExecutes() {
		var v = new Variation(13);
		var found = false;
		var bars = BarFeed.synthetic(300, 5).all();
		for (i in 0...80) {
			var g = v.randomGenome(3);
			var src = Expand.expand(g);
			if (StringTools.contains(src, "macd(") || StringTools.contains(src, "bbands(") || StringTools.contains(src, "stoch(")) {
				found = true;
				var r = Fitness.evaluate(g, bars, "js", false);
				Assert.isTrue(r.ok, 'multi-output genome failed to evaluate: ${r.error}\n$src');
			}
		}
		Assert.isTrue(found, "expected at least one multi-output-field genome across 80 random draws");
	}

	// ── new: attribution-guided crossover protects the important recipient node ───────────

	/** Mirrors testAttributedMutationPrefersTheRedundantNode's exact idea, applied to crossover's
	 * RECIPIENT-side site selection: entryLong = criticalCross AND alwaysTrue. Attribution-guided
	 * crossover should overwrite the redundant half far more often than the critical crossover half,
	 * across many trials -- exactly like the mutation-targeting test, just via
	 * attributedSubtreeCrossover instead of attributedPointMutate. */
	public function testAttributedCrossoverProtectsTheCriticalNode() {
		var critical:BoolNode = BCross("over", SPrice("close"), SInd("sma", "close", 8, null));
		var redundant:BoolNode = BCmp(">", KConst(1.0), KConst(0.0)); // already always-true
		var g1 = baseGenome(BAnd(critical, redundant));
		// Donor genome: distinct BoolNode subtrees to splice in, so a successful splice is
		// detectable (donor content differs from anything already in g1).
		var g2 = baseGenome(BCmp("<", KConst(5.0), KConst(9.0)));

		var bars = BarFeed.synthetic(400, 7).all();
		var evalFn = (gn:StrategyGenome) -> Fitness.score(Fitness.evaluate(gn, bars, "js", false), 1);

		var v = new Variation(21);
		var criticalTouched = 0;
		var redundantTouched = 0;
		var trials = 60;
		for (i in 0...trials) {
			var child = v.attributedSubtreeCrossover(g1, g2, evalFn);
			var src = Expand.expand(child);
			var stillHasCross = StringTools.contains(src, "crossover(");
			if (!stillHasCross) criticalTouched++;
			else redundantTouched++;
		}
		Assert.isTrue(redundantTouched > criticalTouched,
			'expected the redundant node to be overwritten more often (redundant=$redundantTouched critical=$criticalTouched over $trials trials)');
	}

	/** Correctness floor: the crossover-produced child must actually differ from g1 at least
	 * sometimes (donor content really gets spliced in, not silently ignored) and must always
	 * render/execute without error -- a real end-to-end check, not just structural inspection. */
	public function testAttributedCrossoverProducesValidExecutableGenomes() {
		var g1 = baseGenome(BCmp(">", KSeries(SPrice("close")), KConst(0.0)));
		var g2 = baseGenome(BTrend("over", SInd("ema", "close", 13, null), 5));
		var bars = BarFeed.synthetic(300, 17).all();
		var evalFn = (gn:StrategyGenome) -> Fitness.score(Fitness.evaluate(gn, bars, "js", false), 1);
		var v = new Variation(9);
		var changed = false;
		for (i in 0...20) {
			var child = v.attributedSubtreeCrossover(g1, g2, evalFn);
			var r = Fitness.evaluate(child, bars, "js", false);
			Assert.isTrue(r.ok, 'crossover child failed to evaluate: ${r.error}\n${Expand.expand(child)}');
			if (Canonical.structuralKey(child) != Canonical.structuralKey(g1)) changed = true;
		}
		Assert.isTrue(changed, "expected at least one crossover call to actually change the genome");
	}

	// ── new: EvolutionEngine's mutation pressure ramps up under stagnation ────────────────

	public function testMutationPressureRampsUnderStagnation() {
		var engine = new EvolutionEngine(1, 12, 2, 3);
		var pop = engine.seedPopulation(2);
		Assert.floatEquals(0.3, engine.currentMutateProb()); // baseline, zero stagnant gens yet
		// A FLAT fitness landscape (every genome scores identically) can never produce a new
		// best, so this must drive stagnantGens up every step() call AFTER the first -- the
		// first call's fitness always counts as "the first improvement" (lastBest starts at
		// -Infinity, and any real fitness beats that), so 8 calls give 7 stagnant generations.
		var flatFitness = [for (_ in pop) 0.5];
		var lastPop = pop;
		for (_ in 0...8) lastPop = engine.step(lastPop, flatFitness);
		Assert.equals(7, engine.stagnantGens);
		Assert.floatEquals(0.3 + 7 * 0.05, engine.currentMutateProb());
		Assert.equals(12, lastPop.length); // population size stays stable under repeated stagnation

		// A genuine improvement resets the counter back to zero immediately.
		var improvedFitness = [for (_ in lastPop) 5.0];
		engine.step(lastPop, improvedFitness);
		Assert.equals(0, engine.stagnantGens);
		Assert.floatEquals(0.3, engine.currentMutateProb());

		// The ramp is capped, not unbounded -- stays sane after very long stagnation.
		for (_ in 0...50) lastPop = engine.step(lastPop, flatFitness);
		Assert.isTrue(engine.currentMutateProb() <= 0.85);
	}

	// ── new: genome-expanded entries don't pyramid on a sticky condition ──────────────────

	/**
	 * Regression for a real bug: a STICKY entry condition (unlike a transient crossover, which
	 * fires once) used to re-fire `long`/`short` on every single bar it stayed true, pyramiding
	 * the position unbounded (confirmed via a standalone OrderSim probe -- see
	 * TestOrderBook.testPyramidedLongTracksWeightedAverageEntryPrice for the cost-basis half of
	 * this same bug). Fixed in Expand.hx by guarding entries on `position()`. This is the
	 * genome-EXPANSION-level check: entryLong is UNCONDITIONALLY true (never fires exitLong), so
	 * a naive expansion would enter on literally every bar -- the guard must cap it at exactly one
	 * entry fill for the whole run.
	 */
	public function testStickyAlwaysTrueEntryDoesNotPyramid() {
		var g = baseGenome(BCmp(">", KConst(1.0), KConst(0.0))); // always true, every bar
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "position() <= 0"), 'expected the entry guard in: $src');

		var bars = BarFeed.synthetic(200, 3).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok);
		Assert.equals(1, r.trades, 'expected exactly ONE entry fill despite entryLong being true every bar, got ${r.trades}');
	}

	/** A same-bar-repeatable EXIT condition is unaffected by the entry guard (exits were never the
	 * bug) -- flat() still fires whenever exitLong/exitShort holds, unconditionally, matching
	 * pre-existing (correct) behavior. */
	public function testExitGuardUnaffectedByEntryFix() {
		var g:StrategyGenome = {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)), // always true
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(1.0), KConst(0.0)), // ALSO always true -- immediate flat every bar
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
		var bars = BarFeed.synthetic(50, 3).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok);
		// Enter (position<=0 true, guard passes), immediately flat every bar -- so trades should be
		// exactly 2 per bar-cycle (enter+exit), not zero and not unboundedly growing.
		Assert.isTrue(r.trades > 0 && r.trades < 200, 'expected bounded enter/exit trade count, got ${r.trades}');
	}

	// ── new: Fitness's compiled-program cache never cross-contaminates genomes ────────────

	/**
	 * Regression guard for the compiled-program cache added to `Fitness.evaluate` (see its own
	 * doc comment -- caches the compiled `fn`/`decls` per structural key so the attribution
	 * oracle's hundreds-of-calls-per-generation stop re-parsing/re-compiling the same recurring
	 * shapes). The real risk with ANY keyed cache is cross-contamination: genome A's cached `fn`
	 * silently answering for genome B. This interleaves evaluate() calls across several
	 * DIFFERENT genomes (forcing cache hits AND misses to interleave) and asserts each genome's
	 * result stays consistent with evaluating it in complete isolation.
	 */
	public function testFitnessCacheDoesNotCrossContaminateGenomes() {
		Fitness.clearFnCache();
		var bars = BarFeed.synthetic(400, 11).all();
		var gA = baseGenome(BCross("over", SPrice("close"), SInd("sma", "close", 8, null)));
		var gB = baseGenome(BCmp(">", KSeries(SPrice("close")), KConst(5.0)));
		var gC = baseGenome(BTrend("under", SInd("ema", "close", 13, null), 5));

		var isolatedA = Fitness.evaluate(gA, bars, "js", false);
		Fitness.clearFnCache();
		var isolatedB = Fitness.evaluate(gB, bars, "js", false);
		Fitness.clearFnCache();
		var isolatedC = Fitness.evaluate(gC, bars, "js", false);
		Fitness.clearFnCache();

		// Interleave: A, B, A (hit), C, B (hit), A (hit) -- exercises both cold misses and warm
		// hits for each genome, in a shuffled order, all sharing one cache.
		var a1 = Fitness.evaluate(gA, bars, "js", false);
		var b1 = Fitness.evaluate(gB, bars, "js", false);
		var a2 = Fitness.evaluate(gA, bars, "js", false);
		var c1 = Fitness.evaluate(gC, bars, "js", false);
		var b2 = Fitness.evaluate(gB, bars, "js", false);
		var a3 = Fitness.evaluate(gA, bars, "js", false);

		for (r in [a1, a2, a3]) {
			Assert.equals(isolatedA.trades, r.trades);
			Assert.floatEquals(isolatedA.finalEquity, r.finalEquity);
		}
		for (r in [b1, b2]) {
			Assert.equals(isolatedB.trades, r.trades);
			Assert.floatEquals(isolatedB.finalEquity, r.finalEquity);
		}
		Assert.equals(isolatedC.trades, c1.trades);
		Assert.floatEquals(isolatedC.finalEquity, c1.finalEquity);
	}

	/** Same structural genome, different `target`/`strict` -- must NOT share a cache slot (the
	 * key includes both), since a different target can legitimately compile to a different
	 * backend/behavior path. */
	public function testFitnessCacheKeyIncludesTargetAndStrict() {
		Fitness.clearFnCache();
		var g = baseGenome(BCmp(">", KSeries(SPrice("close")), KConst(1.0)));
		var bars = BarFeed.synthetic(200, 5).all();
		var jsResult = Fitness.evaluate(g, bars, "js", false);
		var nativeResult = Fitness.evaluate(g, bars, "native", false); // MuseCompiler's documented interp-fallback target
		Assert.isTrue(jsResult.ok && nativeResult.ok);
		Assert.equals("interp", nativeResult.backend);
		Assert.equals(jsResult.trades, nativeResult.trades);
		Assert.floatEquals(jsResult.finalEquity, nativeResult.finalEquity);
	}

	// ── template holes (BHole/KHole): opt-in mutation/crossover restriction ───────────────

	/** BHole/KHole must be fully transparent to the emitted source -- a hole-wrapped genome and
	 * its bare-unwrapped equivalent compile to byte-identical MuseScript. */
	public function testExpandUnwrapsHoleTransparently() {
		var unwrapped:BoolNode = BAnd(BCmp(">", KSeries(SPrice("close")), KConst(1.0)), BCmp("<", KSeries(SPrice("open")), KConst(5.0)));
		var wrappedA:BoolNode = BAnd(BHole(BCmp(">", KSeries(SPrice("close")), KConst(1.0))), BCmp("<", KSeries(SPrice("open")), KConst(5.0)));
		var wrappedB:BoolNode = BAnd(BCmp(">", KSeries(SPrice("close")), KConst(1.0)), BCmp("<", KSeries(SPrice("open")), KHole(KConst(5.0))));
		var base = Expand.expand(baseGenome(unwrapped));
		Assert.equals(base, Expand.expand(baseGenome(wrappedA)));
		Assert.equals(base, Expand.expand(baseGenome(wrappedB)));
	}

	/** Structural key and node count must ignore hole wrappers -- a hole-wrapped subtree shares
	 * ONE fitness-cache entry and ONE parsimony cost with its bare equivalent (see Canonical.hx's
	 * KHole/BHole doc comments). */
	public function testCanonicalIsTransparentThroughHoles() {
		var bareCond:BoolNode = BCmp(">", KSeries(SPrice("close")), KConst(5.0));
		var holeCond:BoolNode = BHole(bareCond);
		var gBare = baseGenome(bareCond);
		var gHole = baseGenome(holeCond);
		Assert.equals(Canonical.structuralKey(gBare), Canonical.structuralKey(gHole));
		Assert.equals(Canonical.nodeCount(gBare), Canonical.nodeCount(gHole));
	}

	/** A genome with zero BHole/KHole anywhere must report `isTemplated == false` -- the gate that
	 * keeps hole-restricted evolution strictly opt-in (every genome random growth/crossover/plain
	 * corpus-seeding ever produces has no holes, so this must stay false for all of them). */
	public function testIsTemplatedFalseWithoutHoles() {
		var g = baseGenome(BAnd(BCmp(">", KSeries(SPrice("close")), KConst(1.0)), BCmp("<", KSeries(SPrice("open")), KConst(5.0))));
		Assert.isFalse(Variation.isTemplated(g));
	}

	public function testIsTemplatedTrueWithHoleAnywhere() {
		var gBool = baseGenome(BAnd(BHole(BCmp(">", KConst(1.0), KConst(0.0))), BCmp("<", KConst(1.0), KConst(2.0))));
		Assert.isTrue(Variation.isTemplated(gBool));
		var gScalar = baseGenome(BCmp(">", KSeries(SPrice("close")), KHole(KConst(5.0))));
		Assert.isTrue(Variation.isTemplated(gScalar));
	}

	/**
	 * The core contract: repeated `pointMutate` on a templated genome must NEVER touch anything
	 * outside a `BHole` -- the frozen skeleton (the top-level `BAnd`'s first operand, entirely
	 * hole-free) must come out structurally IDENTICAL after every single mutation, across many
	 * iterations and both a fresh and an already-mutated starting genome, while the hole's own
	 * content is free to change. Also confirms the OTHER three bool slots (entryShort/exitLong/
	 * exitShort) and `size` -- all hole-free in this fixture -- are never touched either: since the
	 * genome AS A WHOLE is templated, an untouched slot has zero candidate positions at all.
	 */
	public function testTemplatedGenomeMutationNeverTouchesFrozenSkeleton() {
		var frozen:BoolNode = BCmp(">", KSeries(SPrice("close")), KSeries(SPrice("open")));
		var holeStart:BoolNode = BCmp(">", KConst(50.0), KConst(0.0));
		var g:StrategyGenome = baseGenome(BAnd(frozen, BHole(holeStart)));
		Assert.isTrue(Variation.isTemplated(g));

		var v = new Variation(42);
		var cur = g;
		var sawChange = false;
		for (i in 0...60) {
			cur = v.pointMutate(cur);
			switch (cur.entryLong) {
				case BAnd(a, b):
					Assert.isTrue(Type.enumEq(a, frozen), 'frozen skeleton mutated at iteration $i: $a');
					if (!Type.enumEq(b, BHole(holeStart))) sawChange = true;
					switch (b) {
						case BHole(_): // still a hole -- wrapper survived
						default: Assert.fail('hole wrapper was destroyed at iteration $i: $b');
					}
				default:
					Assert.fail('top-level BAnd skeleton was replaced entirely at iteration $i: ${cur.entryLong}');
			}
			// Every other slot is hole-free -- must stay byte-identical to baseGenome's fixed defaults.
			Assert.isTrue(Type.enumEq(cur.entryShort, BCmp(">", KConst(0.0), KConst(1.0))), 'entryShort touched at iteration $i');
			Assert.isTrue(Type.enumEq(cur.exitLong, BCmp(">", KConst(0.0), KConst(1.0))), 'exitLong touched at iteration $i');
			Assert.isTrue(Type.enumEq(cur.exitShort, BCmp(">", KConst(0.0), KConst(1.0))), 'exitShort touched at iteration $i');
			Assert.isTrue(Type.enumEq(cur.size, KConst(1.0)), 'size touched at iteration $i');
		}
		Assert.isTrue(sawChange, "expected the hole's content to actually change over 60 mutations");
	}

	/** `subtreeCrossover` respects the same hole restriction on the RECIPIENT side: crossing a
	 * templated genome with an ordinary (untemplated) donor must still leave the recipient's
	 * frozen skeleton untouched, with fresh content only landing inside the hole. */
	public function testTemplatedGenomeCrossoverStaysWithinHole() {
		var frozen:BoolNode = BCmp(">", KSeries(SPrice("close")), KSeries(SPrice("open")));
		var g1:StrategyGenome = baseGenome(BAnd(frozen, BHole(BCmp(">", KConst(1.0), KConst(0.0)))));
		var g2:StrategyGenome = baseGenome(BCmp("<", KSeries(SPrice("close")), KConst(42.0))); // plain, untemplated donor

		var v = new Variation(7);
		for (i in 0...30) {
			var child = v.subtreeCrossover(g1, g2);
			switch (child.entryLong) {
				case BAnd(a, _):
					Assert.isTrue(Type.enumEq(a, frozen), 'frozen skeleton mutated by crossover at iteration $i: $a');
				default:
					Assert.fail('top-level BAnd skeleton was replaced by crossover at iteration $i: ${child.entryLong}');
			}
		}
	}

	/** `CorpusSeed`'s `evolve(...)` marker must translate to a `BHole`/`KHole` wrapping exactly
	 * the marked sub-expression, leaving everything else in the strategy bare. */
	public function testCorpusSeedEvolveMarkerProducesHole() {
		var src = 'strategy T {
			onBar {
				when (close > open) && evolve(close > 70): { long() }
			}
		}';
		var prog = new musescript.parse.MuseParser().parse(src, "<test>");
		var g = musescript.evo.CorpusSeed.translateProgram(prog, new Map());
		Assert.notNull(g);
		switch (g.entryLong) {
			case BAnd(a, b):
				switch (a) {
					case BCmp(">", KSeries(SPrice("close")), KSeries(SPrice("open"))): // bare, no hole
					default: Assert.fail('expected the "close > open" clause to be bare (no hole): $a');
				}
				switch (b) {
					case BHole(BCmp(">", KSeries(SPrice("close")), KConst(70.0))): // wrapped, as marked
					default: Assert.fail('expected the evolve(...)-marked clause to be a BHole: $b');
				}
			default:
				Assert.fail('expected entryLong to be a top-level BAnd: ${g.entryLong}');
		}
		Assert.isTrue(Variation.isTemplated(g));
	}

	/**
	 * `Expand.expand` -> `CorpusSeed.translateSource` must round-trip for an ordinary (no-hole)
	 * genome -- this is the exact path `HumanLoopWindow`'s "Apply Edit" button exercises on
	 * whatever's currently in the editor, which starts as `Expand.expand(selectedGenome)`.
	 * Regression coverage for a real bug: `Expand` used to emit the legacy `{ @strategy(...)
	 * @on(bar) { if (cond) long(); } }` annotation dialect, whose braceless `if` doesn't produce
	 * the `When`/general-`if`-with-`EBlock` shape `CorpusSeed.guardedOrders` requires -- every
	 * such round trip failed with "no translatable strategy body" until `Expand` switched to
	 * emitting the modern `strategy { onBar { when cond: { ... } } }` surface instead.
	 */
	public function testExpandRoundTripsThroughCorpusSeedTranslateSource() {
		var g = baseGenome(BCross("over", SPrice("close"), SInd("sma", "close", 8, null)));
		g.entryShort = BCmp("<", KSeries(SPrice("close")), KConst(42.0));
		var src = Expand.expand(g);
		var allowed = new Map<String, Bool>();
		allowed.set("sma", true);
		var res = musescript.evo.CorpusSeed.translateSource(src, allowed);
		Assert.notNull(res.genome, 'round trip failed: ${res.error}\nsource was:\n$src');
		// NOT structural-key equality: `Expand` merges exitLong/exitShort into ONE OR'd `flat()`
		// condition (a single MuseScript strategy has no way to say "this flat() call only fires
		// on the long side"), so CorpusSeed's reverse mapping can't losslessly split that back into
		// two independent slots -- both come back as the SAME merged OR, which is a structurally
		// different (though behaviorally equivalent, since this fixture's exitLong/exitShort were
		// identical `alwaysFalse()` placeholders to begin with) shape. Behavioral equivalence on a
		// real backtest is the meaningful round-trip guarantee here, not byte-identical structure.
		var bars = BarFeed.synthetic(300, 5).all();
		var frOrig = Fitness.evaluate(g, bars, "js", false);
		var frRound = Fitness.evaluate(res.genome, bars, "js", false);
		Assert.isTrue(frOrig.ok && frRound.ok);
		Assert.equals(frOrig.trades, frRound.trades);
		Assert.floatEquals(frOrig.finalEquity, frRound.finalEquity);
	}

	/** Same round trip, but with a minted `@param` -- confirms the parenthesized
	 * `strategy Name(p0 = 1.5) { ... }` param-list form Expand now emits at least PARSES and
	 * BACKTESTS correctly (param-reference recovery in CorpusSeed itself is a separate, pre-
	 * existing limitation -- not something this test claims to cover). */
	public function testExpandWithParamsStillCompilesAndRuns() {
		var g = baseGenome(BCmp(">", KSeries(SPrice("close")), KParam(0)));
		g.params = [{ name: "p0", defaultValue: 50.0, min: 0.0, max: 100.0, step: 0.5, tune: "grid" }];
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "p0 = 50"), 'expected a p0=50 param decl in: $src');
		var bars = BarFeed.synthetic(200, 3).all();
		var fr = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(fr.ok, 'expected a params-bearing genome to still compile+run: ${fr.error}');
	}

	/**
	 * `CorpusSeed.translateScalar`'s multi-output `EField` case used to require the DIRECT-INLINE
	 * spelling (`macd(...).hist`) -- a PRELUDE-BOUND variable's field access (`m = macd(...); ...
	 * m.hist ...`, the natural way a hand-written strategy avoids repeating a long indicator call)
	 * fell through to `default: null` instead, since `resolve()`'s single top-level call in
	 * translateScalar never looks INSIDE the `EField`'s own child node. Found via a real tournament-
	 * corpus strategy failing to inject through HumanLoopWindow. Only the COMPARISON use (`m.hist <
	 * 0`) is fixed by this -- `rising(m.hist, 3)`-style trend/cross calls on a multi-output field
	 * remain structurally unrepresentable (BTrend/BCross require a SeriesNode operand; a multi-
	 * output field can only ever be a KFeature ScalarNode, the same reason CorpusSeed's own
	 * `crossUpScalar`/`crossDownScalar` helpers exist for fib_retracement) -- a real, separate,
	 * deeper limitation this test does NOT claim to cover.
	 */
	public function testCorpusSeedResolvesBoundMultiOutputFieldAccess() {
		var src = 'strategy T {
			m = macd(close, 12, 26, 9)
			onBar {
				when m.hist < 0: { long() }
			}
		}';
		var prog = new musescript.parse.MuseParser().parse(src, "<test>");
		var g = musescript.evo.CorpusSeed.translateProgram(prog, new Map());
		Assert.notNull(g, "expected m.hist (bound multi-output field) to translate in a comparison");
		switch (g.entryLong) {
			case BCmp("<", KFeature(f), KConst(0.0)):
				Assert.isTrue(StringTools.contains(f, "macd(") && StringTools.contains(f, ".hist"),
					'expected a macd(...).hist KFeature, got: $f');
			default:
				Assert.fail('expected a BCmp(<, KFeature(macd...hist), KConst(0)): ${g.entryLong}');
		}
	}

	/**
	 * `onPosition { when ...: { flat() } }` risk-managed exits (stop-loss/time-stop/take-profit
	 * templates -- see corpus_tournament examples) used to be silently dropped entirely
	 * (`translateStrategy` only ever scanned `OnBar` bodies) -- found via a real tournament-corpus
	 * strategy (composed of `Stop`/`TimeCap`/`ProfitCap` templates, all `onPosition`-based) failing
	 * to inject through HumanLoopWindow. Also covers the BARE-identifier spelling of risk-exit
	 * features (`bars_in_trade`/`equity`/`unrealized_pnl`, no parens) -- confirmed via
	 * examples/strategy-kinds/06_risk_window_sortino.ms that this is the actually-idiomatic
	 * MuseScript spelling, not just the parenthesized `bars_in_trade()` form growRiskExit renders.
	 */
	public function testOnPositionRiskExitsWithBareFeaturesTranslate() {
		var src = 'strategy T {
			onBar {
				when close > open: { long() }
			}
			onPosition {
				when unrealized_pnl < -0.05 * equity: { flat() }
				when bars_in_trade >= 13: { flat() }
			}
		}';
		var prog = new musescript.parse.MuseParser().parse(src, "<test>");
		var g = musescript.evo.CorpusSeed.translateProgram(prog, new Map());
		Assert.notNull(g, "expected onPosition risk-exit guards to translate");
		// Both onPosition guards OR into exitLong/exitShort (folded in alongside onBar's own,
		// which contributed none here) -- just confirm SOME real (non-alwaysFalse) exit condition
		// landed, without over-specifying the exact BAnd/BOr shape.
		var isAlwaysFalse = switch (g.exitLong) { case BCmp(">", KConst(0.0), KConst(1.0)): true; default: false; };
		Assert.isFalse(isAlwaysFalse, 'expected a real exit condition from onPosition, got: ${g.exitLong}');
	}

	// ── regression: a bankrupt (negative-equity) account must never score a GOOD sharpe ────

	/**
	 * Real bug, found via this exact scenario: a genome whose `size` grew to a raw `volume`
	 * scalar (buying/shorting literally the bar's share volume every trade) blew an account to
	 * -$11B equity -- and scored fitness=4.6655, the single best result of an entire session's
	 * worth of runs (every honest champion otherwise sat at 0.4-0.9), because
	 * `Metrics.returnsFromEquity` divided two NEGATIVE numbers on every further loss once equity
	 * went negative, producing a fabricated POSITIVE return for each one. A monotonically
	 * worsening equity curve that crosses zero must produce a strongly NEGATIVE sharpe, never a
	 * strongly positive one, regardless of how far into negative territory it goes.
	 */
	public function testBankruptEquityCurveDoesNotScoreArtificiallyHighSharpe() {
		// Starts positive, crosses zero, then gets steadily MORE negative -- exactly the shape
		// the exploit produced (a wipeout followed by continued "losses" past zero).
		var equity = [100000.0, 50000.0, -20000.0, -40000.0, -80000.0, -160000.0, -320000.0];
		var rets = Metrics.returnsFromEquity(equity);
		// The wipeout transition (50000 -> -20000) is a real, correctly-signed catastrophic loss.
		Assert.isTrue(rets[1] < -1.0, 'expected the wipeout bar to be a large negative return, got ${rets[1]}');
		// Every return AFTER equity has already gone non-positive must be exactly 0.0 -- not a
		// fabricated positive number from dividing two negatives (the bug), and not a fabricated
		// negative number either (there is no capital left to compute a percentage return on).
		for (i in 2...rets.length) Assert.floatEquals(0.0, rets[i], 'expected 0.0 post-wipeout, got ${rets[i]} at index $i');
		var sh = Metrics.sharpe(rets, 0);
		Assert.isTrue(sh < 0, 'expected a bankrupt account to score a NEGATIVE sharpe, got $sh');
	}

	/** Ordinary all-positive equity curves are byte-for-byte unaffected by the `prev > 0` guard
	 * (every `prev` in a normal, never-bankrupt curve is already positive). */
	public function testReturnsFromEquityUnchangedForPositiveCurve() {
		var equity = [100000.0, 101000.0, 99500.0, 103000.0];
		var rets = Metrics.returnsFromEquity(equity);
		Assert.floatEquals((101000.0 - 100000.0) / 100000.0, rets[0]);
		Assert.floatEquals((99500.0 - 101000.0) / 101000.0, rets[1]);
		Assert.floatEquals((103000.0 - 99500.0) / 99500.0, rets[2]);
	}

	// ── BasketFitness: multi-symbol aggregation (see this session's multi-symbol plan) ────

	/** Ordinary case: all symbols valid -- trades sum, sharpe means, equity sums. */
	public function testAggregateBasketSumsTradesAndEquityMeansSharpe() {
		var results = [
			{trades: 10, sharpe: 0.8, finalEquity: 1000.0},
			{trades: 20, sharpe: 0.4, finalEquity: 2000.0},
			{trades: 30, sharpe: 0.6, finalEquity: -500.0},
		];
		var agg = BasketFitness.aggregateBasket(results);
		Assert.equals(60, agg.trades);
		Assert.floatEquals((0.8 + 0.4 + 0.6) / 3, agg.sharpe);
		Assert.floatEquals(2500.0, agg.finalEquity);
	}

	/** A single-element basket (the plain `--tape` degenerate case) must reproduce that ONE
	 * result's trades/sharpe/equity exactly -- CorpusEvoRun's whole "zero behavior change without
	 * `--tapes`" guarantee rests on this. */
	public function testAggregateBasketSingleElementIsUnchanged() {
		var agg = BasketFitness.aggregateBasket([{trades: 143, sharpe: 0.8251, finalEquity: 100009.28}]);
		Assert.equals(143, agg.trades);
		Assert.floatEquals(0.8251, agg.sharpe);
		Assert.floatEquals(100009.28, agg.finalEquity);
	}

	/** A genome invalid (no trades, or a NaN sharpe -- a blowup) on ANY one symbol must make the
	 * WHOLE aggregate invalid, even if it looks great on every other symbol -- silently averaging
	 * a blowup away is exactly the kind of exploitable blind spot the `Metrics.returnsFromEquity`
	 * bug (found this same session) showed evolution WILL find and reward, given the chance. */
	public function testAggregateBasketAnyInvalidSymbolInvalidatesWhole() {
		var greatExceptOneBlowup = [
			{trades: 50, sharpe: 1.2, finalEquity: 5000.0},
			{trades: 0, sharpe: Math.NaN, finalEquity: 100000.0}, // never traded on this symbol
			{trades: 40, sharpe: 0.9, finalEquity: 3000.0},
		];
		var agg = BasketFitness.aggregateBasket(greatExceptOneBlowup);
		Assert.equals(0, agg.trades);
		Assert.isTrue(Math.isNaN(agg.sharpe));

		var noTradesOnOneSymbol = [
			{trades: 12, sharpe: 0.5, finalEquity: 1000.0},
			{trades: 0, sharpe: 0.0, finalEquity: 100000.0}, // trades=0 but sharpe happens to be a real number
		];
		var agg2 = BasketFitness.aggregateBasket(noTradesOnOneSymbol);
		Assert.equals(0, agg2.trades);
		Assert.isTrue(Math.isNaN(agg2.sharpe));
	}

	/** `weights` (CorpusEvoRun's `--curriculum`) must match a hand-computed weighted mean, and
	 * omitting it must be BYTE-IDENTICAL to the plain-mean behavior tested above -- the same
	 * "opt-in, zero behavior change" guarantee every flag this session ships with. */
	public function testAggregateBasketWeightedMeanMatchesHandComputation() {
		var results = [
			{trades: 10, sharpe: 1.0, finalEquity: 1000.0},
			{trades: 10, sharpe: 0.0, finalEquity: 1000.0},
		];
		var agg = BasketFitness.aggregateBasket(results, [3.0, 1.0]); // 3:1 weighted toward symbol 0
		Assert.floatEquals((1.0 * 3.0 + 0.0 * 1.0) / 4.0, agg.sharpe);
		var aggUnweighted = BasketFitness.aggregateBasket(results);
		Assert.floatEquals(0.5, aggUnweighted.sharpe); // plain mean, confirms weights==null path untouched
	}

	// ── Canonical.shapeSignature/shapeDistance: speciation's structural fingerprint ────────

	/** Two genomes built from the exact same node-constructor kinds (just different constants/
	 * indicator names) must have IDENTICAL shape signatures -- speciation groups by STRUCTURE,
	 * not by the specific values inside it. */
	public function testShapeSignatureIgnoresLeafValuesNotShape() {
		var a = baseGenome(BCmp(">", KSeries(SPrice("close")), KConst(5.0)));
		var b = baseGenome(BCmp("<", KSeries(SPrice("open")), KConst(42.0)));
		var sigA = Canonical.shapeSignature(a);
		var sigB = Canonical.shapeSignature(b);
		Assert.equals(0, Canonical.shapeDistance(sigA, sigB));
	}

	/** A genuinely different SHAPE (an extra BAnd wrapping a second comparison) must register a
	 * nonzero distance -- otherwise speciation could never actually separate anything. */
	public function testShapeSignatureDetectsRealShapeDifference() {
		var simple = baseGenome(BCmp(">", KSeries(SPrice("close")), KConst(5.0)));
		var compound = baseGenome(BAnd(BCmp(">", KSeries(SPrice("close")), KConst(5.0)), BCmp("<", KSeries(SPrice("open")), KConst(1.0))));
		var d = Canonical.shapeDistance(Canonical.shapeSignature(simple), Canonical.shapeSignature(compound));
		Assert.isTrue(d > 0, 'expected a nonzero shape distance between a bare BCmp and a BAnd of two BCmps, got $d');
	}

	// ── MapElites.noveltyDistance: k-nearest-archived-exemplar novelty bonus ───────────────

	/** An empty archive must report zero novelty (nothing to be novel RELATIVE TO yet) -- a
	 * generation-0 call with an empty archive must be a harmless no-op, not a crash or an
	 * arbitrary bonus. */
	public function testNoveltyDistanceIsZeroForEmptyArchive() {
		var archive = new EliteArchive();
		Assert.floatEquals(0.0, archive.noveltyDistance(0.05, 10.0, 0.5));
	}

	/** A descriptor identical to an already-archived one scores zero novelty; a descriptor far
	 * from everything archived scores meaningfully higher -- confirms the distance actually
	 * discriminates near from far, not just "any nonzero archive returns some constant". */
	public function testNoveltyDistanceDiscriminatesNearFromFar() {
		var archive = new EliteArchive();
		var g = baseGenome(BCmp(">", KConst(1.0), KConst(0.0)));
		archive.offer(g, 0.5, "1_1_1", 0.05, 10.0, 0.5);
		var near = archive.noveltyDistance(0.05, 10.0, 0.5);
		var far = archive.noveltyDistance(0.3, 60.0, 0.95);
		Assert.floatEquals(0.0, near);
		Assert.isTrue(far > near, 'expected a far descriptor to score higher novelty than an identical one: far=$far near=$near');
	}

	// ── Variation.esNudgeParam: (1+1)-ES local param tuning ────────────────────────────────

	/** A genome with no params at all is a pure no-op -- no crash, nothing to nudge. */
	public function testEsNudgeParamNoOpWithoutParams() {
		var g = baseGenome(BCmp(">", KConst(1.0), KConst(0.0)));
		var v = new Variation(1);
		var result = v.esNudgeParam(g, function(_) return 0.0, new Rand(5));
		Assert.equals(0, result.params.length);
	}

	/** Deterministic hill-climb check, decoupled from real backtest randomness: a synthetic
	 * `evalFn` peaked at a known target value -- repeated nudges must move the param STRICTLY
	 * closer to that target than where it started (each individual nudge is accept-if-strictly-
	 * better, so the sequence can never regress; enough tries from a bad starting point must find
	 * at least some real improvement). */
	public function testEsNudgeParamHillClimbsTowardBetterParamValue() {
		var target = 42.0;
		var g = baseGenome(BCmp(">", KSeries(SPrice("close")), KParam(0)));
		g.params = [{ name: "p0", defaultValue: 0.0, min: -100.0, max: 100.0, step: 1.0, tune: "grid" }];
		var evalFn = function(cand:StrategyGenome):Float return -Math.abs(cand.params[0].defaultValue - target);
		var v = new Variation(3);
		var rng = new Rand(11);
		var cur = g;
		var prevScore = evalFn(cur);
		for (_ in 0...200) {
			cur = v.esNudgeParam(cur, evalFn, rng);
			var score = evalFn(cur);
			Assert.isTrue(score >= prevScore, 'expected a (1+1)-ES step to never regress: prev=$prevScore now=$score');
			prevScore = score;
		}
		var finalDist = Math.abs(cur.params[0].defaultValue - target);
		var startDist = Math.abs(g.params[0].defaultValue - target);
		Assert.isTrue(finalDist < startDist, 'expected hill-climbing toward target=$target: start=${g.params[0].defaultValue} final=${cur.params[0].defaultValue}');
	}

	// ── Canonical.shapeFeatures + SurrogateModel: opt-in --surrogate pre-filter ────────────

	/** Fixed-length regardless of genome size/shape -- the whole point of a feature vector a
	 * linear model can consume uniformly. */
	public function testShapeFeaturesFixedLength() {
		var small = baseGenome(BCmp(">", KConst(1.0), KConst(0.0)));
		var big = baseGenome(BAnd(BAnd(BCmp(">", KSeries(SPrice("close")), KConst(1.0)), BCmp("<", KSeries(SPrice("open")), KConst(2.0))),
			BOr(BNot(BCmp(">", KConst(3.0), KConst(4.0))), BTrend("over", SInd("sma", "close", 8, null), 5))));
		var fSmall = Canonical.shapeFeatures(small);
		var fBig = Canonical.shapeFeatures(big);
		Assert.equals(fSmall.length, fBig.length);
	}

	/** Two structurally-different genomes must produce DIFFERENT feature vectors -- otherwise the
	 * surrogate has nothing to learn from. */
	public function testShapeFeaturesDistinguishesDifferentShapes() {
		var a = Canonical.shapeFeatures(baseGenome(BCmp(">", KConst(1.0), KConst(0.0))));
		var b = Canonical.shapeFeatures(baseGenome(BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(2.0), KConst(3.0)))));
		var same = true;
		for (i in 0...a.length) if (Math.abs(a[i] - b[i]) > 1e-9) same = false;
		Assert.isFalse(same, "expected a bare BCmp and a BAnd-of-two-BCmps to have different feature vectors");
	}

	/** Deterministic learning check: train on a synthetic linear pattern (target = features[0])
	 * and confirm predictions actually converge toward it -- decoupled from real backtest
	 * randomness, same style as `testEsNudgeParamHillClimbsTowardBetterParamValue`. */
	public function testSurrogateModelLearnsASimpleLinearPattern() {
		var model = new SurrogateModel(3, 0.1);
		var features = [1.0, 0.0, 0.0];
		var target = 2.5;
		var before = Math.abs(model.predict(features) - target);
		for (_ in 0...200) model.update(features, target);
		var after = Math.abs(model.predict(features) - target);
		Assert.isTrue(after < before, 'expected prediction to converge toward the target: before=$before after=$after');
		Assert.isTrue(after < 0.1, 'expected a near-exact fit on a single-feature linear pattern after 200 updates, got error=$after');
	}

	/** A non-finite target (NaN/Infinity -- an invalid genome's raw sharpe, before a caller
	 * clamps it to a sentinel) must never corrupt the weights. */
	public function testSurrogateModelIgnoresNonFiniteTarget() {
		var model = new SurrogateModel(2, 0.1);
		model.update([1.0, 1.0], Math.NaN);
		model.update([1.0, 1.0], Math.POSITIVE_INFINITY);
		Assert.equals(0.0, model.predict([1.0, 1.0]), "expected weights untouched by non-finite targets");
		Assert.equals(0, model.samplesSeen);
	}

	/** `save`/`load` round-trip: a freshly-loaded model must predict IDENTICALLY to the one that
	 * saved it. */
	public function testSurrogateModelSaveLoadRoundTrips() {
		var model = new SurrogateModel(3, 0.1);
		for (_ in 0...50) model.update([1.0, 0.5, -0.5], 1.7);
		var path = "build/js/.surrogate-test-tmp.tsv";
		model.save(path);
		var loaded = new SurrogateModel(3, 0.1);
		loaded.load(path);
		Assert.floatEquals(model.predict([1.0, 0.5, -0.5]), loaded.predict([1.0, 0.5, -0.5]));
		sys.FileSystem.deleteFile(path);
	}

	/** Loading a file with the WRONG vector length (a stale save from a different `SHAPE_KINDS`
	 * vocabulary) must be silently ignored, not crash or corrupt the freshly-constructed zero
	 * weights. */
	public function testSurrogateModelLoadIgnoresWrongLength() {
		var path = "build/js/.surrogate-test-wronglen-tmp.tsv";
		sys.io.File.saveContent(path, "1.0\t2.0\t3.0"); // 3 numbers, but this model expects 5+1=6
		var model = new SurrogateModel(5, 0.1);
		model.load(path);
		Assert.equals(0.0, model.predict([1.0, 1.0, 1.0, 1.0, 1.0]), "expected the malformed-length file to be ignored, weights stay zero");
		sys.FileSystem.deleteFile(path);
	}

	// ── Fitness.evaluate's `initialCash`/`equityFloor` threading (sim-tape bankruptcy crank) ──
	//
	// These deliberately don't try to model a realistic crashing tape -- OrderSim's own
	// MAX_POSITION_FRACTION risk cap means a SINGLE entry can only ever put 25% of cash at risk
	// (see testExplicitQtyClampedToRiskFractionOfCapital in TestOrderBook.hx), so genuinely
	// wiping out a small account within a short synthetic tape needs several compounding round
	// trips -- unnecessary complexity for what's really a WIRING test. Setting `equityFloor`
	// ABOVE `initialCash` makes the very first `mark()` call (bar 0, before any trade fires)
	// trip the flag deterministically -- proof the params actually reach `OrderSim`, independent
	// of genome/strategy behavior.

	public function testFitnessEvaluateBankruptFalseByDefault() {
		var g = baseGenome(BCmp(">", KConst(0.0), KConst(1.0))); // never enters -- irrelevant here
		var bars = BarFeed.synthetic(50, 1).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isFalse(r.bankrupt);
	}

	public function testFitnessEvaluateEquityFloorCatchesBankruptcy() {
		var g = baseGenome(BCmp(">", KConst(0.0), KConst(1.0)));
		var bars = BarFeed.synthetic(50, 1).all();
		var r = Fitness.evaluate(g, bars, "js", false, 0, 100, 1000); // floor ABOVE starting cash
		Assert.isTrue(r.bankrupt, "expected starting cash below the floor to trip bankrupt on bar 0's mark()");
	}

	public function testFitnessEvaluateNoFloorMeansNeverBankrupt() {
		var g = baseGenome(BCmp(">", KConst(0.0), KConst(1.0)));
		var bars = BarFeed.synthetic(50, 1).all();
		var r = Fitness.evaluate(g, bars, "js", false, 0, 100, 0.0); // same tiny cash, floor disabled
		Assert.isFalse(r.bankrupt);
	}

	// ── SymbolSelector: co-evolved market-selection preference (Part A) ──────────────────────

	public function testSymbolSelectorScoreIsPlainDotProduct() {
		var s = new SymbolSelector(3, new Rand(1));
		s.weights = [2.0, -1.0, 0.5];
		Assert.floatEquals(2.0 * 1.0 + -1.0 * 2.0 + 0.5 * 4.0, s.score([1.0, 2.0, 4.0]));
	}

	public function testSymbolSelectorScoreTreatsMissingFeaturesAsZero() {
		var s = new SymbolSelector(3, new Rand(1));
		s.weights = [1.0, 1.0, 1.0];
		Assert.floatEquals(5.0, s.score([5.0])); // only feature 0 present; 1,2 contribute 0
	}

	public function testSymbolSelectorCrossoverIsDeterministicGivenSeed() {
		var a = new SymbolSelector(4, new Rand(1));
		var b = new SymbolSelector(4, new Rand(2));
		var c1 = SymbolSelector.crossover(a, b, new Rand(42));
		var c2 = SymbolSelector.crossover(a, b, new Rand(42));
		Assert.equals(c1.weights.length, c2.weights.length);
		for (i in 0...c1.weights.length) Assert.floatEquals(c1.weights[i], c2.weights[i]);
	}

	public function testSymbolSelectorCrossoverChildWeightsComeFromEitherParent() {
		var a = new SymbolSelector(4, new Rand(1));
		a.weights = [1.0, 1.0, 1.0, 1.0];
		var b = new SymbolSelector(4, new Rand(2));
		b.weights = [2.0, 2.0, 2.0, 2.0];
		var child = SymbolSelector.crossover(a, b, new Rand(7));
		for (w in child.weights) Assert.isTrue(w == 1.0 || w == 2.0, 'expected every child gene to come from a parent, got $w');
	}

	public function testSymbolSelectorMutateChangesWeightsAtFullRate() {
		var s = new SymbolSelector(4, new Rand(1));
		s.weights = [0.0, 0.0, 0.0, 0.0];
		var mutated = s.mutate(new Rand(9), 1.0); // rate=1.0 -- every gene nudged
		var anyChanged = false;
		for (i in 0...s.weights.length) if (mutated.weights[i] != s.weights[i]) anyChanged = true;
		Assert.isTrue(anyChanged, "expected at least one weight to change at mutation rate 1.0");
	}

	public function testSymbolSelectorMutateRateZeroLeavesWeightsUnchanged() {
		var s = new SymbolSelector(4, new Rand(1));
		s.weights = [1.0, 2.0, 3.0, 4.0];
		var mutated = s.mutate(new Rand(9), 0.0); // rate=0.0 -- never nudged
		for (i in 0...s.weights.length) Assert.floatEquals(s.weights[i], mutated.weights[i]);
	}

	public function testSymbolSelectorSaveLoadRoundTrips() {
		var s = new SymbolSelector(4, new Rand(1));
		s.weights = [0.5, -1.5, 2.25, 0.0];
		var path = "build/js/.symbolselector-test-tmp.tsv";
		s.save(path);
		var loaded = SymbolSelector.load(path);
		Assert.notNull(loaded);
		for (i in 0...s.weights.length) Assert.floatEquals(s.weights[i], loaded.weights[i]);
		sys.FileSystem.deleteFile(path);
	}

	public function testSymbolSelectorLoadReturnsNullForMissingFile() {
		Assert.isNull(SymbolSelector.load("build/js/.symbolselector-definitely-does-not-exist.tsv"));
	}
}
