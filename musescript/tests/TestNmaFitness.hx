package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.EvoParam;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.Variation;
import musescript.harness.Bar;
import musescript.evo.nma.NmaFitness;

/**
 * THE CROWN GATE: NMA-native fitness (`NmaFitness`) must match the production `Fitness.evaluate`
 * (real compile+JS backend + OrderSim) bit-for-bit -- sharpe, trades, finalEquity -- across a
 * battery of genomes and cost levels. Passing this proves the whole NMA evaluation stack end-to-end:
 * indicator columns, cross/trend/arith/logic signals, AND the order/accounting loop, all agree with
 * the path that actually trades. This is the empirical A/B the spec's P1 gate demands.
 */
class TestNmaFitness extends Test {

	// Deterministic OHLCV tape with trend + oscillation so genomes actually trade.
	static function tape(n:Int):Array<Bar> {
		var bars = new Array<Bar>();
		var prevClose = 100.0;
		for (i in 0...n) {
			var t = i / 6.0;
			var close = 100.0 + i * 0.15 + 6.0 * Math.sin(t) + 2.0 * Math.sin(t * 2.3 + 1.0);
			var spread = 0.5 + 0.5 * Math.abs(Math.sin(t * 1.7));
			bars.push({
				open: prevClose,
				high: Math.max(prevClose, close) + spread,
				low: Math.min(prevClose, close) - spread,
				close: close,
				volume: 1000.0 + 50.0 * Math.sin(t * 0.5),
				time: i, index: i
			});
			prevClose = close;
		}
		return bars;
	}

	static final FALSE_BOOL:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	static function gen(entryLong:BoolNode, ?entryShort:BoolNode, ?exitLong:BoolNode,
			?exitShort:BoolNode, ?size:ScalarNode, ?params:Array<EvoParam>, ?name:String):StrategyGenome {
		return {
			entryLong: entryLong,
			entryShort: entryShort != null ? entryShort : FALSE_BOOL,
			exitLong: exitLong != null ? exitLong : FALSE_BOOL,
			exitShort: exitShort != null ? exitShort : FALSE_BOOL,
			size: size != null ? size : KConst(1.0),
			params: params != null ? params : [],
			name: name != null ? name : "ab"
		};
	}

	static function curated():Array<StrategyGenome> {
		var sma5 = SInd("sma", "close", 5, null);
		var sma3 = SInd("sma", "close", 3, null);
		var sma8 = SInd("sma", "close", 8, null);
		var ema4 = SInd("ema", "close", 4, null);
		var rsi5 = SInd("rsi", "close", 5, null);
		return [
			// price vs sma crossover, opposite-cross exit
			gen(BCross("over", SPrice("close"), sma5), null,
				BCross("under", SPrice("close"), sma5), null, null, null, "price_x_sma"),
			// sma fast/slow cross both directions
			gen(BCross("over", sma3, sma8), BCross("under", sma3, sma8),
				BCross("under", sma3, sma8), BCross("over", sma3, sma8), null, null, "sma_x_sma"),
			// rsi thresholds
			gen(BCmp("<", KSeries(rsi5), KConst(35.0)), BCmp(">", KSeries(rsi5), KConst(65.0)),
				BCmp(">", KSeries(rsi5), KConst(55.0)), BCmp("<", KSeries(rsi5), KConst(45.0)),
				null, null, "rsi_bands"),
			// trend (rising/falling) on price
			gen(BTrend("over", SPrice("close"), 3), BTrend("under", SPrice("close"), 3),
				null, null, null, null, "trend"),
			// ema compare with arith size (min-capped)
			gen(BCmp(">", KSeries(SPrice("close")), KSeries(ema4)), null,
				BCmp("<", KSeries(SPrice("close")), KSeries(ema4)), null,
				KArith("min", KConst(3.0), KConst(2.0)), null, "ema_cmp_arithsize"),
			// param-driven size
			gen(BCross("over", SPrice("close"), sma5), null, BCross("under", SPrice("close"), sma5), null,
				KParam(0), [{ name: "q", defaultValue: 2.0, min: 1.0, max: 5.0, step: 1.0, tune: "" }], "param_size"),
			// lookback comparison (close vs close 3 bars ago) + AND logic
			gen(BAnd(BCmp(">", KSeries(SPrice("close")), KLookback(SPrice("close"), 3)),
					BCmp(">", KSeries(sma3), KSeries(sma8))),
				null, BCmp("<", KSeries(SPrice("close")), KLookback(SPrice("close"), 3)), null,
				null, null, "lookback_and"),
			// hole-wrapped (transparent) + OR exit + highest/lowest indicators
			gen(BHole(BCross("over", SPrice("close"), SInd("lowest", "low", 5, null))),
				null,
				BOr(BCross("under", SPrice("close"), SInd("highest", "high", 5, null)), FALSE_BOOL),
				null, KHole(KConst(1.0)), null, "holes_highlow"),
			// Corpus Donchian shape: inclusive compare against a window that includes this bar.
			gen(BCmp(">=", KSeries(SPrice("high")),
					KSeries(SInd("highest", "high", 21, null))),
				null,
				BCmp("<=", KSeries(SPrice("low")),
					KSeries(SInd("lowest", "low", 8, null))),
				null, null, null, "donchian_21_8"),
		];
	}

