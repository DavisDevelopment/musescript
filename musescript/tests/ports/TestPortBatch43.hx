package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.SpreadAr1Coefficient;
import musescript.indicators.lib.SpreadBollingerBands;
import musescript.indicators.lib.SpreadHurst;
import musescript.indicators.lib.Psar;
import musescript.indicators.lib.SarExt;
import musescript.indicators.lib.SuperTrend;
import musescript.indicators.lib.KaseDevStop;
import musescript.indicators.lib.KasePermissionStochastic;
import musescript.indicators.lib.StepTrailingStop;
import musescript.indicators.lib.TimeBasedStop;
import musescript.indicators.lib.VoltyStop;
import musescript.indicators.lib.YoyoExit;
import musescript.indicators.lib.StarcBands;
import musescript.indicators.lib.ProjectionBands;
import musescript.indicators.lib.ProjectionOscillator;
import musescript.indicators.lib.Stochastic;
import musescript.indicators.lib.StochasticCci;
import musescript.indicators.lib.StochRsi;

/**
 * Batch 43: 18 indicators ported from wickra-core (stops, PSAR family,
 * stochastics, spread studies). Known-value cases transcribed directly from
 * the Rust fixture blocks; batch_equals_streaming verifies IndicatorBatch.run
 * equals streaming updates.
 */
class TestPortBatch43 extends Test {
	/** Bar with explicit OHLC; open defaults to close (none of this batch reads open/volume). */
	static function bar(h:Float, l:Float, c:Float, i:Int):Bar {
		return { open: c, high: h, low: l, close: c, volume: 1.0, time: (i : Float), index: i };
	}

	static function pair(a:Float, b:Float):{a:Float, b:Float} {
		return {a: a, b: b};
	}

	static function assertScalarSeriesEqual(a:Array<Null<Float>>, b:Array<Null<Float>>, ?pos:haxe.PosInfos) {
		Assert.equals(a.length, b.length, pos);
		for (i in 0...a.length) {
			if (a[i] == null) {
				Assert.isNull(b[i], 'index $i', pos);
			} else {
				Assert.notNull(b[i], 'index $i', pos);
				Assert.floatEquals(a[i], b[i], pos);
			}
		}
	}

	// ── SpreadAr1Coefficient ─────────────────────────────────────────────────

	public function testSpreadAr1RejectsPeriodBelowThree() {
		try {
			new SpreadAr1Coefficient(2);
			Assert.fail("Should reject period < 3");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		Assert.notNull(new SpreadAr1Coefficient(3));
	}

	public function testSpreadAr1AccessorsAndMetadata() {
		var ar1 = new SpreadAr1Coefficient(30);
		Assert.equals(30, ar1.warmupPeriod());
		Assert.equals("SpreadAr1Coefficient", ar1.name());
		Assert.isTrue(!ar1.isReady());
	}

	public function testSpreadAr1WarmupReturnsNone() {
		var ar1 = new SpreadAr1Coefficient(4);
		Assert.isNull(ar1.update({a: 1.0, b: 0.0}));
		Assert.isNull(ar1.update({a: 2.0, b: 0.0}));
		Assert.isNull(ar1.update({a: 3.0, b: 0.0}));
		Assert.notNull(ar1.update({a: 4.0, b: 0.0}));
		Assert.isTrue(ar1.isReady());
	}

	public function testSpreadAr1MeanRevertingSpreadHasRhoBelowOne() {
		// Fast sinusoidal spread around zero ⇒ stationary ⇒ 0 < ρ < 1.
		var ar1 = new SpreadAr1Coefficient(40);
		var last:Null<Float> = null;
		for (t in 0...120) {
			var b = 100.0 + t;
			var a = b + 2.0 * Math.sin(t * 0.9);
			var v = ar1.update({a: a, b: b});
			if (v != null) last = v;
		}
		Assert.isTrue(last > 0.0 && last < 1.0, 'rho $last');
	}

	public function testSpreadAr1RandomWalkSpreadHasRhoNearOne() {
		// Spread grows by exactly 1 each bar ⇒ OLS slope is exactly 1 (unit root).
		var ar1 = new SpreadAr1Coefficient(20);
		var last:Null<Float> = null;
		for (t in 0...40) {
			var v = ar1.update({a: 2.0 * t, b: (t : Float)});
			if (v != null) last = v;
		}
		Assert.floatEquals(1.0, last);
	}

	public function testSpreadAr1FlatSpreadReturnsZero() {
		// a − b is constant ⇒ var(level) = 0 ⇒ undefined ⇒ 0.
		var ar1 = new SpreadAr1Coefficient(10);
		var last:Null<Float> = null;
		for (t in 0...30) {
			var v = ar1.update({a: 5.0 + t, b: (t : Float)});
			if (v != null) last = v;
		}
		Assert.floatEquals(0.0, last);
	}

	public function testSpreadAr1ResetClearsState() {
		var ar1 = new SpreadAr1Coefficient(5);
		for (t in 0...10) {
			ar1.update({a: t + Math.sin(t * 0.7), b: (t : Float)});
		}
		Assert.isTrue(ar1.isReady());
		ar1.reset();
		Assert.isTrue(!ar1.isReady());
		Assert.isNull(ar1.update({a: 1.0, b: 0.0}));
	}

	public function testSpreadAr1BatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.SpreadAr1Coefficient.SpreadAr1Pair> = [for (t in 0...80) {
			var b = 50.0 + 0.5 * t;
			var p:musescript.indicators.lib.SpreadAr1Coefficient.SpreadAr1Pair = {a: b + Math.sin(t * 0.6), b: b};
			p;
		}];
		var x = new SpreadAr1Coefficient(25);
		var y = new SpreadAr1Coefficient(25);
		var batched = IndicatorBatch.run(x, pairs);
		var streamed = [for (p in pairs) y.update(p)];
		assertScalarSeriesEqual(batched, streamed);
	}

	public function testSpreadAr1NonFiniteInputReturnsNone() {
		var ar1 = new SpreadAr1Coefficient(4);
		Assert.isNull(ar1.update({a: Math.NaN, b: 1.0}));
		Assert.isNull(ar1.update({a: 1.0, b: Math.POSITIVE_INFINITY}));
		// The rejected ticks leave no trace: a fresh window still warms up.
		Assert.isNull(ar1.update({a: 1.0, b: 0.0}));
		Assert.isNull(ar1.update({a: 2.0, b: 0.0}));
		Assert.isNull(ar1.update({a: 3.0, b: 0.0}));
		Assert.notNull(ar1.update({a: 4.0, b: 0.0}));
	}

	// ── SpreadBollingerBands ─────────────────────────────────────────────────

