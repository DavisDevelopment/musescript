package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.harness.Bar;
import musescript.evo.nma.NmaFitness;

/**
 * P1c strangler gate: `Fitness.preferNma` routes eligible genomes through columnar NMA and falls
 * back to Expand→compile for `KFeature`. Attribution-shaped double calls share SInd columns.
 *
 * «εὐοῖ σαβοῖ, ὦ Ἴακχε πολυτίμητε.»
 */
class TestNmaStrangler extends Test {

	static function tape(n:Int):Array<Bar> {
		var bars = new Array<Bar>();
		var prevClose = 100.0;
		for (i in 0...n) {
			var t = i / 6.0;
			var close = 100.0 + i * 0.15 + 6.0 * Math.sin(t);
			bars.push({
				open: prevClose,
				high: Math.max(prevClose, close) + 0.5,
				low: Math.min(prevClose, close) - 0.5,
				close: close,
				volume: 1000.0,
				time: i, index: i
			});
			prevClose = close;
		}
		return bars;
	}

	static final FALSE_BOOL:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	function setup() {
		Fitness.preferNma = false;
		Fitness.nmaVerify = false;
		Fitness.clearFnCache();
	}

	function teardown() {
		Fitness.preferNma = false;
		Fitness.nmaVerify = false;
		Fitness.clearFnCache();
	}

