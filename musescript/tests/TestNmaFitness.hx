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
		// `growSeries` never nests indicator sources, but `growBool` CAN mint `KFeature` via
		// `growRiskExit` / multi-output terminals — those are outside the columnar NMA model and
		// must be skipped explicitly (not counted against the A/B sample). Curated suite is the
		// strict always-on gate; this fuzzes pure market-data genomes only.
		var bars = tape(140);
		var matched = 0;
		var skippedFeature = 0;
		var skippedRefFail = 0;
		var seed = 0;
		// ~11% of randomGenome draws are pure market-data (rest hit growRiskExit/KFeature);
		// cap high enough that 15 eligible A/Bs is the expected case, not a coin flip.
		while (seed < 200 && matched < 15) {
			var g = new Variation(seed).randomGenome(2 + (seed % 4));
			if (genomeHasFeature(g)) { skippedFeature++; seed++; continue; }
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
			'enough pure market-data random genomes exercised the A/B (got $matched; '
			+ 'skippedFeature=$skippedFeature skippedRefFail=$skippedRefFail seedsTried=$seed)');
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
		Assert.isTrue(NmaFitness.supportsColumnar(flat));
		Assert.isTrue(NmaFitness.supportsColumnar(nested));
		Assert.isFalse(musescript.evo.GenomeFeatures.genomeBlocksColumnar(nested));
		var bars = tape(40);
		Fitness.preferNma = true;
		var fr = Fitness.evaluate(nested, bars, "js", false);
		Assert.isTrue(fr.ok, "nested SInd should evaluate on columnar path: " + fr.error);
		Assert.equals("nma", fr.backend);
	}
}