	public function testSpreadBbRejectsBadParameters() {
		var bad = [
			() -> new SpreadBollingerBands(1, 2.0),
			() -> new SpreadBollingerBands(20, 0.0),
			() -> new SpreadBollingerBands(20, -1.0),
			() -> new SpreadBollingerBands(20, Math.NaN),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject bad parameters");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
		Assert.notNull(new SpreadBollingerBands(2, 2.0));
	}

	public function testSpreadBbAccessorsAndMetadata() {
		var bb = new SpreadBollingerBands(20, 2.5);
		Assert.equals(20, bb.warmupPeriod());
		Assert.equals("SpreadBollingerBands", bb.name());
		Assert.isTrue(!bb.isReady());
	}

	public function testSpreadBbWarmupReturnsNone() {
		var bb = new SpreadBollingerBands(3, 2.0);
		Assert.isNull(bb.update({a: 1.0, b: 0.0}));
		Assert.isNull(bb.update({a: 2.0, b: 0.0}));
		Assert.notNull(bb.update({a: 3.0, b: 0.0}));
		Assert.isTrue(bb.isReady());
	}

	public function testSpreadBbHandComputedValue() {
		// Spreads 1,2,3,4 (b = 0), period 4, num_std 2:
		//   mean = 2.5, σ = √1.25, %b at s = 4 ⇒ 0.8354102.
		var bb = new SpreadBollingerBands(4, 2.0);
		bb.update({a: 1.0, b: 0.0});
		bb.update({a: 2.0, b: 0.0});
		bb.update({a: 3.0, b: 0.0});
		var out = bb.update({a: 4.0, b: 0.0});
		Assert.notNull(out);
		Assert.floatEquals(2.5, out.middle);
		Assert.floatEquals(4.73606797749979, out.upper);
		Assert.floatEquals(0.26393202250021, out.lower);
		Assert.floatEquals(0.83541019662497, out.percentB);
	}

	public function testSpreadBbFlatSpreadCollapsesBand() {
		// a − b constant ⇒ σ = 0 ⇒ upper = middle = lower, %b = 0.5.
		var bb = new SpreadBollingerBands(5, 2.0);
		var last = null;
		for (t in 0...10) {
			var v = bb.update({a: 5.0 + t, b: (t : Float)});
			if (v != null) last = v;
		}
		Assert.floatEquals(last.middle, last.upper);
		Assert.floatEquals(last.middle, last.lower);
		Assert.floatEquals(0.5, last.percentB);
	}

	public function testSpreadBbBandsAreOrdered() {
		var bb = new SpreadBollingerBands(20, 2.0);
		for (t in 0...80) {
			var b = 100.0 + t;
			var out = bb.update({a: b + 3.0 * Math.sin(t * 0.4), b: b});
			if (out != null) {
				Assert.isTrue(out.lower <= out.middle && out.middle <= out.upper);
			}
		}
	}

	public function testSpreadBbResetClearsState() {
		var bb = new SpreadBollingerBands(4, 2.0);
		for (s in [1.0, 2.0, 3.0, 4.0, 5.0]) {
			bb.update({a: s, b: 0.0});
		}
		Assert.isTrue(bb.isReady());
		bb.reset();
		Assert.isTrue(!bb.isReady());
		Assert.isNull(bb.update({a: 1.0, b: 0.0}));
	}

	public function testSpreadBbBatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.SpreadBollingerBands.SpreadBbPair> = [for (t in 0...60) {
			var b = 30.0 + 0.7 * t;
			var p:musescript.indicators.lib.SpreadBollingerBands.SpreadBbPair = {a: b + Math.sin(t * 0.4) * 1.5, b: b};
			p;
		}];
		var x = new SpreadBollingerBands(15, 2.0);
		var y = new SpreadBollingerBands(15, 2.0);
		var batched = IndicatorBatch.run(x, pairs);
		var streamed = [for (p in pairs) y.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].middle, streamed[i].middle);
				Assert.floatEquals(batched[i].upper, streamed[i].upper);
				Assert.floatEquals(batched[i].lower, streamed[i].lower);
				Assert.floatEquals(batched[i].percentB, streamed[i].percentB);
			}
		}
	}

	// ── SpreadHurst ──────────────────────────────────────────────────────────

	public function testSpreadHurstRejectsPeriodBelowEight() {
		try {
			new SpreadHurst(7);
			Assert.fail("Should reject period < 8");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		Assert.notNull(new SpreadHurst(8));
	}

	public function testSpreadHurstAccessorsAndMetadata() {
		var h = new SpreadHurst(40);
		Assert.equals(40, h.warmupPeriod());
		Assert.equals("SpreadHurst", h.name());
		Assert.isTrue(!h.isReady());
	}

	public function testSpreadHurstWarmupReturnsNone() {
		var h = new SpreadHurst(8);
		for (t in 0...7) {
			Assert.isNull(h.update({a: (t : Float), b: 0.0}));
		}
		Assert.notNull(h.update({a: 7.0, b: 0.0}));
		Assert.isTrue(h.isReady());
	}

	public function testSpreadHurstOscillatingSpreadIsAntiPersistent() {
		var h = new SpreadHurst(60);
		var last:Null<Float> = null;
		for (t in 0...200) {
			var b = 100.0 + t;
			var v = h.update({a: b + 3.0 * Math.sin(t * 0.8), b: b});
			if (v != null) last = v;
		}
		Assert.isTrue(last < 0.5, 'H $last');
	}

	public function testSpreadHurstLinearTrendSpreadIsPersistent() {
		// Spread = t ⇒ τ-lagged differences are all τ ⇒ V(τ) = τ² ⇒ H = 1.
		var h = new SpreadHurst(20);
		var last:Null<Float> = null;
		for (t in 0...40) {
			var v = h.update({a: 2.0 * t, b: (t : Float)});
			if (v != null) last = v;
		}
		Assert.floatEquals(1.0, last);
	}

	public function testSpreadHurstFlatSpreadReturnsMidpoint() {
		// a − b constant ⇒ all lagged differences zero ⇒ neutral 0.5.
		var h = new SpreadHurst(16);
		var last:Null<Float> = null;
		for (t in 0...30) {
			var v = h.update({a: 5.0 + t, b: (t : Float)});
			if (v != null) last = v;
		}
		Assert.floatEquals(0.5, last);
	}

	public function testSpreadHurstOutputInUnitRange() {
		var h = new SpreadHurst(48);
		for (t in 0...150) {
			var b = 50.0 + 0.3 * t;
			var v = h.update({a: b + Math.sin(t * 0.5) * 2.0 + Math.cos(t * 0.13), b: b});
			if (v != null) {
				Assert.isTrue(v >= 0.0 && v <= 1.0, 'H $v out of [0, 1]');
			}
		}
	}

	public function testSpreadHurstResetClearsState() {
		var h = new SpreadHurst(8);
		for (t in 0...12) {
			h.update({a: t + Math.sin(t * 0.7), b: (t : Float)});
		}
		Assert.isTrue(h.isReady());
		h.reset();
		Assert.isTrue(!h.isReady());
		Assert.isNull(h.update({a: 1.0, b: 0.0}));
	}

	public function testSpreadHurstBatchEqualsStreaming() {
		var pairs:Array<musescript.indicators.lib.SpreadHurst.SpreadHurstPair> = [for (t in 0...100) {
			var b = 30.0 + 0.7 * t;
			var p:musescript.indicators.lib.SpreadHurst.SpreadHurstPair = {a: b + Math.sin(t * 0.4) * 1.5, b: b};
			p;
		}];
		var x = new SpreadHurst(32);
		var y = new SpreadHurst(32);
		var batched = IndicatorBatch.run(x, pairs);
		var streamed = [for (p in pairs) y.update(p)];
		assertScalarSeriesEqual(batched, streamed);
	}

	public function testSpreadHurstNonFiniteInputReturnsNone() {
		var h = new SpreadHurst(8);
		Assert.isNull(h.update({a: Math.NaN, b: 1.0}));
		Assert.isNull(h.update({a: 1.0, b: Math.POSITIVE_INFINITY}));
		// The rejected ticks leave no trace: a fresh window still warms up.
		for (t in 0...7) {
			Assert.isNull(h.update({a: (t : Float), b: 0.0}));
		}
		Assert.notNull(h.update({a: 7.0, b: 0.0}));
	}

	// ── Psar ─────────────────────────────────────────────────────────────────

	public function testPsarRejectsInvalidParams() {
		var bad = [
			() -> new Psar(0.0, 0.02, 0.20),
			() -> new Psar(0.02, 0.0, 0.20),
			() -> new Psar(0.30, 0.02, 0.20),
			() -> new Psar(Math.NaN, 0.02, 0.20),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid PSAR params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testPsarFirstCandleReturnsNone() {
		var psar = Psar.classic();
		Assert.isNull(psar.update(bar(11.0, 9.0, 10.0, 0)));
	}

	public function testPsarAccessorsAndMetadata() {
		var psar = Psar.classic();
		Assert.equals(2, psar.warmupPeriod());
		Assert.equals("PSAR", psar.name());
	}

	public function testPsarPureUptrendSarBelowLows() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 0.5, base - 0.5, base, i);
		}];
		var psar = Psar.classic();
		var out = IndicatorBatch.run(psar, candles);
		for (i in 0...out.length) {
			if (out[i] != null) {
				Assert.isTrue(out[i] <= candles[i].low + 1e-9,
					'SAR sat above a candle\'s low on a pure uptrend at $i');
			}
		}
	}

	public function testPsarPureDowntrendSarAboveHighs() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + (39 - i);
			bar(base + 0.5, base - 0.5, base, i);
		}];
		var psar = Psar.classic();
		var out = IndicatorBatch.run(psar, candles);
		for (i in 5...out.length) {
			if (out[i] != null) {
				Assert.isTrue(out[i] >= candles[i].high - 1e-9,
					'SAR sat below a candle\'s high on a pure downtrend at $i');
			}
		}
	}

	public function testPsarIsReadyOnlyAfterFirstSomeValue() {
		var psar = Psar.classic();
		Assert.isTrue(!psar.isReady(), "fresh PSAR must not be ready");
		var first = psar.update(bar(11.0, 9.0, 10.0, 0));
		Assert.isNull(first, "seed candle returns None by design");
		Assert.isTrue(!psar.isReady(), "is_ready must stay false until a Some value is produced");
		var second = psar.update(bar(12.0, 10.0, 11.0, 1));
		Assert.notNull(second, "second candle must emit");
		Assert.isTrue(psar.isReady());
	}

	public function testPsarResetAllowsCleanReuse() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 0.5, base - 0.5, base, i);
		}];
		var psar = Psar.classic();
		var first = IndicatorBatch.run(psar, candles);
		Assert.isTrue(psar.isReady());
		psar.reset();
		Assert.isTrue(!psar.isReady());
		var second = IndicatorBatch.run(psar, candles);
		assertScalarSeriesEqual(first, second);
	}

	public function testPsarBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(m + 1.0, m - 1.0, m, i);
		}];
		var a = Psar.classic();
		var b = Psar.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── SarExt ───────────────────────────────────────────────────────────────

	public function testSarExtRejectsInvalidParams() {
		var bad = [
			() -> new SarExt(0.0, 0.0, 0.0, 0.02, 0.2, 0.02, 0.02, 0.2),
			() -> new SarExt(0.0, 0.0, 0.02, 0.02, 0.2, 0.0, 0.02, 0.2),
			() -> new SarExt(0.0, 0.0, 0.30, 0.02, 0.2, 0.02, 0.02, 0.2),
			() -> new SarExt(0.0, 0.0, Math.NaN, 0.02, 0.2, 0.02, 0.02, 0.2),
			() -> new SarExt(0.0, 0.0, 0.02, 0.02, 0.2, 0.02, Math.POSITIVE_INFINITY, 0.2),
			() -> new SarExt(Math.NaN, 0.0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2),
			() -> new SarExt(0.0, -1.0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid SAREXT params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testSarExtAccessorsAndMetadata() {
		var s = SarExt.classic();
		Assert.equals(2, s.warmupPeriod());
		Assert.equals("SAREXT", s.name());
		Assert.isTrue(!s.isReady());
	}

	public function testSarExtSeedReturnsNoneThenEmits() {
		var s = SarExt.classic();
		Assert.isNull(s.update(bar(11.0, 9.0, 10.0, 0)));
		Assert.isTrue(!s.isReady());
		Assert.notNull(s.update(bar(12.0, 10.0, 11.0, 1)));
		Assert.isTrue(s.isReady());
	}

	public function testSarExtUptrendIsPositiveAndBelowLows() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 0.5, base - 0.5, base, i);
		}];
		var s = SarExt.classic();
		var out = IndicatorBatch.run(s, candles);
		for (i in 0...out.length) {
			if (out[i] != null) {
				Assert.isTrue(out[i] > 0.0 && out[i] <= candles[i].low + 1e-9,
					'long-phase SAREXT must be positive and below the low at $i');
			}
		}
	}

	public function testSarExtDowntrendIsNegativeAndAboveHighs() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + (39 - i);
			bar(base + 0.5, base - 0.5, base, i);
		}];
		var s = SarExt.classic();
		var out = IndicatorBatch.run(s, candles);
		for (i in 5...out.length) {
			if (out[i] != null) {
				Assert.isTrue(out[i] < 0.0 && -out[i] >= candles[i].high - 1e-9,
					'short-phase SAREXT must be negative and above the high at $i');
			}
		}
	}

	public function testSarExtPositiveStartValueBeginsLong() {
		var s = new SarExt(95.0, 0.0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2);
		Assert.isNull(s.update(bar(101.0, 99.0, 100.0, 0)));
		var v = s.update(bar(102.0, 100.0, 101.0, 1));
		Assert.isTrue(v > 0.0);
	}

	public function testSarExtNegativeStartValueBeginsShort() {
		var s = new SarExt(-105.0, 0.0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2);
		Assert.isNull(s.update(bar(101.0, 99.0, 100.0, 0)));
		var v = s.update(bar(100.0, 98.0, 99.0, 1));
		Assert.isTrue(v < 0.0);
	}

	public function testSarExtOffsetOnReversePushesSarFurther() {
		// A V-shaped path forces a reversal; with an offset the configurations diverge.
		var candles = [for (i in 0...12) {
			var base = i < 6 ? 100.0 - i * 2.0 : 88.0 + (i - 6) * 2.0;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var plain = IndicatorBatch.run(new SarExt(0.0, 0.0, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2), candles);
		var offset = IndicatorBatch.run(new SarExt(0.0, 0.1, 0.02, 0.02, 0.2, 0.02, 0.02, 0.2), candles);
		var differ = false;
		for (i in 0...plain.length) {
			var p = plain[i];
			var o = offset[i];
			if (p == null && o == null) continue;
			if (p == null || o == null || Math.abs(p - o) > 1e-12) {
				differ = true;
				break;
			}
		}
		Assert.isTrue(differ, "plain and offset configurations must diverge after a reversal");
	}

	public function testSarExtBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(m + 1.0, m - 1.0, m, i);
		}];
		var a = SarExt.classic();
		var b = SarExt.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	public function testSarExtResetAllowsCleanReuse() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 0.5, base - 0.5, base, i);
		}];
		var s = SarExt.classic();
		var first = IndicatorBatch.run(s, candles);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		var second = IndicatorBatch.run(s, candles);
		assertScalarSeriesEqual(first, second);
	}

	// ── SuperTrend ───────────────────────────────────────────────────────────

	public function testSuperTrendRejectsInvalidParams() {
		var bad = [
			() -> new SuperTrend(0, 3.0),
			() -> new SuperTrend(10, 0.0),
			() -> new SuperTrend(10, -1.0),
			() -> new SuperTrend(10, Math.NaN),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid SuperTrend params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testSuperTrendAccessorsAndMetadata() {
		var st = new SuperTrend(10, 3.0);
		Assert.equals(10, st.warmupPeriod());
		Assert.equals("SuperTrend", st.name());
	}

	public function testSuperTrendUptrendKeepsLineBelowPriceAndDirectionUp() {
		var candles = [for (i in 0...60) {
			var base = 100.0 + 2.0 * i;
			bar(base + 1.0, base - 1.0, base + 0.5, i);
		}];
		var st = SuperTrend.classic();
		var out = IndicatorBatch.run(st, candles);
		for (i in 0...out.length) {
			if (out[i] != null) {
				Assert.floatEquals(1.0, out[i].direction);
				Assert.isTrue(out[i].value < candles[i].close, "the stop line sits below price");
			}
		}
	}

	public function testSuperTrendDowntrendKeepsLineAbovePriceAndDirectionDown() {
		var candles = [for (i in 0...60) {
			var base = 220.0 - 2.0 * i;
			bar(base + 1.0, base - 1.0, base - 0.5, i);
		}];
		var st = SuperTrend.classic();
		var out = IndicatorBatch.run(st, candles);
		var emitted:Array<{o:SuperTrendOutput, close:Float}> = [];
		for (i in 0...out.length) {
			if (out[i] != null) emitted.push({o: out[i], close: candles[i].close});
		}
		// The seed bar starts the trend up; a steep decline flips it within a
		// few bars. The settled tail must be a clean downtrend.
		for (i in 10...emitted.length) {
			Assert.floatEquals(-1.0, emitted[i].o.direction);
			Assert.isTrue(emitted[i].o.value > emitted[i].close, "the stop line sits above price");
		}
	}

	public function testSuperTrendFlipsWhenPriceReverses() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base + 0.5, i);
		}];
		for (i in 0...40) {
			var base = 140.0 - i;
			candles.push(bar(base + 1.0, base - 1.0, base - 0.5, 40 + i));
		}
		var st = SuperTrend.classic();
		var dirs:Array<Float> = [];
		for (o in IndicatorBatch.run(st, candles)) {
			if (o != null) dirs.push(o.direction);
		}
		var hasUp = false;
		var hasDown = false;
		for (d in dirs) {
			if (d > 0.0) hasUp = true;
			if (d < 0.0) hasDown = true;
		}
		Assert.isTrue(hasUp, "expected an uptrend stretch");
		Assert.isTrue(hasDown, "expected a downtrend stretch");
	}

	public function testSuperTrendFirstEmissionMatchesWarmupPeriod() {
		var candles = [for (i in 0...30) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var st = SuperTrend.classic();
		var out = IndicatorBatch.run(st, candles);
		Assert.equals(10, st.warmupPeriod());
		for (i in 0...9) {
			Assert.isNull(out[i], 'index $i must be None during warmup');
		}
		Assert.notNull(out[9], "first value lands at warmup_period - 1");
	}

	public function testSuperTrendResetClearsState() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var st = SuperTrend.classic();
		IndicatorBatch.run(st, candles);
		Assert.isTrue(st.isReady());
		st.reset();
		Assert.isTrue(!st.isReady());
		Assert.isNull(st.update(candles[0]));
	}

	public function testSuperTrendBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(mid + 1.5, mid - 1.5, mid + 0.5, i);
		}];
		var a = SuperTrend.classic();
		var b = SuperTrend.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].value, streamed[i].value);
				Assert.floatEquals(batched[i].direction, streamed[i].direction);
			}
		}
	}

	// ── KaseDevStop ──────────────────────────────────────────────────────────

	public function testKaseDevStopRejectsInvalidParams() {
		var bad = [
			() -> new KaseDevStop(1, 1.0),
			() -> new KaseDevStop(30, 0.0),
			() -> new KaseDevStop(30, -1.0),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid KaseDevStop params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testKaseDevStopAccessorsAndMetadata() {
		var k = new KaseDevStop(30, 1.0);
		Assert.equals(31, k.warmupPeriod());
		Assert.equals("KaseDevStop", k.name());
		Assert.isTrue(!k.isReady());
	}

	public function testKaseDevStopFirstEmissionAtWarmupPeriod() {
		var k = new KaseDevStop(3, 1.0);
		var candles = [for (i in 0...8) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var out = IndicatorBatch.run(k, candles);
		Assert.equals(4, k.warmupPeriod());
		for (i in 0...3) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[3]);
	}

	public function testKaseDevStopUptrendKeepsStopBelowPrice() {
		var k = new KaseDevStop(5, 1.0);
		var candles = [for (i in 0...60) {
			var base = 100.0 + 2.0 * i;
			bar(base + 1.0, base - 1.0, base + 0.5, i);
		}];
		var out = IndicatorBatch.run(k, candles);
		for (i in 0...out.length) {
			if (out[i] != null) {
				Assert.floatEquals(1.0, out[i].direction);
				Assert.isTrue(out[i].value < candles[i].close, "stop below price");
			}
		}
	}

	public function testKaseDevStopRatchetsUpInUptrend() {
		var k = new KaseDevStop(5, 1.0);
		var candles = [for (i in 0...60) {
			var base = 100.0 + 2.0 * i;
			bar(base + 1.0, base - 1.0, base + 0.5, i);
		}];
		var prev = Math.NEGATIVE_INFINITY;
		for (o in IndicatorBatch.run(k, candles)) {
			if (o != null) {
				Assert.isTrue(o.value >= prev, "long stop must not fall");
				prev = o.value;
			}
		}
	}

	public function testKaseDevStopFlipsOnReversal() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base + 0.5, i);
		}];
		for (i in 0...40) {
			var base = 140.0 - i;
			candles.push(bar(base + 1.0, base - 1.0, base - 0.5, 40 + i));
		}
		var k = new KaseDevStop(5, 1.0);
		var hasUp = false;
		var hasDown = false;
		for (o in IndicatorBatch.run(k, candles)) {
			if (o != null) {
				if (o.direction > 0.0) hasUp = true;
				if (o.direction < 0.0) hasDown = true;
			}
		}
		Assert.isTrue(hasUp);
		Assert.isTrue(hasDown);
	}

	public function testKaseDevStopResetClearsState() {
		var k = new KaseDevStop(5, 1.0);
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base + 0.5, i);
		}];
		IndicatorBatch.run(k, candles);
		Assert.isTrue(k.isReady());
		k.reset();
		Assert.isTrue(!k.isReady());
		Assert.isNull(k.update(candles[0]));
	}

	public function testKaseDevStopBatchEqualsStreaming() {
		var candles = [for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.25) * 9.0;
			bar(base + 2.0, base - 1.5, base + 0.5, i);
		}];
		var a = new KaseDevStop(20, 2.0);
		var b = new KaseDevStop(20, 2.0);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].value, streamed[i].value);
				Assert.floatEquals(batched[i].direction, streamed[i].direction);
			}
		}
	}

	// ── KasePermissionStochastic ─────────────────────────────────────────────

	public function testKasePermissionStochasticRejectsZeroPeriod() {
		try {
			new KasePermissionStochastic(0, 3);
			Assert.fail("Should reject length == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new KasePermissionStochastic(9, 0);
			Assert.fail("Should reject smooth == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testKasePermissionStochasticAccessorsAndMetadata() {
		var k = KasePermissionStochastic.classic();
		// 9 + 2*3 - 2 = 13.
		Assert.equals(13, k.warmupPeriod());
		Assert.equals("KasePermissionStochastic", k.name());
		Assert.isTrue(!k.isReady());
	}

	public function testKasePermissionStochasticWarmupEmitsAtExpectedBar() {
		var k = new KasePermissionStochastic(3, 2);
		// warmup = 3 + 2*2 - 2 = 5 -> first value at input 5 (index 4).
		var candles = [for (i in 0...8) bar(11.0, 9.0, 10.5, i)];
		var out = IndicatorBatch.run(k, candles);
		Assert.isNull(out[3]);
		Assert.notNull(out[4]);
	}

	public function testKasePermissionStochasticTopOfRangeIsHigh() {
		// Close pinned at the top of a rising range -> both smoothed lines high.
		var k = new KasePermissionStochastic(5, 3);
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 2.0, base - 2.0, base + 2.0, i);
		}];
		var out = IndicatorBatch.run(k, candles);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.isTrue(last.fast > 80.0, 'fast ${last.fast} should be high');
		Assert.isTrue(last.slow > 80.0, 'slow ${last.slow} should be high');
	}

	public function testKasePermissionStochasticFlatWindowDefaultsToNeutral() {
		// Constant high/low/close -> HH == LL -> raw%K defaults to 50.
		var k = new KasePermissionStochastic(4, 2);
		var candles = [for (i in 0...20) bar(10.0, 10.0, 10.0, i)];
		var out = IndicatorBatch.run(k, candles);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(50.0, last.fast);
		Assert.floatEquals(50.0, last.slow);
	}

	public function testKasePermissionStochasticResetClearsState() {
		var k = KasePermissionStochastic.classic();
		var candles = [for (i in 0...40) bar(11.0, 9.0, 10.5, i)];
		IndicatorBatch.run(k, candles);
		Assert.isTrue(k.isReady());
		k.reset();
		Assert.isTrue(!k.isReady());
	}

	public function testKasePermissionStochasticBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.2) * 5.0;
			bar(base + 2.0, base - 2.0, base + Math.cos(i * 0.3), i);
		}];
		var a = KasePermissionStochastic.classic();
		var b = KasePermissionStochastic.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].fast, streamed[i].fast);
				Assert.floatEquals(batched[i].slow, streamed[i].slow);
			}
		}
	}

	// ── StepTrailingStop ─────────────────────────────────────────────────────

	public function testStepTrailingStopRejectsInvalidStep() {
		var bad = [
			() -> new StepTrailingStop(0.0),
			() -> new StepTrailingStop(-1.0),
			() -> new StepTrailingStop(Math.NaN),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid step size");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testStepTrailingStopAccessorsAndMetadata() {
		var s = StepTrailingStop.classic();
		Assert.equals("StepTrailingStop", s.name());
		Assert.equals(1, s.warmupPeriod());
		Assert.isTrue(!s.isReady());
	}

	public function testStepTrailingStopFirstValueSnapsBelowPrice() {
		var s = new StepTrailingStop(1.0);
		// floor((100.4 - 1) / 1) · 1 = 99.
		Assert.floatEquals(99.0, s.update(100.4));
	}

	public function testStepTrailingStopLongRatchetsInDiscreteSteps() {
		var s = new StepTrailingStop(1.0);
		var out = [for (p in [100.0, 100.5, 101.0, 102.0, 103.5]) s.update(p)];
		// 100 -> 99, 100.5 -> 99 (no advance), 101 -> 100, 102 -> 101, 103.5 -> 102.
		Assert.floatEquals(99.0, out[0]);
		Assert.floatEquals(99.0, out[1]);
		Assert.floatEquals(100.0, out[2]);
		Assert.floatEquals(101.0, out[3]);
		Assert.floatEquals(102.0, out[4]);
	}

	public function testStepTrailingStopFlipsToShortOnCloseThroughAndBack() {
		var s = new StepTrailingStop(1.0);
		s.update(100.0); // 99
		s.update(105.0); // 104
		var flipped = s.update(50.0);
		// ceil((50+1)/1)·1 = 51.
		Assert.floatEquals(51.0, flipped);
		// Rally back through 51 -> flip long at 99.
		var back = s.update(100.0);
		Assert.floatEquals(99.0, back);
	}

	public function testStepTrailingStopShortStopRatchetsDown() {
		var s = new StepTrailingStop(1.0);
		s.update(100.0);
		s.update(50.0); // short at 51
		var v = s.update(40.0);
		// ceil((40+1)/1)·1 = 41 -> min(51, 41) = 41.
		Assert.floatEquals(41.0, v);
	}

	public function testStepTrailingStopConstantSeriesHoldsStop() {
		var s = new StepTrailingStop(1.0);
		for (i in 0...30) {
			Assert.floatEquals(99.0, s.update(100.0));
		}
	}

	public function testStepTrailingStopResetClearsState() {
		var s = new StepTrailingStop(1.0);
		s.update(100.0);
		s.update(50.0);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.floatEquals(199.0, s.update(200.0));
	}

	public function testStepTrailingStopBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.3) * 8.0];
		var a = StepTrailingStop.classic();
		var b = StepTrailingStop.classic();
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── TimeBasedStop ────────────────────────────────────────────────────────

	public function testTimeBasedStopRejectsZeroMaxBars() {
		try {
			new TimeBasedStop(0);
			Assert.fail("Should reject max_bars == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTimeBasedStopAccessorsAndMetadata() {
		var t = new TimeBasedStop(5);
		Assert.equals(0, t.heldBars());
		Assert.isTrue(!t.triggered());
		Assert.equals(1, t.warmupPeriod());
		Assert.equals("TimeBasedStop", t.name());
		Assert.isTrue(!t.isReady());
	}

	public function testTimeBasedStopProgressClimbsToOne() {
		var t = new TimeBasedStop(4);
		var candles = [for (i in 0...4) bar(101.0, 99.0, 100.0, i)];
		var out = IndicatorBatch.run(t, candles);
		Assert.floatEquals(0.25, out[0]);
		Assert.floatEquals(0.50, out[1]);
		Assert.floatEquals(0.75, out[2]);
		Assert.floatEquals(1.00, out[3]);
	}

	public function testTimeBasedStopTriggersAfterMaxBars() {
		var t = new TimeBasedStop(3);
		var c = bar(101.0, 99.0, 100.0, 0);
		t.update(c);
		Assert.isTrue(!t.triggered());
		t.update(c);
		Assert.isTrue(!t.triggered());
		t.update(c);
		Assert.isTrue(t.triggered());
	}

	public function testTimeBasedStopProgressSaturatesAtOne() {
		var t = new TimeBasedStop(2);
		var candles = [for (i in 0...4) bar(101.0, 99.0, 100.0, i)];
		var out = IndicatorBatch.run(t, candles);
		Assert.floatEquals(1.0, out[2]);
		Assert.floatEquals(1.0, out[3]);
	}

	public function testTimeBasedStopResetRestartsTimer() {
		var t = new TimeBasedStop(3);
		var candles = [for (i in 0...3) bar(101.0, 99.0, 100.0, i)];
		IndicatorBatch.run(t, candles);
		Assert.isTrue(t.triggered());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.equals(0, t.heldBars());
		Assert.isTrue(!t.triggered());
		Assert.floatEquals(1.0 / 3.0, t.update(candles[0]));
	}

	public function testTimeBasedStopBatchEqualsStreaming() {
		var candles = [for (i in 0...10) bar(101.0, 99.0, 100.0, i)];
		var a = new TimeBasedStop(4);
		var b = new TimeBasedStop(4);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── VoltyStop ────────────────────────────────────────────────────────────

	public function testVoltyStopRejectsInvalidParams() {
		var bad = [
			() -> new VoltyStop(0, 2.0),
			() -> new VoltyStop(14, 0.0),
			() -> new VoltyStop(14, -1.0),
			() -> new VoltyStop(14, Math.NaN),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid VoltyStop params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testVoltyStopAccessorsAndMetadata() {
		var s = VoltyStop.classic();
		Assert.equals(14, s.warmupPeriod());
		Assert.equals("VoltyStop", s.name());
	}

	public function testVoltyStopFirstEmissionMatchesWarmup() {
		var candles = [for (i in 0...20) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var s = new VoltyStop(8, 2.0);
		var out = IndicatorBatch.run(s, candles);
		for (i in 0...7) {
			Assert.isNull(out[i], 'index $i must be None during warmup');
		}
		Assert.notNull(out[7]);
	}

	public function testVoltyStopReferenceValuesFlatMarket() {
		// H=11, L=9, C=10 -> TR=2 -> ATR=2; band = 2·2 = 4; stop = 10-4 = 6.
		var candles = [for (i in 0...20) bar(11.0, 9.0, 10.0, i)];
		var s = new VoltyStop(5, 2.0);
		for (v in IndicatorBatch.run(s, candles)) {
			if (v != null) Assert.floatEquals(6.0, v);
		}
	}

	public function testVoltyStopUptrendAnchorRatchetsUpWithClose() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var s = new VoltyStop(14, 3.0);
		var out = IndicatorBatch.run(s, candles);
		var prev:Null<Float> = null;
		for (i in 0...out.length) {
			if (out[i] == null) continue;
			if (prev != null) {
				Assert.isTrue(out[i] >= prev - 1e-9, "stop must not loosen in an uptrend");
			}
			Assert.isTrue(out[i] < candles[i].close, "uptrend stop should sit below the close");
			prev = out[i];
		}
	}

	public function testVoltyStopFlipsOnReversal() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		for (i in 0...40) {
			var base = 140.0 - 3.0 * i;
			candles.push(bar(base + 1.0, base - 1.0, base, 40 + i));
		}
		var s = new VoltyStop(14, 3.0);
		var out = IndicatorBatch.run(s, candles);
		var sawBelow = false;
		var sawAbove = false;
		for (i in 0...out.length) {
			if (out[i] == null) continue;
			if (out[i] < candles[i].close) sawBelow = true;
			if (out[i] > candles[i].close) sawAbove = true;
		}
		Assert.isTrue(sawBelow);
		Assert.isTrue(sawAbove);
	}

	public function testVoltyStopResetClearsState() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var s = VoltyStop.classic();
		IndicatorBatch.run(s, candles);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(candles[0]));
	}

	public function testVoltyStopBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(mid + 1.5, mid - 1.5, mid + 0.5, i);
		}];
		var a = VoltyStop.classic();
		var b = VoltyStop.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── YoyoExit ─────────────────────────────────────────────────────────────

	public function testYoyoExitRejectsInvalidParams() {
		var bad = [
			() -> new YoyoExit(0, 2.0),
			() -> new YoyoExit(14, 0.0),
			() -> new YoyoExit(14, -1.0),
			() -> new YoyoExit(14, Math.NaN),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid YoyoExit params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testYoyoExitAccessorsAndMetadata() {
		var s = YoyoExit.classic();
		Assert.equals(14, s.warmupPeriod());
		Assert.equals("YoyoExit", s.name());
		Assert.isTrue(s.inTrade());
	}

	public function testYoyoExitFirstEmissionMatchesWarmup() {
		var candles = [for (i in 0...20) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var s = new YoyoExit(8, 2.0);
		var out = IndicatorBatch.run(s, candles);
		for (i in 0...7) {
			Assert.isNull(out[i], 'index $i must be None during warmup');
		}
		Assert.notNull(out[7]);
	}

	public function testYoyoExitReferenceValuesFlatMarket() {
		// ATR = 2; band = 4; trail starts at close - band = 10 - 4 = 6 and stays.
		var candles = [for (i in 0...20) bar(11.0, 9.0, 10.0, i)];
		var s = new YoyoExit(5, 2.0);
		for (v in IndicatorBatch.run(s, candles)) {
			if (v != null) Assert.floatEquals(6.0, v);
		}
	}

	public function testYoyoExitUptrendTrailRatchetsUp() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var s = new YoyoExit(14, 3.0);
		var prev:Null<Float> = null;
		for (v in IndicatorBatch.run(s, candles)) {
			if (v == null) continue;
			if (prev != null) {
				Assert.isTrue(v >= prev - 1e-9, "trail must not loosen in an uptrend");
			}
			prev = v;
		}
	}

	public function testYoyoExitReentryAfterStopOut() {
		// Up-leg sets the trail, big drop stops out, recovery re-enters.
		var candles = [for (i in 0...30) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		candles.push(bar(60.0, 40.0, 50.0, 30)); // stop-out
		candles.push(bar(60.0, 50.0, 55.0, 31)); // still out
		candles.push(bar(200.0, 100.0, 200.0, 32)); // strong rally -> re-entry
		var s = new YoyoExit(14, 3.0);
		for (c in candles) {
			s.update(c);
		}
		Assert.isTrue(s.isReady());
		// Final candle's close (200) is way above the trail, so we're back in.
		Assert.isTrue(s.inTrade());
	}

	public function testYoyoExitResetClearsState() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + i;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var s = YoyoExit.classic();
		IndicatorBatch.run(s, candles);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isTrue(s.inTrade());
		Assert.isNull(s.update(candles[0]));
	}

	public function testYoyoExitBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			bar(mid + 1.5, mid - 1.5, mid + 0.5, i);
		}];
		var a = YoyoExit.classic();
		var b = YoyoExit.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── StarcBands ───────────────────────────────────────────────────────────

	public function testStarcBandsRejectsInvalidInput() {
		var bad = [
			() -> new StarcBands(0, 14, 2.0),
			() -> new StarcBands(6, 0, 2.0),
			() -> new StarcBands(6, 14, 0.0),
			() -> new StarcBands(6, 14, -1.0),
			() -> new StarcBands(6, 14, Math.NaN),
		];
		for (mk in bad) {
			try {
				mk();
				Assert.fail("Should reject invalid STARC params");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testStarcBandsAccessorsAndMetadata() {
		var s = new StarcBands(6, 15, 2.0);
		Assert.equals(15, s.warmupPeriod());
		Assert.equals("StarcBands", s.name());
	}

	public function testStarcBandsFlatMarketCollapsesBands() {
		var candles = [for (i in 0...50) bar(10.0, 10.0, 10.0, i)];
		var s = new StarcBands(6, 15, 2.0);
		var out = IndicatorBatch.run(s, candles);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(last.middle, last.upper);
		Assert.floatEquals(last.middle, last.lower);
	}

	public function testStarcBandsUpperAboveMiddleAboveLower() {
		var candles = [for (i in 0...80) {
			var m = 100.0 + Math.sin(i * 0.2) * 5.0;
			bar(m + 1.0, m - 1.0, m, i);
		}];
		var s = StarcBands.classic();
		for (o in IndicatorBatch.run(s, candles)) {
			if (o != null) {
				Assert.isTrue(o.upper >= o.middle);
				Assert.isTrue(o.middle >= o.lower);
			}
		}
	}

	public function testStarcBandsBatchEqualsStreaming() {
		var candles = [for (i in 0...40) bar(i + 1.0, i - 1.0, (i : Float), i)];
		var a = StarcBands.classic();
		var b = StarcBands.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].upper, streamed[i].upper);
				Assert.floatEquals(batched[i].middle, streamed[i].middle);
				Assert.floatEquals(batched[i].lower, streamed[i].lower);
			}
		}
	}

	public function testStarcBandsResetClearsState() {
		var candles = [for (i in 0...30) bar(i + 1.0, i - 1.0, (i : Float), i)];
		var s = StarcBands.classic();
		IndicatorBatch.run(s, candles);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(candles[0]));
	}

	// ── ProjectionBands ──────────────────────────────────────────────────────

	public function testProjectionBandsRejectsPeriodBelowTwo() {
		for (p in [0, 1]) {
			try {
				new ProjectionBands(p);
				Assert.fail("Should reject period < 2");
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
		Assert.notNull(new ProjectionBands(2));
	}

	public function testProjectionBandsAccessorsAndMetadata() {
		var pb = new ProjectionBands(14);
		Assert.equals(14, pb.warmupPeriod());
		Assert.equals("ProjectionBands", pb.name());
		Assert.isTrue(!pb.isReady());
	}

	public function testProjectionBandsWarmsUpThenEmits() {
		var pb = new ProjectionBands(3);
		Assert.isNull(pb.update(bar(10.0, 8.0, 9.0, 0)));
		Assert.isNull(pb.update(bar(12.0, 9.0, 11.0, 1)));
		Assert.notNull(pb.update(bar(11.0, 10.0, 11.0, 2)));
		Assert.isTrue(pb.isReady());
	}

	public function testProjectionBandsKnownProjection() {
		// highs 10,12,11 -> slope_h = 0.5; projected = 11, 12.5, 11 -> upper 12.5
		// lows   8, 9,10 -> slope_l = 1.0; projected = 10, 10,  10 -> lower 10
		var pb = new ProjectionBands(3);
		pb.update(bar(10.0, 8.0, 9.0, 0));
		pb.update(bar(12.0, 9.0, 11.0, 1));
		var out = pb.update(bar(11.0, 10.0, 11.0, 2));
		Assert.notNull(out);
		Assert.floatEquals(12.5, out.upper);
		Assert.floatEquals(10.0, out.lower);
		Assert.floatEquals(11.25, out.middle);
	}

	public function testProjectionBandsPerfectTrendPinsBandsToCurrentExtremes() {
		// High_i and Low_i both rise by exactly 1 per bar: every projected high
		// collapses onto the current high, every projected low onto the current low.
		var pb = new ProjectionBands(5);
		var last = null;
		for (i in 0...10) {
			var v = pb.update(bar(100.0 + i, 95.0 + i, 100.0 + i, i));
			if (v != null) last = v;
		}
		Assert.notNull(last);
		Assert.floatEquals(109.0, last.upper);
		Assert.floatEquals(104.0, last.lower);
		Assert.floatEquals(106.5, last.middle);
	}

	public function testProjectionBandsResetClearsState() {
		var pb = new ProjectionBands(3);
		pb.update(bar(10.0, 8.0, 9.0, 0));
		pb.update(bar(12.0, 9.0, 11.0, 1));
		pb.update(bar(11.0, 10.0, 11.0, 2));
		Assert.isTrue(pb.isReady());
		pb.reset();
		Assert.isTrue(!pb.isReady());
		Assert.isNull(pb.update(bar(10.0, 8.0, 9.0, 3)));
	}

	public function testProjectionBandsBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.35) * 6.0;
			bar(m + 1.5, m - 1.5, m + Math.cos(i * 0.2), i);
		}];
		var a = new ProjectionBands(9);
		var b = new ProjectionBands(9);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].upper, streamed[i].upper);
				Assert.floatEquals(batched[i].middle, streamed[i].middle);
				Assert.floatEquals(batched[i].lower, streamed[i].lower);
			}
		}
	}

	// ── ProjectionOscillator ─────────────────────────────────────────────────

	public function testProjectionOscillatorRejectsPeriodBelowTwo() {
		try {
			new ProjectionOscillator(1);
			Assert.fail("Should reject period < 2");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		Assert.notNull(new ProjectionOscillator(2));
	}

	public function testProjectionOscillatorAccessorsAndMetadata() {
		var po = new ProjectionOscillator(14);
		Assert.equals(14, po.warmupPeriod());
		Assert.equals("ProjectionOscillator", po.name());
		Assert.isTrue(!po.isReady());
	}

	public function testProjectionOscillatorWarmsUpThenEmits() {
		var po = new ProjectionOscillator(3);
		Assert.isNull(po.update(bar(10.0, 8.0, 9.0, 0)));
		Assert.isNull(po.update(bar(12.0, 9.0, 11.0, 1)));
		Assert.notNull(po.update(bar(11.0, 10.0, 11.0, 2)));
		Assert.isTrue(po.isReady());
	}

	public function testProjectionOscillatorKnownPosition() {
		// Same window as ProjectionBands known_projection: upper 12.5, lower 10.
		// close 11 -> 100 * (11 - 10) / (12.5 - 10) = 40.
		var po = new ProjectionOscillator(3);
		po.update(bar(10.0, 8.0, 9.0, 0));
		po.update(bar(12.0, 9.0, 11.0, 1));
		var out = po.update(bar(11.0, 10.0, 11.0, 2));
		Assert.floatEquals(40.0, out);
	}

	public function testProjectionOscillatorCollapsedBandsReturnNeutral() {
		// Zero-range, perfectly trending candles: upper == lower every bar.
		var po = new ProjectionOscillator(3);
		var last:Null<Float> = null;
		for (i in 0...6) {
			var v = 100.0 + i;
			var out = po.update(bar(v, v, v, i));
			if (out != null) last = out;
		}
		Assert.floatEquals(50.0, last);
	}

	public function testProjectionOscillatorResetClearsState() {
		var po = new ProjectionOscillator(3);
		po.update(bar(10.0, 8.0, 9.0, 0));
		po.update(bar(12.0, 9.0, 11.0, 1));
		po.update(bar(11.0, 10.0, 11.0, 2));
		Assert.isTrue(po.isReady());
		po.reset();
		Assert.isTrue(!po.isReady());
		Assert.isNull(po.update(bar(10.0, 8.0, 9.0, 3)));
	}

	public function testProjectionOscillatorBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.35) * 6.0;
			bar(m + 1.5, m - 1.5, m + Math.cos(i * 0.2), i);
		}];
		var a = new ProjectionOscillator(9);
		var b = new ProjectionOscillator(9);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── Stochastic ───────────────────────────────────────────────────────────

	/** Naive %K computation for cross-checks (transcribed from the Rust fixture). */
	static function naiveK(candles:Array<Bar>, kPeriod:Int):Array<Null<Float>> {
		return [for (i in 0...candles.length) {
			if (i + 1 < kPeriod) {
				(null : Null<Float>);
			} else {
				var hh = Math.NEGATIVE_INFINITY;
				var ll = Math.POSITIVE_INFINITY;
				for (j in (i + 1 - kPeriod)...(i + 1)) {
					if (candles[j].high > hh) hh = candles[j].high;
					if (candles[j].low < ll) ll = candles[j].low;
				}
				var range = hh - ll;
				var cl = candles[i].close;
				range == 0.0 ? 50.0 : 100.0 * (cl - ll) / range;
			}
		}];
	}

	public function testStochasticRejectsZeroPeriods() {
		try {
			new Stochastic(0, 3);
			Assert.fail("Should reject k_period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Stochastic(14, 0);
			Assert.fail("Should reject d_period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testStochasticClassicPeriodsAndMetadata() {
		var s = Stochastic.classic();
		// Warmup for the classic config: k_period + d_period - 1 = 16.
		Assert.equals(16, s.warmupPeriod());
		Assert.equals("Stochastic", s.name());
	}

	public function testStochasticCloseAtHighYieldsK100() {
		var candles = [
			bar(10.0, 8.0, 9.0, 0),
			bar(11.0, 9.0, 10.0, 1),
			bar(12.0, 10.0, 12.0, 2), // close == high == HH
		];
		var s = new Stochastic(3, 1);
		var out = IndicatorBatch.run(s, candles);
		Assert.floatEquals(100.0, out[2].k);
	}

	public function testStochasticCloseAtLowYieldsK0() {
		var candles = [
			bar(10.0, 8.0, 9.0, 0),
			bar(11.0, 9.0, 10.0, 1),
			bar(12.0, 8.0, 8.0, 2), // close == LL
		];
		var s = new Stochastic(3, 1);
		var out = IndicatorBatch.run(s, candles);
		Assert.floatEquals(0.0, out[2].k);
	}

	public function testStochasticFlatRangeYieldsK50() {
		var candles = [for (i in 0...20) bar(10.0, 10.0, 10.0, i)];
		var s = new Stochastic(14, 3);
		for (o in IndicatorBatch.run(s, candles)) {
			if (o != null) {
				Assert.floatEquals(50.0, o.k);
				Assert.floatEquals(50.0, o.d);
			}
		}
	}

	public function testStochasticKMatchesNaive() {
		var candles = [for (i in 0...60) {
			var mid = 50.0 + Math.sin(i * 0.4) * 10.0;
			bar(mid + 2.0, mid - 2.0, mid + Math.cos(i * 0.7), i);
		}];
		var s = new Stochastic(14, 3);
		var out = IndicatorBatch.run(s, candles);
		var naive = naiveK(candles, 14);
		for (i in 0...out.length) {
			if (out[i] != null) {
				Assert.floatEquals(naive[i], out[i].k);
			}
		}
	}

	public function testStochasticDIsSmaOfK() {
		var candles = [for (i in 0...60) {
			var mid = 50.0 + Math.sin(i) * 5.0;
			bar(mid + 1.5, mid - 1.5, mid, i);
		}];
		var s = new Stochastic(14, 3);
		var out = IndicatorBatch.run(s, candles);
		var naiveKs = naiveK(candles, 14);
		// The first emitted %D is the SMA of the first three valid %K values.
		var firstEmitIdx = -1;
		for (i in 0...out.length) {
			if (out[i] != null) {
				firstEmitIdx = i;
				break;
			}
		}
		Assert.isTrue(firstEmitIdx >= 0, "d eventually emits");
		var firstD = out[firstEmitIdx].d;
		var want = (naiveKs[firstEmitIdx - 2] + naiveKs[firstEmitIdx - 1] + naiveKs[firstEmitIdx]) / 3.0;
		Assert.floatEquals(want, firstD);
	}

	public function testStochasticBatchEqualsStreaming() {
		var candles = [for (i in 0...50) {
			var mid = 100.0 + i * 0.5;
			bar(mid + 2.0, mid - 2.0, mid, i);
		}];
		var a = new Stochastic(14, 3);
		var b = new Stochastic(14, 3);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].k, streamed[i].k);
				Assert.floatEquals(batched[i].d, streamed[i].d);
			}
		}
	}

	public function testStochasticResetClearsState() {
		var s = new Stochastic(5, 3);
		var candles = [for (i in 0...10) bar(10.0 + i, 5.0, 7.0, i)];
		IndicatorBatch.run(s, candles);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(candles[0]));
	}

	// ── StochasticCci ────────────────────────────────────────────────────────

	public function testStochasticCciRejectsZeroPeriod() {
		try {
			new StochasticCci(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testStochasticCciAccessorsAndMetadata() {
		var sc = new StochasticCci(14);
		Assert.equals(27, sc.warmupPeriod());
		Assert.equals("StochasticCCI", sc.name());
	}

	public function testStochasticCciFirstEmissionMatchesWarmupPeriod() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.4) * 8.0;
			bar(base + 1.0, base - 1.0, base, i);
		}];
		var sc = new StochasticCci(5);
		var out = IndicatorBatch.run(sc, candles);
		Assert.equals(9, sc.warmupPeriod());
		for (i in 0...8) {
			Assert.isNull(out[i], 'index $i must be None during warmup');
		}
		Assert.notNull(out[8]);
	}

	public function testStochasticCciBoundedZeroToHundred() {
		var candles = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.35) * 12.0;
			bar(base + 2.0, base - 2.0, base, i);
		}];
		var sc = new StochasticCci(9);
		for (v in IndicatorBatch.run(sc, candles)) {
			if (v != null) {
				Assert.isTrue(v >= 0.0 && v <= 100.0, '%K $v left [0, 100]');
			}
		}
	}

	public function testStochasticCciFlatMarketIsNeutral() {
		// Constant candles -> CCI pinned at 0 -> zero range -> neutral 50.
		var sc = new StochasticCci(4);
		var candles = [for (i in 0...20) bar(10.0, 10.0, 10.0, i)];
		var out = IndicatorBatch.run(sc, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(50.0, last);
	}

	public function testStochasticCciHighestCciInWindowIsHundred() {
		// A long rise then a strong final push so the last CCI tops its window.
		var candles = [for (i in 0...20) bar(i + 1.0, i - 1.0, (i : Float), i)];
		candles.push(bar(100.0, 98.0, 100.0, 20));
		var sc = new StochasticCci(5);
		var out = IndicatorBatch.run(sc, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(100.0, last);
	}

	public function testStochasticCciResetClearsState() {
		var sc = new StochasticCci(5);
		var candles = [for (i in 0...30) bar(i + 1.0, i - 1.0, (i : Float), i)];
		IndicatorBatch.run(sc, candles);
		Assert.isTrue(sc.isReady());
		sc.reset();
		Assert.isTrue(!sc.isReady());
		Assert.isNull(sc.update(bar(2.0, 0.0, 1.0, 0)));
	}

	public function testStochasticCciBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var base = 50.0 + Math.sin(i * 0.5) * 10.0;
			bar(base + 1.5, base - 1.5, base, i);
		}];
		var a = new StochasticCci(9);
		var b = new StochasticCci(9);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarSeriesEqual(batched, streamed);
	}

	// ── StochRsi ─────────────────────────────────────────────────────────────

	public function testStochRsiRejectsZeroPeriod() {
		try {
			new StochRsi(0, 14);
			Assert.fail("Should reject rsi_period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new StochRsi(14, 0);
			Assert.fail("Should reject stoch_period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testStochRsiAccessorsAndMetadata() {
		var sr = new StochRsi(14, 14);
		Assert.equals("StochRSI", sr.name());
		Assert.isNull(sr.value());
		for (i in 1...sr.warmupPeriod() + 1) {
			sr.update(100.0 + i);
		}
		Assert.notNull(sr.value());
	}

	public function testStochRsiFirstEmissionAtWarmupPeriod() {
		var sr = new StochRsi(5, 4);
		Assert.equals(9, sr.warmupPeriod());
		var prices = [for (i in 1...41) 100.0 + Math.sin(i * 0.6) * 8.0];
		var out = IndicatorBatch.run(sr, prices);
		for (i in 0...8) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[8]);
	}

	public function testStochRsiFlatRsiWindowYields50() {
		// A constant price series gives a constant RSI, so the StochRSI window
		// has zero range and reports the neutral midpoint.
		var sr = new StochRsi(5, 4);
		var out = IndicatorBatch.run(sr, [for (_ in 0...40) 100.0]);
		for (i in 9...out.length) {
			if (out[i] != null) Assert.floatEquals(50.0, out[i]);
		}
	}

	public function testStochRsiPureUptrendYields50() {
		// A pure uptrend pins RSI at 100, so its window is again flat.
		var sr = new StochRsi(5, 4);
		var out = IndicatorBatch.run(sr, [for (i in 1...41) (i : Float)]);
		for (i in 9...out.length) {
			if (out[i] != null) Assert.floatEquals(50.0, out[i]);
		}
	}

	public function testStochRsiOutputStaysWithin0To100() {
		var sr = new StochRsi(14, 14);
		var prices = [for (i in 1...201) 100.0 + Math.sin(i * 0.3) * 15.0 + Math.cos(i * 0.07) * 6.0];
		for (v in IndicatorBatch.run(sr, prices)) {
			if (v != null) {
				Assert.isTrue(v >= 0.0 && v <= 100.0, 'StochRSI out of range: $v');
			}
		}
	}

	public function testStochRsiIgnoresNonFiniteInput() {
		var sr = new StochRsi(5, 4);
		var prices = [for (i in 1...41) 100.0 + Math.sin(i * 0.6) * 8.0];
		var out = IndicatorBatch.run(sr, prices);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(last, sr.update(Math.NaN));
		Assert.floatEquals(last, sr.update(Math.POSITIVE_INFINITY));
	}

	public function testStochRsiResetClearsState() {
		var sr = new StochRsi(5, 4);
		IndicatorBatch.run(sr, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(sr.isReady());
		sr.reset();
		Assert.isTrue(!sr.isReady());
		Assert.isNull(sr.update(1.0));
	}

	public function testStochRsiBatchEqualsStreaming() {
		var prices = [for (i in 1...121) 100.0 + Math.sin(i * 0.25) * 12.0];
		var a = new StochRsi(14, 14);
		var b = new StochRsi(14, 14);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		assertScalarSeriesEqual(batched, streamed);
	}
}