	public function testNmaVerifyPassesOnParity() {
		var g:StrategyGenome = {
			entryLong: BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
			entryShort: FALSE_BOOL,
			exitLong: BCross("under", SPrice("close"), SInd("sma", "close", 5, null)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "verify_ok"
		};
		Fitness.preferNma = true;
		Fitness.nmaVerify = true;
		var fr = Fitness.evaluate(g, tape(100), "js", false, 0.0);
		Assert.isTrue(fr.ok);
		Assert.equals("nma", fr.backend);
	}

	public function testPopMemoHitsAcrossIdenticalSubtrees() {
		var bars = tape(80);
		var g1:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SInd("sma", "close", 5, null)), KConst(0.0)),
			entryShort: FALSE_BOOL,
			exitLong: FALSE_BOOL,
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "pop1"
		};
		var g2:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SInd("sma", "close", 5, null)), KConst(1.0)),
			entryShort: FALSE_BOOL,
			exitLong: FALSE_BOOL,
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "pop2"
		};
		Fitness.preferNma = true;
		Fitness.beginNmaPopMemo();
		Assert.equals(0, Fitness.nmaPopMemoHits);
		Assert.isTrue(Fitness.evaluate(g1, bars, "js", false).ok);
		var afterFirst = Fitness.nmaPopMemoHits;
		Assert.isTrue(Fitness.evaluate(g2, bars, "js", false).ok);
		Assert.isTrue(Fitness.nmaPopMemoHits > afterFirst, "shared sma/close/5 column should hit pop memo");
	}

	public function testPopMemoSeparatesDifferentParamEpochs() {
		var bars = tape(80);
		function genome(name:String, threshold:Float):StrategyGenome {
			return {
				entryLong: BCmp(">", KSeries(SPrice("close")), KParam(0)),
				entryShort: FALSE_BOOL,
				exitLong: BCmp("<", KSeries(SPrice("close")), KParam(0)),
				exitShort: FALSE_BOOL,
				size: KConst(1.0),
				params: [{
					name: "threshold", defaultValue: threshold,
					min: 50.0, max: 150.0, step: 1.0, tune: "grid"
				}],
				name: name
			};
		}
		var low = genome("param_low", 90.0);
		var high = genome("param_high", 110.0);
		Fitness.preferNma = true;
		Fitness.beginNmaPopMemo();
		Assert.isTrue(Fitness.evaluate(low, bars, "js", false).ok);
		var warmHigh = Fitness.evaluate(high, bars, "js", false);
		Fitness.nmaPopMemo = null;
		var coldHigh = Fitness.evaluate(high, bars, "js", false);
		Assert.equals(coldHigh.trades, warmHigh.trades,
			"same structural shape with different KParam defaults must not share bool columns");
		Assert.floatEquals(coldHigh.finalEquity, warmHigh.finalEquity, 1e-9);
	}

	public function testPreferNmaUsesNmaBackendOnPureGenome() {
		var g:StrategyGenome = {
			entryLong: BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
			entryShort: FALSE_BOOL,
			exitLong: BCross("under", SPrice("close"), SInd("sma", "close", 5, null)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "strangle_pure"
		};
		var bars = tape(120);
		Assert.isTrue(NmaFitness.columnSwappable(g), "curated genome is columnar-eligible");

		Fitness.preferNma = true;
		var fr = Fitness.evaluate(g, bars, "js", false, 0.0);
		Assert.isTrue(fr.ok, 'nma strangler ok (${fr.error})');
		Assert.equals("nma", fr.backend, "eligible genome should report backend=nma");

		var classic = Fitness.evaluateCompiled(g, bars, "js", false, 0.0);
		Assert.isTrue(classic.ok, 'classic ok (${classic.error})');
		Assert.equals(classic.trades, fr.trades, "trades parity");
		Assert.floatEquals(classic.finalEquity, fr.finalEquity, "equity parity");
	}

	/**
	 * A position-state feature no longer costs the genome the columnar backend. It has no
	 * standalone column -- so it is still not column-swappable, which is what attribution asks --
	 * but `NmaPositionEval` walks the coupled spine per bar inside the sim loop, and the result
	 * must match the compiled path it used to be handed to.
	 */
	public function testPreferNmaHostsPositionFeatureOnSimLoop() {
		var g:StrategyGenome = {
			entryLong: BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
			entryShort: FALSE_BOOL,
			exitLong: BCmp("<", KFeature("unrealized_pnl_pct()"), KConst(-0.02)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "strangle_feat"
		};
		var bars = tape(80);
		Assert.isTrue(musescript.evo.GenomeFeatures.isSimCoupled(g), "risk exit reads sim state");
		Assert.isFalse(NmaFitness.columnSwappable(g), "and so has no column to swap");

		Fitness.preferNma = true;
		var fr = Fitness.evaluate(g, bars, "js", false, 0.0);
		Assert.isTrue(fr.ok, 'coupled genome must evaluate (${fr.error})');
		Assert.equals("nma", fr.backend, "coupled genome now stays on the columnar backend");

		var classic = Fitness.evaluateCompiled(g, bars, "js", false, 0.0);
		Assert.isTrue(classic.ok, 'classic ok (${classic.error})');
		Assert.equals(classic.trades, fr.trades, "trades parity");
		Assert.floatEquals(classic.finalEquity, fr.finalEquity, "equity parity");
	}

	public function testSindColumnCacheHitsAcrossAblationShapedEvals() {
		var bars = tape(100);
		var g:StrategyGenome = {
			entryLong: BCross("over", SPrice("close"), SInd("ema", "close", 4, null)),
			entryShort: FALSE_BOOL,
			exitLong: BTrend("under", SPrice("close"), 3),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "cache_ablate"
		};
		Fitness.preferNma = true;
		NmaFitness.clearColumnCache();
		var a = Fitness.evaluate(g, bars, "js", false, 0.0);
		var b = Fitness.evaluate(g, bars, "js", false, 0.0);
		Assert.isTrue(a.ok && b.ok);
		Assert.equals(a.trades, b.trades);
		Assert.floatEquals(a.finalEquity, b.finalEquity);
		Assert.equals("nma", a.backend);
		// Second call must still be a real OrderSim (champion-style double-exec), not a memoized
		// FitnessResult — backend stays nma and numbers match.
		Assert.equals("nma", b.backend);
	}

	public function testPreferNmaOffIsClassicByDefault() {
		var bars = tape(60);
		var g:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SPrice("close")), KConst(0.0)),
			entryShort: FALSE_BOOL,
			exitLong: FALSE_BOOL,
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: "default_off"
		};
		Fitness.preferNma = false;
		var fr = Fitness.evaluate(g, bars, "js", false, 0.0);
		Assert.isTrue(fr.ok, 'classic path ok (${fr.error})');
		Assert.notEquals("nma", fr.backend, "preferNma=false must not select nma backend");
	}
}