	/**
	 * Genomes that read simulator state. The first three are exactly the shapes `Variation`
	 * grows (stop loss, take profit, time stop); the rest push the coupled spine into places
	 * crossover can move it -- under logic, under negation, inside arithmetic, into an entry
	 * head, and into `size`, where the value is read at submit time rather than at the `when`.
	 */
	static function simCoupled():Array<StrategyGenome> {
		var sma5 = SInd("sma", "close", 5, null);
		var enter = BCross("over", SPrice("close"), sma5);
		var pnl = KFeature("unrealized_pnl_pct()");
		var held = KFeature("bars_in_trade()");
		return [
			gen(enter, null, BCmp("<", pnl, KConst(-0.01)), null, null, null, "stop_loss"),
			gen(enter, null, BCmp(">", pnl, KConst(0.02)), null, null, null, "take_profit"),
			gen(enter, null, BCmp(">", held, KConst(4.0)), null, null, null, "time_stop"),
			// stop OR time stop -- the shape a risk-managed elite actually converges to
			gen(enter, null, BOr(BCmp("<", pnl, KConst(-0.01)), BCmp(">", held, KConst(6.0))),
				null, null, null, "stop_or_time"),
			// coupled AND pure, so one operand is a column and the other is walked
			gen(enter, null, BAnd(BCmp(">", held, KConst(2.0)),
					BCross("under", SPrice("close"), sma5)),
				null, null, null, "time_and_cross"),
			gen(enter, null, BNot(BCmp("<", held, KConst(3.0))), null, null, null, "not_time"),
			// arithmetic over the feature, and a hole in the coupled spine
			gen(enter, null, BCmp(">", KArith("*", held, KConst(2.0)), KConst(9.0)),
				null, null, null, "arith_on_feature"),
			gen(enter, null, BHole(BCmp("<", pnl, KConst(-0.015))), null, null, null, "hole_stop"),
			// coupled ENTRY head: read before this bar's submits, unlike an exit
			gen(BAnd(enter, BCmp("<", held, KConst(1.0))), null,
				BCross("under", SPrice("close"), sma5), null, null, null, "coupled_entry"),
			// coupled SIZE: evaluated at the submit call, after the entry head passed
			gen(enter, null, BCross("under", SPrice("close"), sma5), null,
				KArith("+", KConst(1.0), held), null, "coupled_size"),
			// both exits coupled, plus a short side that also trades
			gen(enter, BCross("under", SPrice("close"), sma5),
				BCmp(">", held, KConst(5.0)), BCmp("<", pnl, KConst(-0.02)),
				null, null, "both_sides_coupled"),
		];
	}

	public function testSimCoupledGenomesMatchProductionFitness() {
		var bars = tape(160);
		for (g in simCoupled())
			for (cost in [0.0, 20.0])
				checkParity(g, bars, cost);
	}

	/** The coupled path must be reached, not silently skipped by a fallback. */
	public function testSimCoupledGenomesRunOnTheColumnarBackend() {
		var bars = tape(80);
		var prev = Fitness.preferNma;
		Fitness.preferNma = true;
		for (g in simCoupled()) {
			Assert.isTrue(musescript.evo.GenomeFeatures.isSimCoupled(g), '${g.name}: is sim-coupled');
			Assert.isFalse(NmaFitness.columnSwappable(g), '${g.name}: has no swappable column');
			var fr = Fitness.evaluate(g, bars, "js", false);
			Assert.isTrue(fr.ok, '${g.name}: evaluates (${fr.error})');
			Assert.equals("nma", fr.backend, '${g.name}: took the columnar backend');
		}
		Fitness.preferNma = prev;
	}

	function checkParity(g:StrategyGenome, bars:Array<Bar>, costBps:Float):Void {
		var ref = Fitness.evaluate(g, bars, "js", false, costBps);
		var nma = NmaFitness.evaluate(g, bars, costBps);
		var tag = '${g.name}@${costBps}bps';
		Assert.isTrue(ref.ok, '$tag: reference evaluate ok (${ref.error})');
		Assert.isTrue(nma.ok, '$tag: nma evaluate ok (${nma.error})');
		Assert.equals(ref.trades, nma.trades, '$tag: trades');
		Assert.floatEquals(ref.finalEquity, nma.finalEquity, '$tag: finalEquity');
		if (Math.isNaN(ref.sharpe)) Assert.isTrue(Math.isNaN(nma.sharpe), '$tag: sharpe both NaN');
		else Assert.floatEquals(ref.sharpe, nma.sharpe, '$tag: sharpe');
	}

