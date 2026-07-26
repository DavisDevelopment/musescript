package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.FryPanBottom;
import musescript.indicators.lib.Garch11;
import musescript.indicators.lib.Gartley;
import musescript.indicators.lib.GoldenPocket;
import musescript.indicators.lib.GrangerCausality;
import musescript.indicators.geom.HarmonicVizEmit;

/**
 * Batch 32: 3 indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch32 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, volume:Float, i:Int):Bar {
		return bar(price, price, price, price, volume, i);
	}

	// ── FryPanBottom ─────────────────────────────────────────────────────────

	public function testFryPanBottomRejectsSmallPeriod() {
		try {
			new FryPanBottom(4);
			Assert.fail("Should reject period < 5");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		// period >= 5 should succeed
		var f = new FryPanBottom(5);
		Assert.notNull(f);
	}

	public function testFryPanBottomAccessorsAndMetadata() {
		var f = new FryPanBottom(9);
		Assert.equals("FryPanBottom", f.name());
		Assert.equals(9, f.warmupPeriod());
		Assert.isTrue(!f.isReady());
		Assert.isNull(f.update(bar(100.0, 100.5, 99.5, 100.0, 1000.0, 0)));
	}

	public function testFryPanBottomFirstEmissionAtWarmupPeriod() {
		var f = new FryPanBottom(5);
		var bars = [
			bar(100.0, 100.5, 99.5, 100.0, 1.0, 0),
			bar(99.0, 99.5, 98.5, 99.0, 1.0, 1),
			bar(98.0, 98.5, 97.5, 98.0, 1.0, 2),
			bar(99.0, 99.5, 98.5, 99.0, 1.0, 3),
			bar(101.0, 101.5, 100.5, 101.0, 1.0, 4),
			bar(102.0, 102.5, 101.5, 102.0, 1.0, 5),
		];
		var out = IndicatorBatch.run(f, bars);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[4]);
	}

	public function testFryPanBottomRoundedBottomThenRecoverySignals() {
		// U-shaped base then recovery.
		var f = new FryPanBottom(9);
		var closes = [100.0, 98.0, 96.0, 95.0, 96.0, 98.0, 101.0, 103.0, 105.0];
		var bars = [for (i in 0...closes.length) {
			var c = closes[i];
			bar(c, c + 0.5, c - 0.5, c, 1000.0, i);
		}];
		var out = IndicatorBatch.run(f, bars);
		var last = out[out.length - 1];
		Assert.floatEquals(1.0, last);
	}

	public function testFryPanBottomOneSidedDropIsZero() {
		// Straight decline (min at the end) is not a bowl.
		var f = new FryPanBottom(9);
		var bars = [for (i in 0...9) {
			var c = 100.0 - i;
			bar(c, c + 0.5, c - 0.5, c, 1000.0, i);
		}];
		var out = IndicatorBatch.run(f, bars);
		var last = out[out.length - 1];
		Assert.floatEquals(0.0, last);
	}

	public function testFryPanBottomNoRecoveryIsZero() {
		// Bowl shape but the last close never climbs above the first.
		var f = new FryPanBottom(9);
		var closes = [100.0, 98.0, 96.0, 95.0, 96.0, 97.0, 98.0, 99.0, 99.5];
		var bars = [for (i in 0...closes.length) {
			var c = closes[i];
			bar(c, c + 0.5, c - 0.5, c, 1000.0, i);
		}];
		var out = IndicatorBatch.run(f, bars);
		var last = out[out.length - 1];
		Assert.floatEquals(0.0, last);
	}

	public function testFryPanBottomResetClearsState() {
		var f = new FryPanBottom(5);
		var bars = [
			bar(100.0, 100.5, 99.5, 100.0, 1.0, 0),
			bar(99.0, 99.5, 98.5, 99.0, 1.0, 1),
			bar(98.0, 98.5, 97.5, 98.0, 1.0, 2),
			bar(99.0, 99.5, 98.5, 99.0, 1.0, 3),
			bar(101.0, 101.5, 100.5, 101.0, 1.0, 4),
		];
		IndicatorBatch.run(f, bars);
		Assert.isTrue(f.isReady());
		f.reset();
		Assert.isTrue(!f.isReady());
		Assert.isNull(f.update(bar(100.0, 100.5, 99.5, 100.0, 1.0, 0)));
	}

	public function testFryPanBottomBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(base, base + 0.5, base - 0.5, base, 1000.0, i);
		}];
		var a = new FryPanBottom(9);
		var b = new FryPanBottom(9);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── Garch11 ──────────────────────────────────────────────────────────────

	public function testGarch11RejectsInvalidParams() {
		// omega must be > 0
		try {
			new Garch11(0.0, 0.1, 0.8);
			Assert.fail("Should reject omega <= 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}

		// alpha + beta must be < 1
		try {
			new Garch11(0.001, 0.5, 0.5);
			Assert.fail("Should reject alpha + beta >= 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testGarch11AccessorsAndMetadata() {
		var g = new Garch11(0.001, 0.1, 0.85);
		Assert.equals("Garch11", g.name());
		Assert.equals(2, g.warmupPeriod());
		Assert.isTrue(!g.isReady());
		Assert.isNull(g.update(100.0));
	}

	public function testGarch11FirstEmissionIsUnconditional() {
		// First log return emits sqrt(unconditional variance).
		var g = new Garch11(0.002, 0.1, 0.85);
		Assert.isNull(g.update(100.0));
		var out = g.update(110.0);
		Assert.notNull(out);
		var expected = Math.sqrt(0.002 / 0.05);
		Assert.floatEquals(expected, out);
	}

	public function testGarch11KnownValue() {
		// σ²₁ = uncond; σ²₂ = ω + α·r1² + β·uncond.
		var omega = 0.002;
		var alpha = 0.1;
		var beta = 0.85;
		var g = new Garch11(omega, alpha, beta);
		var prices = [100.0, 110.0, 99.0];
		var outs = [for (p in prices) g.update(p)];

		var uncond = omega / (1.0 - alpha - beta);
		Assert.floatEquals(Math.sqrt(uncond), outs[1]);

		var r1 = Math.log(110.0 / 100.0);
		var var2 = omega + alpha * r1 * r1 + beta * uncond;
		Assert.floatEquals(Math.sqrt(var2), outs[2]);
	}

	public function testGarch11FlatSeriesConvergesLongRun() {
		// With zero returns, variance mean-reverts to ω / (1 − β).
		var omega = 0.002;
		var beta = 0.85;
		var g = new Garch11(omega, 0.10, beta);
		var outs:Array<Null<Float>> = [];
		for (i in 0...400) {
			outs.push(g.update(100.0));
		}
		var lastNonNull:Null<Float> = null;
		for (v in outs) {
			if (v != null) lastNonNull = v;
		}
		var fixedPoint = Math.sqrt(omega / (1.0 - beta));
		Assert.floatEquals(fixedPoint, lastNonNull);
	}

	public function testGarch11OutputIsStrictlyPositive() {
		var g = new Garch11(0.000002, 0.1, 0.88);
		for (i in 1...200) {
			var price = 100.0 + Math.sin(i * 0.3) * 12.0;
			var v = g.update(price);
			if (v != null) {
				Assert.isTrue(v > 0.0, 'GARCH volatility must be positive, got ${v}');
			}
		}
	}

	public function testGarch11IgnoresNonFiniteInput() {
		var g = new Garch11(0.001, 0.1, 0.85);
		var outs:Array<Null<Float>> = [];
		for (i in 1...20) {
			outs.push(g.update(i + 0.0));
		}
		var lastValid:Null<Float> = null;
		for (v in outs) {
			if (v != null) lastValid = v;
		}
		Assert.equals(lastValid, g.update(Math.NaN));
		Assert.equals(lastValid, g.update(Math.POSITIVE_INFINITY));
	}

	public function testGarch11SkipsNonPositivePrices() {
		var g = new Garch11(0.001, 0.1, 0.85);
		var warmup:Array<Null<Float>> = [];
		for (i in 1...20) {
			warmup.push(g.update(i + 0.0));
		}
		var baseline:Null<Float> = null;
		for (v in warmup) {
			if (v != null) baseline = v;
		}
		Assert.equals(baseline, g.update(-5.0));
		Assert.equals(baseline, g.update(0.0));
	}

	public function testGarch11ResetClearsState() {
		var g = new Garch11(0.001, 0.1, 0.85);
		for (i in 1...20) {
			g.update(i + 0.0);
		}
		Assert.isTrue(g.isReady());
		g.reset();
		Assert.isTrue(!g.isReady());
		Assert.isNull(g.update(1.0));
	}

	public function testGarch11BatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 1...120) {
			prices.push(100.0 + Math.sin(i * 0.25) * 9.0);
		}
		var a = new Garch11(0.000002, 0.1, 0.88);
		var b = new Garch11(0.000002, 0.1, 0.88);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── GrangerCausality ─────────────────────────────────────────────────────

	public function testGrangerCausalityRejectsBadParameters() {
		// lag must be >= 1
		try {
			new GrangerCausality(10, 0);
			Assert.fail("Should reject lag < 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}

		// period must be >= 3*lag + 2
		try {
			new GrangerCausality(4, 1);
			Assert.fail("Should reject period < 3*lag + 2");
		} catch (e:Dynamic) {
			Assert.pass();
		}

		// Valid parameters should succeed
		var g = new GrangerCausality(5, 1);
		Assert.notNull(g);
	}

	public function testGrangerCausalityAccessorsAndMetadata() {
		var g = new GrangerCausality(60, 2);
		Assert.equals(60, g.warmupPeriod());
		Assert.equals("GrangerCausality", g.name());
		Assert.isTrue(!g.isReady());
	}

	public function testGrangerCausalityWarmupReturnsNone() {
		var g = new GrangerCausality(5, 1);
		for (t in 0...4) {
			Assert.isNull(g.update({a: t + 0.0, b: t * 0.5}));
		}
		Assert.notNull(g.update({a: 4.0, b: 2.0}));
		Assert.isTrue(g.isReady());
	}

	public function testGrangerCausalityBLeadingAHasPositiveStatistic() {
		// a[t] is driven by b[t-1] ⇒ b helps predict a.
		var pairs:Array<{a: Float, b: Float}> = [];
		var prevDrive = 0.0;
		for (t in 0...120) {
			var drive = Math.sin(t * 0.3) + 0.4 * Math.cos(t * 0.11);
			var a = 0.8 * prevDrive + 0.05 * Math.sin(t * 0.7);
			prevDrive = drive;
			pairs.push({a: a, b: drive});
		}

		var g = new GrangerCausality(60, 1);
		var outs:Array<Null<Float>> = [];
		for (pair in pairs) {
			outs.push(g.update(pair));
		}
		var lastValid:Null<Float> = null;
		for (v in outs) {
			if (v != null) lastValid = v;
		}
		Assert.isTrue(lastValid > 1.0, 'F-stat ${lastValid} should be > 1.0');
	}

	public function testGrangerCausalityConstantBIsSingularAndReturnsZero() {
		// b is constant ⇒ singular ⇒ 0.
		var pairs:Array<{a: Float, b: Float}> = [];
		for (t in 0...40) {
			pairs.push({a: t + 0.0 + Math.sin(t * 0.6), b: 3.0});
		}

		var g = new GrangerCausality(20, 1);
		var outs:Array<Null<Float>> = [];
		for (pair in pairs) {
			outs.push(g.update(pair));
		}
		var lastValid:Null<Float> = null;
		for (v in outs) {
			if (v != null) lastValid = v;
		}
		Assert.floatEquals(0.0, lastValid);
	}

	public function testGrangerCausalityConstantARestrictedSingularReturnsZero() {
		// a is constant ⇒ restricted singular ⇒ 0.
		var pairs:Array<{a: Float, b: Float}> = [];
		for (t in 0...40) {
			pairs.push({a: 5.0, b: Math.sin(t * 0.4)});
		}

		var g = new GrangerCausality(20, 1);
		var outs:Array<Null<Float>> = [];
		for (pair in pairs) {
			outs.push(g.update(pair));
		}
		var lastValid:Null<Float> = null;
		for (v in outs) {
			if (v != null) lastValid = v;
		}
		Assert.floatEquals(0.0, lastValid);
	}

	public function testGrangerCausalityResetClearsState() {
		var g = new GrangerCausality(8, 1);
		for (t in 0...12) {
			g.update({
				a: t + 0.0 + Math.sin(t * 0.7),
				b: Math.cos(t * 0.3)
			});
		}
		Assert.isTrue(g.isReady());
		g.reset();
		Assert.isTrue(!g.isReady());
		Assert.isNull(g.update({a: 1.0, b: 1.0}));
	}

	public function testGrangerCausalityBatchEqualsStreaming() {
		var pairs:Array<{a: Float, b: Float}> = [];
		for (t in 0...80) {
			var b = Math.sin(t * 0.4);
			pairs.push({
				a: 0.6 * Math.sin((t > 0 ? t - 1 : 0) * 0.4) + 0.1 * (t % 3),
				b: b
			});
		}

		var a = new GrangerCausality(30, 2);
		var b = new GrangerCausality(30, 2);
		var batched = IndicatorBatch.run(a, pairs);
		var streamed = [for (p in pairs) b.update(p)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	public function testGrangerCausalityNonFiniteInputReturnsNone() {
		var g = new GrangerCausality(5, 1);
		Assert.isNull(g.update({a: Math.NaN, b: 1.0}));
		Assert.isNull(g.update({a: 1.0, b: Math.POSITIVE_INFINITY}));
		// Rejected ticks leave no trace: fresh window still warms up
		for (t in 0...4) {
			Assert.isNull(g.update({a: t + 0.0, b: t * 0.5}));
		}
		Assert.notNull(g.update({a: 4.0, b: 2.0}));
	}

	// ── Gartley ──────────────────────────────────────────────────────────────

	public function testGartleyAccessorsAndMetadata() {
		var g = new Gartley();
		Assert.equals("Gartley", g.name());
		Assert.equals(6, g.warmupPeriod());
		Assert.isTrue(!g.isReady());
	}

	public function testGartleyBullishGartleyIsPlus() {
		// Bullish Gartley: pivots [150, 100, 140, 115.3, 127.65, 108.56]
		var g = new Gartley();
		var pivots = [150.0, 100.0, 140.0, 115.3, 127.65, 108.56];
		var bars = candlesForPivots(pivots);
		var results:Array<Null<HarmonicVizOutput>> = [];
		for (b in bars) {
			results.push(g.update(b));
		}
		var last = results[results.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(1.0, last.signal);
	}

	public function testGartleyBearishGartleyIsMinus() {
		// Bearish Gartley
		var g = new Gartley();
		var pivots = [150.0, 110.0, 134.7, 122.35, 141.44];
		var bars = candlesForPivots(pivots);
		var results:Array<Null<HarmonicVizOutput>> = [];
		for (b in bars) {
			results.push(g.update(b));
		}
		var last = results[results.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(-1.0, last.signal);
	}

	public function testGartleyOutOfRatioDoesNotTrigger() {
		// Five pivots but D completion out of ratio
		var g = new Gartley();
		var pivots = [150.0, 100.0, 140.0, 110.0, 135.0, 105.0];
		var bars = candlesForPivots(pivots);
		var results:Array<Null<HarmonicVizOutput>> = [];
		for (b in bars) {
			results.push(g.update(b));
		}
		var last = results[results.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(0.0, last.signal);
	}

	public function testGartleyResetClearsState() {
		var g = new Gartley();
		var pivots = [150.0, 100.0, 140.0];
		var bars = candlesForPivots(pivots);
		for (b in bars) {
			g.update(b);
		}
		g.reset();
		Assert.isTrue(!g.isReady());
		var c = bar(99.5, 100.0, 99.5, 99.5, 1.0, 0);
		Assert.floatEquals(0.0, g.update(c).signal);
	}

	// ── GoldenPocket ─────────────────────────────────────────────────────────

	public function testGoldenPocketAccessorsAndMetadata() {
		var g = new GoldenPocket();
		Assert.equals("GoldenPocket", g.name());
		Assert.equals(2, g.warmupPeriod());
		Assert.isTrue(!g.isReady());
	}

	public function testGoldenPocketNoOutputBeforeTwoPivots() {
		var g = new GoldenPocket();
		var pivots = [120.0];
		var bars = candlesForPivots(pivots);
		var results:Array<Null<GoldenPocketOutput>> = [];
		for (b in bars) {
			results.push(g.update(b));
		}
		for (v in results) {
			Assert.isNull(v);
		}
	}

	public function testGoldenPocketZoneOfDownLeg() {
		// Leg 200 (high) -> 100 (low), span = 100.
		// 61.8% = 161.8, 65% = 165 → sorted band [161.8, 165], mid 163.4.
		var g = new GoldenPocket();
		var pivots = [200.0, 100.0];
		var bars = candlesForPivots(pivots);
		var lastVal:Null<GoldenPocketOutput> = null;
		for (b in bars) {
			lastVal = g.update(b);
		}
		Assert.isTrue(g.isReady());
		Assert.notNull(lastVal);
		Assert.floatEquals(161.8, lastVal.low);
		Assert.floatEquals(165.0, lastVal.high);
		Assert.floatEquals(163.4, lastVal.mid);
	}

	public function testGoldenPocketBandIsSortedForUpLeg() {
		// Latest leg 100 (low) -> 250 (high): band should be sorted low <= high.
		var g = new GoldenPocket();
		var pivots = [200.0, 100.0, 250.0];
		var bars = candlesForPivots(pivots);
		var lastVal:Null<GoldenPocketOutput> = null;
		for (b in bars) {
			lastVal = g.update(b);
		}
		Assert.isTrue(lastVal.low <= lastVal.high);
		var mid_expected = (lastVal.low + lastVal.high) / 2.0;
		Assert.floatEquals(mid_expected, lastVal.mid);
	}

	public function testGoldenPocketResetClearsState() {
		var g = new GoldenPocket();
		var pivots = [200.0, 100.0];
		var bars = candlesForPivots(pivots);
		for (b in bars) {
			g.update(b);
		}
		g.reset();
		Assert.isTrue(!g.isReady());
		var c = bar(99.5, 100.0, 99.5, 99.5, 1.0, 0);
		Assert.isNull(g.update(c));
	}

	// ── Helper: candles_for_pivots ───────────────────────────────────────────

	static function candlesForPivots(pivots:Array<Float>):Array<Bar> {
		var out:Array<Bar> = [];
		out.push(bar(pivots[0], pivots[0], pivots[0] * 0.999, pivots[0] * 0.999, 1.0, 0));

		var ts = 0;
		for (k in 0...pivots.length) {
			ts++;
			var price = pivots[k];
			var isHigh = k % 2 == 0;
			var next = if (k + 1 < pivots.length) {
				pivots[k + 1];
			} else {
				isHigh ? price * 0.90 : price * 1.10;
			};

			var b = if (isHigh) {
				// Reverse down from candidate high
				bar(price * 0.99, price * 0.99, next, next, 1.0, ts);
			} else {
				// Reverse up from candidate low
				bar(next, next, price * 1.01, price * 1.01, 1.0, ts);
			};
			out.push(b);
		}
		return out;
	}
}
