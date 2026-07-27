package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.harness.Bar;
import musescript.evo.nma.NmaBarColumns;
import musescript.evo.nma.NmaFitness;

/**
 * `NmaFitness.runPrepared` and `NmaPositionEval` read OHLC and the bar index out of unboxed
 * per-tape columns instead of the `Bar` typedef. These pin the two ways that can go wrong:
 * the columns disagreeing with the bars they were derived from, and a cached column set being
 * read against a DIFFERENT tape than the one the caller passed.
 *
 * Both tapes here number their bars `i * 2`, so `bar.index` is neither the loop counter nor an
 * affine shift of it — a `bars_in_trade()` genome then measures a doubled holding period, and
 * any confusion of the two indices changes the trades.
 *
 * «δύο ῥυθμοί, εἷς χορός· ὁ ἀριθμὸς οὐ ψεύδεται.»
 */
class TestNmaBarColumns extends Test {
	/** `index = i * 2` on purpose; `openBias` shifts open/high/low without touching close, so two
	 * tapes can share a close-derived tape signature while differing elsewhere. */
	static function tape(n:Int, openBias:Float = 0.0):Array<Bar> {
		var bars = new Array<Bar>();
		var prevClose = 100.0;
		for (i in 0...n) {
			var close = 100.0 + i * 0.15 + 6.0 * Math.sin(i / 6.0);
			bars.push({
				open: prevClose + openBias,
				high: Math.max(prevClose, close) + 0.5 + openBias,
				low: Math.min(prevClose, close) - 0.5 + openBias,
				close: close,
				volume: 1000.0,
				time: i,
				index: i * 2
			});
			prevClose = close;
		}
		return bars;
	}

	static final FALSE_BOOL:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	/** Times out of a trade, so the exit depends on `bar.index` arithmetic. */
	static function timedExitGenome(name:String):StrategyGenome {
		return {
			entryLong: BCross("over", SPrice("close"), SInd("sma", "close", 5, null)),
			entryShort: FALSE_BOOL,
			exitLong: BCmp(">", KFeature("bars_in_trade()"), KConst(6.0)),
			exitShort: FALSE_BOOL,
			size: KConst(1.0),
			params: [],
			name: name
		};
	}

	function setup() {
		Fitness.preferNma = false;
		Fitness.clearFnCache();
		NmaFitness.clearColumnCache();
	}

	function teardown() {
		Fitness.preferNma = false;
		Fitness.clearFnCache();
		NmaFitness.clearColumnCache();
	}

	public function testColumnsMirrorTheirBars() {
		var bars = tape(40);
		var cols = NmaBarColumns.of(bars);
		Assert.equals(bars.length, cols.n);
		Assert.isTrue(cols.bars == bars, "retains the tape identity its holders guard on");
		for (i in 0...bars.length) {
			Assert.equals(bars[i].open, cols.open.at(i));
			Assert.equals(bars[i].high, cols.high.at(i));
			Assert.equals(bars[i].low, cols.low.at(i));
			Assert.equals(bars[i].close, cols.close.at(i));
			Assert.equals(bars[i].index, cols.index[i]);
		}
	}

	public function testEmptyTapeYieldsEmptyColumns() {
		var cols = NmaBarColumns.of([]);
		Assert.equals(0, cols.n);
		Assert.equals(0, cols.close.length);
		Assert.equals(0, cols.index.length);
	}

	/** The columnar sim loop must still agree with Expand→compile when `bar.index` is not `i`. */
	public function testSimCoupledParityOnNonIdentityBarIndex() {
		var bars = tape(120);
		var g = timedExitGenome("barcols_coupled");

		Fitness.preferNma = true;
		var nma = Fitness.evaluate(g, bars, "js", false, 0.0);
		Assert.isTrue(nma.ok, 'nma ok (${nma.error})');
		Assert.equals("nma", nma.backend);

		var classic = Fitness.evaluateCompiled(g, bars, "js", false, 0.0);
		Assert.isTrue(classic.ok, 'classic ok (${classic.error})');
		Assert.equals(classic.trades, nma.trades, "trades parity");
		Assert.floatEquals(classic.finalEquity, nma.finalEquity, "equity parity");
		Assert.isTrue(nma.trades > 0, "the timed exit has to actually fire for this to prove anything");
	}

	/**
	 * A retained context evaluated against a different `Array<Bar>` must read THAT tape. The two
	 * tapes share every close, so the tape signature matches and the memoized signal columns stay
	 * valid — only the fields the sim loop reads directly differ.
	 */
	public function testPreparedContextFollowsTheTapeItIsHanded() {
		var barsA = tape(120);
		var barsB = tape(120, 3.0);

		Fitness.preferNma = true;
		var built = NmaFitness.prepare(timedExitGenome("barcols_rebind"), barsA);
		Assert.notNull(built);
		var onA = NmaFitness.evaluatePrepared(built.nma, built.ctx, barsA);
		var onB = NmaFitness.evaluatePrepared(built.nma, built.ctx, barsB);
		var freshB = NmaFitness.evaluate(timedExitGenome("barcols_rebind"), barsB);

		Assert.isTrue(onA.ok && onB.ok && freshB.ok);
		Assert.equals(freshB.trades, onB.trades, "reused context must score barsB as barsB");
		Assert.floatEquals(freshB.finalEquity, onB.finalEquity);

		// And handing the original tape back afterwards must not have been poisoned by the detour.
		var backOnA = NmaFitness.evaluatePrepared(built.nma, built.ctx, barsA);
		Assert.equals(onA.trades, backOnA.trades);
		Assert.floatEquals(onA.finalEquity, backOnA.finalEquity);
	}
}