	public function testCuratedGenomesMatchProductionFitness() {
		var bars = tape(160);
		for (g in curated())
			for (cost in [0.0, 20.0])
				checkParity(g, bars, cost);
	}

	public function testRandomGrownGenomesMatchProductionFitness() {
		// Nothing `growBool` can mint is skipped any more. `growRiskExit`'s position-state
		// features used to be excluded from this A/B because NMA refused them outright; they are
		// now evaluated per bar inside the sim loop, so the fuzzer covers them — which is the
		// point, since they are the shapes least likely to be right by construction.
		var bars = tape(140);
		var matched = 0;
		var coupled = 0;
		var skippedRefFail = 0;
		var seed = 0;
		while (seed < 200 && matched < 15) {
			var g = new Variation(seed).randomGenome(2 + (seed % 4));
			if (genomeHasFeature(g)) coupled++;
			var ref = Fitness.evaluate(g, bars, "js", false, 0.0);
			if (!ref.ok) { skippedRefFail++; seed++; continue; }
			var nma = NmaFitness.evaluate(g, bars, 0.0);
			Assert.isTrue(nma.ok, 'random seed=$seed: nma ok (${nma.error})');
			Assert.equals(ref.trades, nma.trades, 'random seed=$seed: trades');
			Assert.floatEquals(ref.finalEquity, nma.finalEquity, 'random seed=$seed: finalEquity');
			if (Math.isNaN(ref.sharpe)) Assert.isTrue(Math.isNaN(nma.sharpe), 'random seed=$seed: sharpe NaN');
			else Assert.floatEquals(ref.sharpe, nma.sharpe, 'random seed=$seed: sharpe');
			matched++;
			seed++;
		}
		Assert.isTrue(matched >= 15,
			'enough random genomes exercised the A/B (got $matched; '
			+ 'skippedRefFail=$skippedRefFail seedsTried=$seed)');
		// Guards the test itself: if grammar changes stopped producing risk clauses, the
		// coverage this test is claiming would quietly vanish.
		Assert.isTrue(coupled > 0, 'the sample included sim-coupled genomes (got $coupled)');
	}

	static function genomeHasFeature(g:StrategyGenome):Bool {
		return boolHasFeature(g.entryLong) || boolHasFeature(g.entryShort)
			|| boolHasFeature(g.exitLong) || boolHasFeature(g.exitShort)
			|| scalarHasFeature(g.size);
	}

	static function boolHasFeature(n:BoolNode):Bool {
		return switch (n) {
			case BCross(_, a, b): seriesHasFeature(a) || seriesHasFeature(b);
			case BCmp(_, a, b): scalarHasFeature(a) || scalarHasFeature(b);
			case BTrend(_, s, _): seriesHasFeature(s);
			case BAnd(a, b) | BOr(a, b): boolHasFeature(a) || boolHasFeature(b);
			case BNot(a) | BHole(a): boolHasFeature(a);
		};
	}

	static function scalarHasFeature(n:ScalarNode):Bool {
		return switch (n) {
			case KFeature(_): true;
			case KArith(_, a, b): scalarHasFeature(a) || scalarHasFeature(b);
			case KSeries(s) | KLookback(s, _): seriesHasFeature(s);
			case KHole(inner): scalarHasFeature(inner);
			case KConst(_) | KParam(_): false;
		};
	}

	static function seriesHasFeature(n:SeriesNode):Bool {
		return switch (n) {
			case SPrice(_): false;
			case SProj(_, _): false;
			case SInd(_, _, _, src): src != null && seriesHasFeature(src);
		};
	}

	public function testNestedSindIsColumnarHostable() {
		var flat:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SInd("sma", "close", 5, null)), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "flat"
		};
		var nested:StrategyGenome = {
			entryLong: BCmp(">", KSeries(SInd("ema", "close", 3, SInd("sma", "close", 2, null))), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "nested"
		};
		Assert.isTrue(NmaFitness.columnSwappable(flat));
		Assert.isTrue(NmaFitness.columnSwappable(nested));
		Assert.isFalse(musescript.evo.GenomeFeatures.isSimCoupled(nested));
		var bars = tape(40);
		Fitness.preferNma = true;
		var fr = Fitness.evaluate(nested, bars, "js", false);
		Assert.isTrue(fr.ok, "nested SInd should evaluate on columnar path: " + fr.error);
		Assert.equals("nma", fr.backend);
	}
}
