package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.MurreyMathLines;
import musescript.indicators.lib.NewPriceLines;
import musescript.indicators.lib.Parkinson;
import musescript.indicators.lib.Pgo;
import musescript.indicators.lib.PlusDi;
import musescript.indicators.lib.PlusDm;
import musescript.indicators.lib.RogersSatchell;
import musescript.indicators.lib.Rwi;
import musescript.indicators.lib.Vortex;
import musescript.indicators.lib.VolatilityCone;
import musescript.indicators.lib.VolatilityRatio;
import musescript.indicators.lib.WaveTrend;
import musescript.indicators.lib.WoodiePivots;
import musescript.indicators.lib.YangZhang;
import musescript.indicators.lib.TtmSqueeze;
import musescript.indicators.lib.TtmTrend;
import musescript.indicators.lib.UltimateOscillator;
import musescript.indicators.lib.VerticalHorizontalFilter;

/**
 * Batch 45: 18 indicators ported from wickra-core (volatility estimators,
 * DI/DM, pivots, misc candle studies). Known-value cases transcribed directly
 * from the Rust fixture blocks; batch_equals_streaming verifies
 * IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch45 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, i:Int):Bar {
		return bar(price, price, price, price, 1.0, i);
	}

	// ── MurreyMathLines ──────────────────────────────────────────────────────

	/** Rust helper: c(high, low) → Candle(low, high, low, midpoint, 1000, 0). */
	static function mmlBar(high:Float, low:Float, i:Int):Bar {
		return bar(low, high, low, (high + low) / 2.0, 1000.0, i);
	}

	public function testMurreyMathLinesRejectsZeroPeriod() {
		try {
			new MurreyMathLines(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testMurreyMathLinesAccessorsAndMetadata() {
		var m = new MurreyMathLines(64);
		Assert.equals(64, m.warmupPeriod());
		Assert.equals("MurreyMathLines", m.name());
		Assert.isTrue(!m.isReady());
	}

	public function testMurreyMathLinesFirstEmissionAtWarmupPeriod() {
		var m = new MurreyMathLines(4);
		var bars = [for (i in 0...6) mmlBar(101.0 + i, 99.0 + i, i)];
		var out = IndicatorBatch.run(m, bars);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testMurreyMathLinesEighthsAreEvenlySpaced() {
		// Frame [100, 180] over the window -> step = 10.
		var m = new MurreyMathLines(2);
		var out = IndicatorBatch.run(m, [mmlBar(180.0, 100.0, 0), mmlBar(180.0, 100.0, 1)]);
		var o = out[1];
		Assert.notNull(o);
		Assert.floatEquals(100.0, o.mm0_8);
		Assert.floatEquals(140.0, o.mm4_8);
		Assert.floatEquals(180.0, o.mm8_8);
		Assert.floatEquals(10.0, o.mm1_8 - o.mm0_8);
	}

	public function testMurreyMathLinesFlatFrameCollapses() {
		var m = new MurreyMathLines(3);
		var out = IndicatorBatch.run(m, [for (i in 0...3) mmlBar(50.0, 50.0, i)]);
		var o = out[2];
		Assert.floatEquals(50.0, o.mm0_8);
		Assert.floatEquals(50.0, o.mm8_8);
	}

	public function testMurreyMathLinesLevelsAreOrdered() {
		var m = new MurreyMathLines(10);
		var bars = [for (i in 0...30) mmlBar(110.0 + Math.sin(i * 0.3) * 8.0, 90.0 + Math.cos(i * 0.3) * 8.0, i)];
		for (o in IndicatorBatch.run(m, bars)) {
			if (o == null) continue;
			Assert.isTrue(o.mm0_8 <= o.mm4_8 && o.mm4_8 <= o.mm8_8);
			Assert.isTrue(o.mm3_8 <= o.mm5_8);
		}
	}

	public function testMurreyMathLinesResetClearsState() {
		var m = new MurreyMathLines(4);
		IndicatorBatch.run(m, [for (i in 0...6) mmlBar(101.0 + i, 99.0 + i, i)]);
		Assert.isTrue(m.isReady());
		m.reset();
		Assert.isTrue(!m.isReady());
		Assert.isNull(m.update(mmlBar(101.0, 99.0, 0)));
	}

	public function testMurreyMathLinesBatchEqualsStreaming() {
		var bars = [for (i in 0...120) mmlBar(110.0 + Math.sin(i * 0.25) * 9.0, 90.0 + Math.cos(i * 0.25) * 9.0, i)];
		var a = new MurreyMathLines(64);
		var b = new MurreyMathLines(64);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].mm0_8, streamed[i].mm0_8);
				Assert.floatEquals(batched[i].mm4_8, streamed[i].mm4_8);
				Assert.floatEquals(batched[i].mm8_8, streamed[i].mm8_8);
			}
		}
	}

	// ── NewPriceLines ────────────────────────────────────────────────────────

	public function testNewPriceLinesRejectsSmallCount() {
		try {
			new NewPriceLines(1);
			Assert.fail("Should reject count < 2");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		Assert.notNull(new NewPriceLines(2));
	}

	public function testNewPriceLinesAccessorsAndMetadata() {
		var n = new NewPriceLines(8);
		Assert.equals(2, n.warmupPeriod());
		Assert.equals("NewPriceLines", n.name());
		Assert.isTrue(!n.isReady());
		Assert.equals(0, n.streak().up);
		Assert.equals(0, n.streak().down);
	}

	public function testNewPriceLinesFirstBarSeedsWithoutSignal() {
		var n = new NewPriceLines(3);
		Assert.isNull(n.update(flatBar(100.0, 0)));
		Assert.notNull(n.update(flatBar(101.0, 1)));
	}

	public function testNewPriceLinesEightHigherClosesSignalSell() {
		var n = new NewPriceLines(8);
		var bars = [for (i in 0...12) flatBar(100.0 + i, i)];
		var out = IndicatorBatch.run(n, bars);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testNewPriceLinesEightLowerClosesSignalBuy() {
		var n = new NewPriceLines(8);
		var bars = [for (i in 0...12) flatBar(200.0 - i, i)];
		var out = IndicatorBatch.run(n, bars);
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testNewPriceLinesBreakInStreakClearsSignal() {
		var n = new NewPriceLines(3);
		var out = IndicatorBatch.run(n, [flatBar(100.0, 0), flatBar(101.0, 1), flatBar(102.0, 2), flatBar(103.0, 3)]);
		Assert.floatEquals(-1.0, out[3]);
		// A lower close breaks the up streak.
		Assert.floatEquals(0.0, n.update(flatBar(102.0, 4)));
		Assert.equals(0, n.streak().up);
		Assert.equals(1, n.streak().down);
	}

	public function testNewPriceLinesUnchangedCloseResetsStreak() {
		var n = new NewPriceLines(3);
		IndicatorBatch.run(n, [flatBar(100.0, 0), flatBar(101.0, 1), flatBar(102.0, 2)]);
		Assert.floatEquals(0.0, n.update(flatBar(102.0, 3)));
		Assert.equals(0, n.streak().up);
		Assert.equals(0, n.streak().down);
	}

	public function testNewPriceLinesResetClearsState() {
		var n = new NewPriceLines(3);
		IndicatorBatch.run(n, [flatBar(100.0, 0), flatBar(101.0, 1), flatBar(102.0, 2), flatBar(103.0, 3)]);
		Assert.isTrue(n.isReady());
		n.reset();
		Assert.isTrue(!n.isReady());
		Assert.equals(0, n.streak().up);
		Assert.equals(0, n.streak().down);
		Assert.isNull(n.update(flatBar(100.0, 0)));
	}

	public function testNewPriceLinesBatchEqualsStreaming() {
		var bars = [for (i in 0...80) flatBar(100.0 + Math.sin(i * 0.25) * 9.0, i)];
		var a = new NewPriceLines(8);
		var b = new NewPriceLines(8);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Parkinson ────────────────────────────────────────────────────────────

	/** 1 / (4 ln 2), the same constant the Rust fixture references. */
	static var PARKINSON_FACTOR:Float = 0.3606737602222412;

	/** Rust helper: candle(h, l, c, ts) with open = midpoint(h, l). */
	static function pkBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar((h + l) / 2.0, h, l, c, 1.0, i);
	}

	public function testParkinsonRejectsZeroPeriod() {
		try {
			new Parkinson(0, 252);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Parkinson(20, 0);
			Assert.fail("Should reject trading_periods == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testParkinsonAccessorsAndMetadata() {
		var pv = new Parkinson(20, 252);
		Assert.equals(20, pv.warmupPeriod());
		Assert.equals("ParkinsonVolatility", pv.name());
		Assert.isTrue(!pv.isReady());
	}

	public function testParkinsonZeroRangeYieldsZero() {
		// H == L every bar -> ln(H/L) = 0 -> sigma = 0.
		var pv = new Parkinson(14, 1);
		var bars = [for (i in 0...30) pkBar(10.0, 10.0, 10.0, i)];
		for (v in IndicatorBatch.run(pv, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testParkinsonConstantRangeYieldsConstantSigma() {
		// Every bar has the same H/L ratio -> variance = factor * k.
		var pv = new Parkinson(10, 1);
		var bars = [for (i in 0...30) pkBar(11.0, 9.0, 10.0, i)];
		var out = IndicatorBatch.run(pv, bars);
		var lhl = Math.log(11.0 / 9.0);
		var expected = Math.sqrt(PARKINSON_FACTOR * lhl * lhl) * 100.0;
		for (i in 9...out.length) {
			Assert.isTrue(Math.abs(out[i] - expected) < 1e-9);
		}
	}

	public function testParkinsonAnnualisationScalesBySqrtTradingPeriods() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var half = 1.0 + Math.abs(Math.cos(i * 0.2));
			pkBar(base + half, base - half, base, i);
		}];
		var raw = IndicatorBatch.run(new Parkinson(10, 1), bars);
		var annual = IndicatorBatch.run(new Parkinson(10, 252), bars);
		var scale = Math.sqrt(252.0);
		for (i in 0...raw.length) {
			Assert.equals(raw[i] == null, annual[i] == null);
			if (raw[i] != null) Assert.isTrue(Math.abs(annual[i] - raw[i] * scale) < 1e-9);
		}
	}

	public function testParkinsonFirstEmissionAtWarmupPeriod() {
		var pv = new Parkinson(5, 1);
		var bars = [for (i in 0...20) pkBar(11.0, 9.0, 10.0, i)];
		var out = IndicatorBatch.run(pv, bars);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
	}

	public function testParkinsonResetClearsState() {
		var pv = new Parkinson(14, 252);
		IndicatorBatch.run(pv, [for (i in 0...30) pkBar(11.0, 9.0, 10.0, i)]);
		Assert.isTrue(pv.isReady());
		pv.reset();
		Assert.isTrue(!pv.isReady());
		Assert.isNull(pv.update(pkBar(11.0, 9.0, 10.0, 0)));
	}

	public function testParkinsonBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			var half = 1.0 + Math.abs(Math.cos(i * 0.15));
			pkBar(base + half, base - half, base, i);
		}];
		var a = new Parkinson(14, 252);
		var b = new Parkinson(14, 252);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Pgo ──────────────────────────────────────────────────────────────────

	/** Rust helper: candle(close, high, low, ts) with open = close. */
	static function pgoBar(c:Float, h:Float, l:Float, i:Int):Bar {
		return bar(c, h, l, c, 1.0, i);
	}

	public function testPgoRejectsZeroPeriod() {
		try {
			new Pgo(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testPgoAccessorsAndMetadata() {
		var p = new Pgo(14);
		Assert.equals(14, p.warmupPeriod());
		Assert.equals("PGO", p.name());
		Assert.isTrue(!p.isReady());
		for (i in 0...14) p.update(pgoBar(10.0, 11.0, 9.0, i));
		Assert.isTrue(p.isReady());
	}

	public function testPgoFlatCloseYieldsZeroNumerator() {
		// Constant close -> SMA == close, numerator 0 (TR-EMA non-zero).
		var p = new Pgo(5);
		var out:Null<Float> = null;
		for (i in 0...20) out = p.update(pgoBar(10.0, 11.0, 9.0, i));
		Assert.floatEquals(0.0, out);
	}

	public function testPgoWarmupEmitsFirstValueAtPeriod() {
		var p = new Pgo(3);
		for (i in 0...2) Assert.isNull(p.update(pgoBar(10.0, 11.0, 9.0, i)));
		Assert.notNull(p.update(pgoBar(10.0, 11.0, 9.0, 2)));
	}

	public function testPgoCloseAboveMeanIsPositive() {
		var p = new Pgo(5);
		for (i in 0...20) {
			var c = 10.0 + i;
			p.update(pgoBar(c, c + 0.5, c - 0.5, i));
		}
		var last = p.update(pgoBar(40.0, 40.5, 39.5, 20));
		Assert.isTrue(last > 0.0);
	}

	public function testPgoZeroTrHoldsValue() {
		// Single-point candles: TR = 0, EMA(TR) = 0 -> hold. With no previous
		// value on the first ready step, the indicator stays unset.
		var p = new Pgo(3);
		p.update(pgoBar(10.0, 10.0, 10.0, 0));
		p.update(pgoBar(10.0, 10.0, 10.0, 1));
		var v = p.update(pgoBar(10.0, 10.0, 10.0, 2));
		Assert.isNull(v);
	}

	public function testPgoResetClearsState() {
		var p = new Pgo(5);
		for (i in 0...20) p.update(pgoBar(10.0, 11.0, 9.0, i));
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.update(pgoBar(10.0, 11.0, 9.0, 0)));
	}

	public function testPgoBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var c = 100.0 + Math.sin(i * 0.3) * 8.0;
			pgoBar(c, c + 1.0, c - 1.0, i);
		}];
		var a = new Pgo(14);
		var b = new Pgo(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── PlusDi ───────────────────────────────────────────────────────────────

	/** Rust helper: c(h, l, cl) with open = close = cl. */
	static function diBar(h:Float, l:Float, cl:Float, i:Int):Bar {
		return bar(cl, h, l, cl, 1.0, i);
	}

	public function testPlusDiRejectsZeroPeriod() {
		try {
			new PlusDi(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testPlusDiAccessorsAndMetadata() {
		var di = new PlusDi(7);
		Assert.equals("PlusDi", di.name());
		// Mirrors MinusDi: first emission after period + 1 candles.
		Assert.equals(8, di.warmupPeriod());
		Assert.isTrue(!di.isReady());
	}

	public function testPlusDiUptrendDrivesPlusDiHigh() {
		// Strict uptrend: +DM dominates, so +DI is large and bounded by 100.
		var bars = [for (i in 0...12) {
			var base = 100.0 + i * 2.0;
			diBar(base + 1.0, base - 0.5, base + 0.5, i);
		}];
		var di = new PlusDi(3);
		var out = IndicatorBatch.run(di, bars);
		Assert.isNull(out[0]);
		Assert.notNull(out[3]);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.isTrue(last > 0.0 && last <= 100.0);
		Assert.isTrue(di.isReady());
	}

	public function testPlusDiFlatMarketReturnsZero() {
		// No range and no movement: smoothed true range is zero -> +DI is zero.
		var bars = [for (i in 0...6) diBar(50.0, 50.0, 50.0, i)];
		var di = new PlusDi(3);
		var out = IndicatorBatch.run(di, bars);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(0.0, last);
	}

	public function testPlusDiResetRestoresInitialState() {
		var bars = [for (i in 0...6) {
			var base = 100.0 + i * 2.0;
			diBar(base + 1.0, base - 0.5, base + 0.5, i);
		}];
		var di = new PlusDi(3);
		IndicatorBatch.run(di, bars);
		Assert.isTrue(di.isReady());
		di.reset();
		Assert.isTrue(!di.isReady());
		Assert.isNull(di.update(bars[0]));
	}

	public function testPlusDiBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 6.0;
			diBar(base + 1.0, base - 1.0, base + 0.3, i);
		}];
		var a = new PlusDi(14);
		var b = new PlusDi(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── PlusDm ───────────────────────────────────────────────────────────────

	public function testPlusDmRejectsZeroPeriod() {
		try {
			new PlusDm(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testPlusDmAccessorsAndMetadata() {
		var dm = new PlusDm(7);
		Assert.equals("PlusDm", dm.name());
		// Mirrors MinusDm: first emission after period + 1 candles.
		Assert.equals(8, dm.warmupPeriod());
		Assert.isTrue(!dm.isReady());
	}

	public function testPlusDmSeedsThenSmoothsAConstantPlusDm() {
		// High rises by 1 each bar (up = +1); low rises by 0.5 each bar, so
		// +DM equals the up-move (1.0) on every bar.
		var bars = [for (i in 0...5) diBar(11.0 + i, 9.0 + 0.5 * i, 10.0 + i, i)];
		var dm = new PlusDm(3);
		var out = IndicatorBatch.run(dm, bars);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.isNull(out[2]);
		// Seed = sum of three unit +DM values.
		Assert.floatEquals(3.0, out[3]);
		// Wilder step: 3 - 3/3 + 1 = 3.
		Assert.floatEquals(3.0, out[4]);
		Assert.isTrue(dm.isReady());
	}

	public function testPlusDmDownMovesContributeZero() {
		// Strict downtrend: highs fall, so every raw +DM is zero.
		var bars = [for (i in 0...6) diBar(20.0 - i, 5.0 - i, 12.0 - i, i)];
		var dm = new PlusDm(3);
		var out = IndicatorBatch.run(dm, bars);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(0.0, last);
	}

	public function testPlusDmResetRestoresInitialState() {
		var bars = [for (i in 0...5) diBar(11.0 + i, 9.0 + 0.5 * i, 10.0 + i, i)];
		var dm = new PlusDm(3);
		IndicatorBatch.run(dm, bars);
		Assert.isTrue(dm.isReady());
		dm.reset();
		Assert.isTrue(!dm.isReady());
		Assert.isNull(dm.update(bars[0]));
	}

	public function testPlusDmBatchEqualsStreaming() {
		var bars = [for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 6.0;
			diBar(base + 1.0, base - 1.0, base + 0.3, i);
		}];
		var a = new PlusDm(14);
		var b = new PlusDm(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── RogersSatchell ───────────────────────────────────────────────────────

	public function testRogersSatchellRejectsZeroPeriod() {
		try {
			new RogersSatchell(0, 252);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new RogersSatchell(20, 0);
			Assert.fail("Should reject trading_periods == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testRogersSatchellAccessorsAndMetadata() {
		var rs = new RogersSatchell(20, 252);
		Assert.equals(20, rs.warmupPeriod());
		Assert.equals("RogersSatchellVolatility", rs.name());
		Assert.isTrue(!rs.isReady());
	}

	public function testRogersSatchellZeroMovementYieldsZero() {
		var rs = new RogersSatchell(14, 1);
		var bars = [for (i in 0...30) bar(10.0, 10.0, 10.0, 10.0, 1.0, i)];
		for (v in IndicatorBatch.run(rs, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testRogersSatchellConstantBarShapeYieldsConstantSigma() {
		// Each bar has identical OHLC (10, 11, 9, 10.5) -> constant sample k.
		var bars = [for (i in 0...30) bar(10.0, 11.0, 9.0, 10.5, 1.0, i)];
		var logHc = Math.log(11.0 / 10.5);
		var logHo = Math.log(11.0 / 10.0);
		var logLc = Math.log(9.0 / 10.5);
		var logLo = Math.log(9.0 / 10.0);
		var k = logHc * logHo + logLc * logLo;
		var expected = Math.sqrt(Math.max(k, 0.0)) * 100.0;

		var rs = new RogersSatchell(10, 1);
		var out = IndicatorBatch.run(rs, bars);
		for (i in 9...out.length) {
			Assert.isTrue(Math.abs(out[i] - expected) < 1e-9);
		}
	}

	public function testRogersSatchellAnnualisationScalesBySqrtTradingPeriods() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var half = 1.0 + Math.abs(Math.cos(i * 0.2));
			bar(base, base + half, base - half, base + 0.3, 1.0, i);
		}];
		var raw = IndicatorBatch.run(new RogersSatchell(10, 1), bars);
		var annual = IndicatorBatch.run(new RogersSatchell(10, 252), bars);
		var scale = Math.sqrt(252.0);
		for (i in 0...raw.length) {
			Assert.equals(raw[i] == null, annual[i] == null);
			if (raw[i] != null) Assert.isTrue(Math.abs(annual[i] - raw[i] * scale) < 1e-9);
		}
	}

	public function testRogersSatchellFirstEmissionAtWarmupPeriod() {
		var rs = new RogersSatchell(5, 1);
		var bars = [for (i in 0...20) bar(10.0, 11.0, 9.0, 10.5, 1.0, i)];
		var out = IndicatorBatch.run(rs, bars);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
	}

	public function testRogersSatchellResetClearsState() {
		var rs = new RogersSatchell(14, 252);
		var bars = [for (i in 0...30) bar(10.0, 11.0, 9.0, 10.5, 1.0, i)];
		IndicatorBatch.run(rs, bars);
		Assert.isTrue(rs.isReady());
		rs.reset();
		Assert.isTrue(!rs.isReady());
		Assert.isNull(rs.update(bars[0]));
	}

	public function testRogersSatchellBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			var half = 1.0 + Math.abs(Math.cos(i * 0.15));
			bar(base, base + half, base - half, base + 0.5, 1.0, i);
		}];
		var a = new RogersSatchell(14, 252);
		var b = new RogersSatchell(14, 252);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── Rwi ──────────────────────────────────────────────────────────────────

	/** Rust helper: candle(h, l, c, ts) with open = c. */
	static function rwiBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 1.0, i);
	}

	public function testRwiRejectsBadPeriods() {
		try {
			new Rwi(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Rwi(1);
			Assert.fail("Should reject period == 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testRwiAccessorsAndMetadata() {
		var r = new Rwi(14);
		Assert.equals(14, r.warmupPeriod());
		Assert.equals("RWI", r.name());
		Assert.isTrue(!r.isReady());
		for (i in 0...30) {
			var p = 100.0 + i;
			r.update(rwiBar(p + 1.0, p - 1.0, p, i));
		}
		Assert.isTrue(r.isReady());
	}

	public function testRwiFirstEmissionAtWarmupPeriod() {
		var bars = [for (i in 0...40) {
			var p = 100.0 + Math.sin(i * 0.3) * 5.0;
			rwiBar(p + 1.0, p - 1.0, p, i);
		}];
		var r = new Rwi(5);
		var out = IndicatorBatch.run(r, bars);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
	}

	public function testRwiConstantSeriesYieldsZeroOutputs() {
		// Flat market: ATR is zero -> both lines stay 0.
		var bars = [for (i in 0...30) rwiBar(10.0, 10.0, 10.0, i)];
		var r = new Rwi(5);
		var out = IndicatorBatch.run(r, bars);
		var last = out[out.length - 1];
		Assert.floatEquals(0.0, last.high);
		Assert.floatEquals(0.0, last.low);
	}

	public function testRwiPureUptrendHighDominatesLow() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i * 2.0;
			rwiBar(base + 1.0, base - 0.5, base + 0.5, i);
		}];
		var r = new Rwi(14);
		var out = IndicatorBatch.run(r, bars);
		var last = out[out.length - 1];
		Assert.isTrue(last.high > last.low);
		Assert.isTrue(last.high > 1.0);
	}

	public function testRwiPureDowntrendLowDominatesHigh() {
		var bars:Array<Bar> = [];
		var idx = 0;
		var i = 39;
		while (i >= 0) {
			var base = 100.0 + i * 2.0;
			bars.push(rwiBar(base + 0.5, base - 1.0, base - 0.5, idx));
			idx++;
			i--;
		}
		var r = new Rwi(14);
		var out = IndicatorBatch.run(r, bars);
		var last = out[out.length - 1];
		Assert.isTrue(last.low > last.high);
		Assert.isTrue(last.low > 1.0);
	}

	public function testRwiOutputsNonNegative() {
		var bars = [for (i in 0...120) {
			var p = 100.0 + Math.sin(i * 0.25) * 6.0;
			rwiBar(p + 1.5, p - 1.5, p, i);
		}];
		var r = new Rwi(10);
		for (v in IndicatorBatch.run(r, bars)) {
			if (v == null) continue;
			Assert.isTrue(v.high >= 0.0 && v.low >= 0.0);
			Assert.isTrue(Math.isFinite(v.high) && Math.isFinite(v.low));
		}
	}

	public function testRwiResetClearsState() {
		var bars = [for (i in 0...30) rwiBar(11.0, 9.0, 10.0, i)];
		var r = new Rwi(5);
		IndicatorBatch.run(r, bars);
		Assert.isTrue(r.isReady());
		r.reset();
		Assert.isTrue(!r.isReady());
		Assert.isNull(r.update(bars[0]));
	}

	public function testRwiBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var p = 100.0 + Math.sin(i * 0.3) * 5.0;
			rwiBar(p + 1.0, p - 1.0, p, i);
		}];
		var a = new Rwi(7);
		var b = new Rwi(7);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].high, streamed[i].high);
				Assert.floatEquals(batched[i].low, streamed[i].low);
			}
		}
	}

	// ── Vortex ───────────────────────────────────────────────────────────────

	public function testVortexRejectsZeroPeriod() {
		try {
			new Vortex(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testVortexAccessorsAndMetadata() {
		var v = new Vortex(14);
		Assert.equals("Vortex", v.name());
		Assert.equals(15, v.warmupPeriod());
		Assert.isTrue(!v.isReady());
	}

	public function testVortexReferenceValues() {
		// Vortex(2) over three candles (o, h, l, c):
		//   c1 = (9, 10, 8, 9), c2 = (10, 12, 9, 11), c3 = (12, 13, 11, 12).
		// bar 2: VM+ = |12-8| = 4, VM- = |9-10| = 1, TR = 3.
		// bar 3: VM+ = |13-9| = 4, VM- = |11-12| = 1, TR = 2.
		// window sums: VM+ = 8, VM- = 2, TR = 5 -> VI+ = 1.6, VI- = 0.4.
		var bars = [
			bar(9.0, 10.0, 8.0, 9.0, 1.0, 0),
			bar(10.0, 12.0, 9.0, 11.0, 1.0, 1),
			bar(12.0, 13.0, 11.0, 12.0, 1.0, 2),
		];
		var v = new Vortex(2);
		var out = IndicatorBatch.run(v, bars);
		Assert.equals(3, v.warmupPeriod());
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		var o = out[2];
		Assert.floatEquals(1.6, o.vi_plus);
		Assert.floatEquals(0.4, o.vi_minus);
	}

	public function testVortexPerfectlyFlatMarketYieldsZero() {
		var v = new Vortex(5);
		var bars = [for (i in 0...20) bar(10.0, 10.0, 10.0, 10.0, 1.0, i)];
		for (o in IndicatorBatch.run(v, bars)) {
			if (o == null) continue;
			Assert.floatEquals(0.0, o.vi_plus);
			Assert.floatEquals(0.0, o.vi_minus);
		}
	}

	public function testVortexOutputsAreNonNegative() {
		var v = new Vortex(14);
		var bars = [for (i in 0...120) {
			var mid = 100.0 + Math.sin(i * 0.3) * 10.0;
			bar(mid, mid + 3.0, mid - 3.0, mid + 1.0, 1.0, i);
		}];
		for (o in IndicatorBatch.run(v, bars)) {
			if (o == null) continue;
			Assert.isTrue(o.vi_plus >= 0.0 && o.vi_minus >= 0.0);
		}
	}

	public function testVortexResetClearsState() {
		var v = new Vortex(5);
		var bars = [for (i in 0...20) bar(100.0, 102.0, 98.0, 101.0, 1.0, i)];
		IndicatorBatch.run(v, bars);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(bars[0]));
	}

	public function testVortexBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var mid = 100.0 + Math.sin(i * 0.35) * 9.0;
			bar(mid, mid + 2.5, mid - 2.5, mid + 0.5, 1.0, i);
		}];
		var a = new Vortex(14);
		var b = new Vortex(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].vi_plus, streamed[i].vi_plus);
				Assert.floatEquals(batched[i].vi_minus, streamed[i].vi_minus);
			}
		}
	}

	// ── VolatilityCone ───────────────────────────────────────────────────────

	public function testVolatilityConeRejectsBadWindows() {
		try {
			new VolatilityCone(0, 10);
			Assert.fail("Should reject window == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new VolatilityCone(10, 0);
			Assert.fail("Should reject lookback == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new VolatilityCone(1, 10);
			Assert.fail("Should reject window == 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new VolatilityCone(10, 1);
			Assert.fail("Should reject lookback == 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testVolatilityConeAccessorsAndMetadata() {
		var vc = new VolatilityCone(20, 60);
		Assert.equals(80, vc.warmupPeriod());
		Assert.equals("VolatilityCone", vc.name());
		Assert.isTrue(!vc.isReady());
	}

	public function testVolatilityConeFirstEmissionAtWarmupPeriod() {
		var vc = new VolatilityCone(2, 2);
		Assert.equals(4, vc.warmupPeriod());
		var prices = [100.0, 110.0, 121.0, 100.0, 105.0, 99.0];
		var out = IndicatorBatch.run(vc, [for (i in 0...prices.length) flatBar(prices[i], i)]);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testVolatilityConeKnownValue() {
		// window = 2 -> vol = |r_t − r_{t−1}| / √2; lookback = 2.
		var vc = new VolatilityCone(2, 2);
		var prices = [100.0, 110.0, 121.0, 100.0];
		var out = IndicatorBatch.run(vc, [for (i in 0...prices.length) flatBar(prices[i], i)]);
		var r2 = Math.log(121.0 / 110.0);
		var r3 = Math.log(100.0 / 121.0);
		var vol2 = Math.abs(r2 - r3) / Math.sqrt(2.0);
		var o = out[3];
		Assert.isTrue(Math.abs(o.current - vol2) < 1e-9);
		Assert.isTrue(Math.abs(o.min - 0.0) < 1e-9); // vol1 = 0 (r1 == r2)
		Assert.isTrue(Math.abs(o.max - vol2) < 1e-9);
		Assert.isTrue(Math.abs(o.median - vol2 / 2.0) < 1e-9);
		Assert.floatEquals(100.0, o.percentile);
	}

	public function testVolatilityConeEnvelopeBracketsCurrent() {
		var vc = new VolatilityCone(10, 30);
		var bars = [for (i in 0...200) flatBar(100.0 + Math.sin(i * 0.3) * 12.0, i)];
		for (o in IndicatorBatch.run(vc, bars)) {
			if (o == null) continue;
			Assert.isTrue(o.min <= o.current && o.current <= o.max);
			Assert.isTrue(o.min <= o.median && o.median <= o.max);
			Assert.isTrue(o.percentile > 0.0 && o.percentile <= 100.0);
		}
	}

	public function testVolatilityConeConstantSeriesYieldsZeroCone() {
		var vc = new VolatilityCone(5, 5);
		var bars = [for (i in 0...40) flatBar(100.0, i)];
		for (o in IndicatorBatch.run(vc, bars)) {
			if (o == null) continue;
			Assert.floatEquals(0.0, o.current);
			Assert.floatEquals(0.0, o.min);
			Assert.floatEquals(0.0, o.max);
			Assert.floatEquals(0.0, o.median);
			Assert.floatEquals(100.0, o.percentile);
		}
	}

	public function testVolatilityConeSkipsNonPositiveClose() {
		var vc = new VolatilityCone(2, 2);
		var prices = [100.0, 110.0, 121.0, 100.0];
		var out = IndicatorBatch.run(vc, [for (i in 0...prices.length) flatBar(prices[i], i)]);
		var baseline = out[out.length - 1];
		Assert.notNull(baseline);
		// A non-positive close is skipped and the previous value is returned.
		var skipped = vc.update(flatBar(0.0, 4));
		Assert.floatEquals(baseline.current, skipped.current);
		Assert.floatEquals(baseline.percentile, skipped.percentile);
		// State untouched: a control instance replaying the same real ticks agrees.
		var control = new VolatilityCone(2, 2);
		IndicatorBatch.run(control, [for (i in 0...prices.length) flatBar(prices[i], i)]);
		var after = vc.update(flatBar(105.0, 5));
		var controlAfter = control.update(flatBar(105.0, 5));
		Assert.floatEquals(controlAfter.current, after.current);
		Assert.floatEquals(controlAfter.median, after.median);
	}

	public function testVolatilityConeSkipsNonPositiveBeforeFirstClose() {
		var vc = new VolatilityCone(2, 2);
		Assert.isNull(vc.update(flatBar(0.0, 0)));
		Assert.isNull(vc.update(flatBar(100.0, 1)));
	}

	public function testVolatilityConeResetClearsState() {
		var vc = new VolatilityCone(2, 2);
		var prices = [100.0, 110.0, 121.0, 100.0, 105.0];
		IndicatorBatch.run(vc, [for (i in 0...prices.length) flatBar(prices[i], i)]);
		Assert.isTrue(vc.isReady());
		vc.reset();
		Assert.isTrue(!vc.isReady());
		Assert.isNull(vc.update(flatBar(100.0, 0)));
	}

	public function testVolatilityConeBatchEqualsStreaming() {
		var bars = [for (i in 0...200) flatBar(100.0 + Math.sin(i * 0.25) * 9.0, i)];
		var a = new VolatilityCone(10, 30);
		var b = new VolatilityCone(10, 30);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].current, streamed[i].current);
				Assert.floatEquals(batched[i].min, streamed[i].min);
				Assert.floatEquals(batched[i].median, streamed[i].median);
				Assert.floatEquals(batched[i].max, streamed[i].max);
				Assert.floatEquals(batched[i].percentile, streamed[i].percentile);
			}
		}
	}

	// ── VolatilityRatio ──────────────────────────────────────────────────────

	/** Rust helper: candle(high, low, close) with open = low. */
	static function vrBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(l, h, l, c, 1000.0, i);
	}

	public function testVolatilityRatioRejectsZeroPeriod() {
		try {
			new VolatilityRatio(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testVolatilityRatioAccessorsAndMetadata() {
		var vr = new VolatilityRatio(14);
		Assert.equals(16, vr.warmupPeriod());
		Assert.equals("VolatilityRatio", vr.name());
		Assert.isTrue(!vr.isReady());
	}

	public function testVolatilityRatioFirstEmissionAtWarmupPeriod() {
		var vr = new VolatilityRatio(3);
		Assert.equals(5, vr.warmupPeriod());
		var bars = [for (i in 0...10) {
			var base = 100.0 + i;
			vrBar(base + 1.0, base - 1.0, base, i);
		}];
		var out = IndicatorBatch.run(vr, bars);
		for (i in 0...4) Assert.isNull(out[i]);
		Assert.notNull(out[4]);
	}

	public function testVolatilityRatioWideRangingDayExceedsTwo() {
		// Steady TR of 2.0 seeds the EMA, then one far wider bar.
		var vr = new VolatilityRatio(3);
		var bars = [for (i in 0...6) {
			var base = 100.0 + i;
			vrBar(base + 1.0, base - 1.0, base, i);
		}];
		bars.push(vrBar(110.0, 100.0, 105.0, 6));
		var out = IndicatorBatch.run(vr, bars);
		var last = out[out.length - 1];
		Assert.isTrue(last > 2.0);
	}

	public function testVolatilityRatioSteadyRangeRatioIsOne() {
		// Constant true range -> EMA equals it -> ratio exactly 1.0.
		var vr = new VolatilityRatio(3);
		var bars = [for (i in 0...12) {
			var base = 100.0 + i;
			vrBar(base + 1.0, base - 1.0, base, i);
		}];
		var out = IndicatorBatch.run(vr, bars);
		Assert.isTrue(Math.abs(out[out.length - 1] - 1.0) < 1e-9);
	}

	public function testVolatilityRatioFlatMarketYieldsZero() {
		var vr = new VolatilityRatio(3);
		var bars = [for (i in 0...10) vrBar(100.0, 100.0, 100.0, i)];
		for (v in IndicatorBatch.run(vr, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testVolatilityRatioOutputIsNonNegative() {
		var vr = new VolatilityRatio(14);
		var bars = [for (i in 0...200) {
			var base = 100.0 + Math.sin(i * 0.3) * 12.0;
			vrBar(base + 2.0, base - 2.0, base + 0.5, i);
		}];
		for (v in IndicatorBatch.run(vr, bars)) {
			if (v != null) Assert.isTrue(v >= 0.0);
		}
	}

	public function testVolatilityRatioResetClearsState() {
		var vr = new VolatilityRatio(3);
		var bars = [for (i in 0...10) {
			var base = 100.0 + i;
			vrBar(base + 1.0, base - 1.0, base, i);
		}];
		IndicatorBatch.run(vr, bars);
		Assert.isTrue(vr.isReady());
		vr.reset();
		Assert.isTrue(!vr.isReady());
		Assert.isNull(vr.update(vrBar(101.0, 99.0, 100.0, 0)));
	}

	public function testVolatilityRatioBatchEqualsStreaming() {
		var bars = [for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.25) * 9.0;
			vrBar(base + 2.0, base - 1.5, base + 0.5, i);
		}];
		var a = new VolatilityRatio(14);
		var b = new VolatilityRatio(14);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── WaveTrend ────────────────────────────────────────────────────────────

	/** Rust helper: candle(h, l, c, ts) with open = c. */
	static function wtBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 1.0, i);
	}

	public function testWaveTrendRejectsZeroPeriod() {
		try {
			new WaveTrend(0, 21, 4);
			Assert.fail("Should reject channel == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new WaveTrend(10, 0, 4);
			Assert.fail("Should reject average == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new WaveTrend(10, 21, 0);
			Assert.fail("Should reject signal == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testWaveTrendAccessorsAndMetadata() {
		var w = WaveTrend.classic();
		Assert.equals("WaveTrend", w.name());
		// 2 * 10 + 21 + 4 - 3 = 42.
		Assert.equals(42, w.warmupPeriod());
		Assert.isTrue(!w.isReady());
		for (i in 0...80) {
			var p = 100.0 + Math.sin(i * 0.3) * 5.0;
			w.update(wtBar(p + 1.0, p - 1.0, p, i));
		}
		Assert.isTrue(w.isReady());
	}

	public function testWaveTrendFirstEmissionAtWarmupPeriod() {
		var bars = [for (i in 0...60) {
			var p = 100.0 + Math.sin(i * 0.25) * 6.0;
			wtBar(p + 1.0, p - 1.0, p, i);
		}];
		var w = new WaveTrend(5, 8, 3);
		var warmup = 2 * 5 + 8 + 3 - 3; // 18
		Assert.equals(warmup, w.warmupPeriod());
		var out = IndicatorBatch.run(w, bars);
		for (i in 0...(warmup - 1)) Assert.isNull(out[i]);
		Assert.notNull(out[warmup - 1]);
	}

	public function testWaveTrendConstantSeriesYieldsZeroLines() {
		var bars = [for (i in 0...80) wtBar(10.0, 10.0, 10.0, i)];
		var w = new WaveTrend(5, 8, 3);
		var out = IndicatorBatch.run(w, bars);
		var last = out[out.length - 1];
		Assert.floatEquals(0.0, last.wt1);
		Assert.floatEquals(0.0, last.wt2);
	}

	public function testWaveTrendPureUptrendIsPositive() {
		var bars = [for (i in 0...120) {
			var base = 100.0 + i * 0.5;
			wtBar(base + 1.0, base - 0.5, base + 0.5, i);
		}];
		var w = WaveTrend.classic();
		var out = IndicatorBatch.run(w, bars);
		var last = out[out.length - 1];
		Assert.isTrue(last.wt1 > 0.0);
		Assert.isTrue(last.wt2 > 0.0);
	}

	public function testWaveTrendPureDowntrendIsNegative() {
		var bars = [for (i in 0...120) {
			var base = 200.0 - i * 0.5;
			wtBar(base + 1.0, base - 0.5, base - 0.5, i);
		}];
		var w = WaveTrend.classic();
		var out = IndicatorBatch.run(w, bars);
		var last = out[out.length - 1];
		Assert.isTrue(last.wt1 < 0.0);
		Assert.isTrue(last.wt2 < 0.0);
	}

	public function testWaveTrendOutputsRemainFinite() {
		var bars = [for (i in 0...200) {
			var p = 100.0 + Math.sin(i * 0.3) * 8.0;
			wtBar(p + 2.0, p - 2.0, p, i);
		}];
		var w = WaveTrend.classic();
		for (v in IndicatorBatch.run(w, bars)) {
			if (v == null) continue;
			Assert.isTrue(Math.isFinite(v.wt1) && Math.isFinite(v.wt2));
		}
	}

	public function testWaveTrendResetClearsState() {
		var bars = [for (i in 0...80) wtBar(11.0, 9.0, 10.0, i)];
		var w = WaveTrend.classic();
		IndicatorBatch.run(w, bars);
		Assert.isTrue(w.isReady());
		w.reset();
		Assert.isTrue(!w.isReady());
		Assert.isNull(w.update(bars[0]));
	}

	public function testWaveTrendBatchEqualsStreaming() {
		var bars = [for (i in 0...120) {
			var p = 100.0 + Math.sin(i * 0.27) * 6.0;
			wtBar(p + 1.5, p - 1.5, p, i);
		}];
		var a = WaveTrend.classic();
		var b = WaveTrend.classic();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].wt1, streamed[i].wt1);
				Assert.floatEquals(batched[i].wt2, streamed[i].wt2);
			}
		}
	}

	// ── WoodiePivots ─────────────────────────────────────────────────────────

	/** Rust helper: c(h, l, close, ts) with open = close. */
	static function wpBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 1.0, i);
	}

	public function testWoodiePivotsFormulaReferenceValues() {
		// H=110, L=90, C=108 -> PP = (110+90+216)/4 = 104.
		var p = new WoodiePivots();
		var levels = p.update(wpBar(110.0, 90.0, 108.0, 0));
		Assert.notNull(levels);
		Assert.floatEquals(104.0, levels.pivot);
		Assert.floatEquals(2.0 * 104.0 - 90.0, levels.r1);
		Assert.floatEquals(2.0 * 104.0 - 110.0, levels.s1);
		Assert.floatEquals(104.0 + 20.0, levels.r2);
		Assert.floatEquals(104.0 - 20.0, levels.s2);
	}

	public function testWoodiePivotsPpDiffersFromClassicWhenCloseIsSkewed() {
		var levels = new WoodiePivots().update(wpBar(120.0, 80.0, 110.0, 0));
		var classicPp = (120.0 + 80.0 + 110.0) / 3.0;
		Assert.isTrue(Math.abs(levels.pivot - classicPp) > 1e-6);
		// Equal when close = midpoint.
		var mid = new WoodiePivots().update(wpBar(120.0, 80.0, 100.0, 0));
		var classicMid = (120.0 + 80.0 + 100.0) / 3.0;
		Assert.isTrue(Math.abs(mid.pivot - classicMid) < 1e-9);
	}

	public function testWoodiePivotsOrderingResistanceAbovePivotAboveSupport() {
		var levels = new WoodiePivots().update(wpBar(120.0, 80.0, 110.0, 0));
		Assert.isTrue(levels.r2 >= levels.r1);
		Assert.isTrue(levels.r1 >= levels.pivot);
		Assert.isTrue(levels.pivot >= levels.s1);
		Assert.isTrue(levels.s1 >= levels.s2);
	}

	public function testWoodiePivotsConstantSeriesCollapsesLevels() {
		var levels = new WoodiePivots().update(wpBar(50.0, 50.0, 50.0, 0));
		Assert.floatEquals(50.0, levels.pivot);
		Assert.floatEquals(50.0, levels.r2);
		Assert.floatEquals(50.0, levels.s2);
	}

	public function testWoodiePivotsWarmupAndReady() {
		var p = new WoodiePivots();
		Assert.isTrue(!p.isReady());
		Assert.equals(1, p.warmupPeriod());
		Assert.equals("WoodiePivots", p.name());
		p.update(wpBar(11.0, 9.0, 10.0, 0));
		Assert.isTrue(p.isReady());
	}

	public function testWoodiePivotsResetClearsState() {
		var p = new WoodiePivots();
		p.update(wpBar(11.0, 9.0, 10.0, 0));
		p.reset();
		Assert.isTrue(!p.isReady());
	}

	public function testWoodiePivotsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) wpBar(i + 2.0, i + 0.0, i + 1.0, i)];
		var a = new WoodiePivots();
		var b = new WoodiePivots();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			Assert.floatEquals(batched[i].pivot, streamed[i].pivot);
			Assert.floatEquals(batched[i].r1, streamed[i].r1);
			Assert.floatEquals(batched[i].r2, streamed[i].r2);
			Assert.floatEquals(batched[i].s1, streamed[i].s1);
			Assert.floatEquals(batched[i].s2, streamed[i].s2);
		}
	}

	// ── YangZhang ────────────────────────────────────────────────────────────

	public function testYangZhangRejectsBadPeriods() {
		try {
			new YangZhang(0, 252);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new YangZhang(20, 0);
			Assert.fail("Should reject trading_periods == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new YangZhang(1, 252);
			Assert.fail("Should reject period == 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testYangZhangAccessorsAndMetadata() {
		var yz = new YangZhang(20, 252);
		Assert.equals(21, yz.warmupPeriod());
		Assert.equals("YangZhangVolatility", yz.name());
		Assert.isTrue(!yz.isReady());
		// k = 0.34 / (1.34 + 21/19) ≈ 0.139
		var n = 20.0;
		var expectedK = 0.34 / (1.34 + (n + 1.0) / (n - 1.0));
		Assert.floatEquals(expectedK, yz.blendingFactor());
	}

	public function testYangZhangZeroMovementYieldsZero() {
		var yz = new YangZhang(14, 1);
		var bars = [for (i in 0...30) bar(10.0, 10.0, 10.0, 10.0, 1.0, i)];
		for (v in IndicatorBatch.run(yz, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testYangZhangOutputIsNonNegative() {
		var yz = new YangZhang(14, 252);
		var bars = [for (i in 0...200) {
			var base = 100.0 + Math.sin(i * 0.3) * 12.0;
			var half = 0.5 + Math.abs(Math.cos(i * 0.13)) * 1.5;
			bar(base - 0.1, base + half, base - half, base + 0.2, 1.0, i);
		}];
		for (v in IndicatorBatch.run(yz, bars)) {
			if (v != null) Assert.isTrue(v >= 0.0);
		}
	}

	public function testYangZhangAnnualisationScalesBySqrtTradingPeriods() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			var half = 1.0 + Math.abs(Math.cos(i * 0.2));
			bar(base - 0.05, base + half, base - half, base + 0.3, 1.0, i);
		}];
		var raw = IndicatorBatch.run(new YangZhang(10, 1), bars);
		var annual = IndicatorBatch.run(new YangZhang(10, 252), bars);
		var scale = Math.sqrt(252.0);
		for (i in 0...raw.length) {
			Assert.equals(raw[i] == null, annual[i] == null);
			if (raw[i] != null) Assert.isTrue(Math.abs(annual[i] - raw[i] * scale) < 1e-9);
		}
	}

	public function testYangZhangFirstEmissionAtWarmupPeriod() {
		// period = 5 -> first ready at index 5 (the 6th candle).
		var bars = [for (i in 0...20) {
			var base = 100.0 + Math.sin(i * 0.4) * 3.0;
			bar(base, base + 1.0, base - 1.0, base + 0.2, 1.0, i);
		}];
		var yz = new YangZhang(5, 1);
		Assert.equals(6, yz.warmupPeriod());
		var out = IndicatorBatch.run(yz, bars);
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.notNull(out[5]);
	}

	public function testYangZhangIntradayDataCollapsesToRsOnly() {
		// O = 10, H = 11, L = 9, C = 10 every bar: overnight and open-to-close
		// variances are zero, so YZ reduces to (1 − k) · rs_sample.
		var bars = [for (i in 0...30) bar(10.0, 11.0, 9.0, 10.0, 1.0, i)];
		var yz = new YangZhang(10, 1);
		var out = IndicatorBatch.run(yz, bars);

		var logHc = Math.log(11.0 / 10.0);
		var logHo = Math.log(11.0 / 10.0);
		var logLc = Math.log(9.0 / 10.0);
		var logLo = Math.log(9.0 / 10.0);
		var rsSample = logHc * logHo + logLc * logLo;
		var n = 10.0;
		var k = 0.34 / (1.34 + (n + 1.0) / (n - 1.0));
		var expected = Math.sqrt(Math.max((1.0 - k) * rsSample, 0.0)) * 100.0;

		for (i in 11...out.length) {
			Assert.isTrue(Math.abs(out[i] - expected) < 1e-9);
		}
	}

	public function testYangZhangResetClearsState() {
		var yz = new YangZhang(14, 252);
		var bars = [for (i in 0...30) bar(10.0, 11.0, 9.0, 10.5, 1.0, i)];
		IndicatorBatch.run(yz, bars);
		Assert.isTrue(yz.isReady());
		yz.reset();
		Assert.isTrue(!yz.isReady());
		Assert.isNull(yz.update(bars[0]));
	}

	public function testYangZhangBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.25) * 6.0;
			var half = 1.0 + Math.abs(Math.cos(i * 0.15));
			bar(base - 0.05, base + half, base - half, base + 0.5, 1.0, i);
		}];
		var a = new YangZhang(14, 252);
		var b = new YangZhang(14, 252);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── TtmSqueeze ───────────────────────────────────────────────────────────

	public function testTtmSqueezeRejectsInvalidPeriod() {
		try {
			new TtmSqueeze(0, 2.0, 1.5);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TtmSqueeze(1, 2.0, 1.5);
			Assert.fail("Should reject period == 1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTtmSqueezeRejectsNonPositiveMultipliers() {
		try {
			new TtmSqueeze(20, 0.0, 1.5);
			Assert.fail("Should reject bb_mult == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TtmSqueeze(20, 2.0, -1.0);
			Assert.fail("Should reject kc_mult < 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TtmSqueeze(20, Math.NaN, 1.5);
			Assert.fail("Should reject NaN bb_mult");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTtmSqueezeAccessorsAndMetadata() {
		var s = TtmSqueeze.classic();
		Assert.equals(20, s.warmupPeriod());
		Assert.equals("TtmSqueeze", s.name());
		Assert.isTrue(!s.isReady());
	}

	public function testTtmSqueezeFlatMarketHasZeroMomentum() {
		var bars = [for (i in 0...30) diBar(10.0, 10.0, 10.0, i)];
		var s = new TtmSqueeze(20, 2.0, 1.5);
		var out = IndicatorBatch.run(s, bars);
		var last = out[out.length - 1];
		Assert.isTrue(Math.abs(last.momentum) < 1e-9);
		// With zero volatility both BB and KC collapse: squeeze trivially "on".
		Assert.floatEquals(1.0, last.squeeze);
	}

	public function testTtmSqueezeWarmupReturnsNone() {
		var s = new TtmSqueeze(20, 2.0, 1.5);
		for (i in 0...19) {
			var base = 100.0 + i;
			Assert.isNull(s.update(diBar(base + 1.0, base - 1.0, base, i)));
		}
		Assert.notNull(s.update(diBar(121.0, 119.0, 120.0, 19)));
	}

	public function testTtmSqueezeSqueezeIsBinary() {
		var bars = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.4) * 2.0;
			diBar(m + 1.0, m - 1.0, m, i);
		}];
		var s = new TtmSqueeze(20, 2.0, 1.5);
		for (o in IndicatorBatch.run(s, bars)) {
			if (o == null) continue;
			Assert.isTrue(o.squeeze == 0.0 || o.squeeze == 1.0);
		}
	}

	public function testTtmSqueezeResetClearsState() {
		var bars = [for (i in 0...30) diBar(i + 1.0, i - 1.0, i + 0.0, i)];
		var s = TtmSqueeze.classic();
		IndicatorBatch.run(s, bars);
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
		Assert.isNull(s.update(bars[0]));
	}

	public function testTtmSqueezeBatchEqualsStreaming() {
		var bars = [for (i in 0...40) diBar(i + 2.0, i + 0.0, i + 1.0, i)];
		var a = new TtmSqueeze(20, 2.0, 1.5);
		var b = new TtmSqueeze(20, 2.0, 1.5);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].squeeze, streamed[i].squeeze);
				Assert.floatEquals(batched[i].momentum, streamed[i].momentum);
			}
		}
	}

	// ── TtmTrend ─────────────────────────────────────────────────────────────

	/** Rust helper: candle(high, low, close, ts) with open = midpoint(h, l). */
	static function ttBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar((h + l) / 2.0, h, l, c, 1.0, i);
	}

	public function testTtmTrendRejectsZeroPeriod() {
		try {
			new TtmTrend(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTtmTrendAccessorsAndMetadata() {
		var t = new TtmTrend(6);
		Assert.equals(6, t.warmupPeriod());
		Assert.equals("TtmTrend", t.name());
		Assert.isTrue(!t.isReady());
	}

	public function testTtmTrendWarmupThenEmits() {
		var t = new TtmTrend(3);
		var out = IndicatorBatch.run(t, [for (i in 0...3) ttBar(13.0, 9.0, 12.0, i)]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.notNull(out[2]);
	}

	public function testTtmTrendCloseAboveReferenceIsUptrend() {
		// Close (12) sits above the median reference (13 + 9) / 2 = 11 -> +1.
		var t = new TtmTrend(3);
		var out = IndicatorBatch.run(t, [for (i in 0...6) ttBar(13.0, 9.0, 12.0, i)]);
		Assert.floatEquals(1.0, out[out.length - 1]);
	}

	public function testTtmTrendCloseAtOrBelowReferenceIsDowntrend() {
		// Constant median 10, close equal to reference -> not strictly above -> -1.
		var t = new TtmTrend(3);
		var out = IndicatorBatch.run(t, [for (i in 0...6) ttBar(11.0, 9.0, 10.0, i)]);
		Assert.floatEquals(-1.0, out[out.length - 1]);
	}

	public function testTtmTrendResetClearsState() {
		var t = new TtmTrend(3);
		IndicatorBatch.run(t, [for (i in 0...6) ttBar(13.0, 9.0, 12.0, i)]);
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
	}

	public function testTtmTrendBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.25) * 4.0;
			ttBar(base + 1.0, base - 1.0, base + Math.cos(i * 0.5), i);
		}];
		var a = new TtmTrend(6);
		var b = new TtmTrend(6);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── UltimateOscillator ───────────────────────────────────────────────────

	public function testUltimateOscillatorRejectsZeroPeriod() {
		try {
			new UltimateOscillator(0, 14, 28);
			Assert.fail("Should reject short == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new UltimateOscillator(7, 0, 28);
			Assert.fail("Should reject mid == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new UltimateOscillator(7, 14, 0);
			Assert.fail("Should reject long == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testUltimateOscillatorAccessorsAndMetadata() {
		var uo = new UltimateOscillator(7, 14, 28);
		Assert.equals("UltimateOscillator", uo.name());
		Assert.equals(29, uo.warmupPeriod());
		Assert.isTrue(!uo.isReady());
		for (i in 0...29) {
			var p = 100.0 + Math.sin(i * 0.3) * 5.0;
			uo.update(bar(p, p + 1.0, p - 1.0, p, 1.0, i));
		}
		Assert.isTrue(uo.isReady());
	}

	public function testUltimateOscillatorFirstEmissionAtWarmupPeriod() {
		var uo = new UltimateOscillator(2, 3, 5);
		Assert.equals(6, uo.warmupPeriod());
		var bars = [for (i in 0...20) flatBar(100.0 + i, i)];
		var out = IndicatorBatch.run(uo, bars);
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.notNull(out[5]);
	}

	public function testUltimateOscillatorPureUptrendSaturatesAt100() {
		// Each flat candle closes higher: BP == TR every bar -> UO is 100.
		var uo = new UltimateOscillator(2, 3, 5);
		var bars = [for (i in 0...30) flatBar(100.0 + i, i)];
		for (v in IndicatorBatch.run(uo, bars)) {
			if (v != null) Assert.isTrue(Math.abs(v - 100.0) < 1e-9);
		}
	}

	public function testUltimateOscillatorPureDowntrendSaturatesAt0() {
		// Each flat candle closes lower: BP is 0 every bar -> UO is 0.
		var uo = new UltimateOscillator(2, 3, 5);
		var bars = [for (i in 0...30) flatBar(100.0 - i, i)];
		for (v in IndicatorBatch.run(uo, bars)) {
			if (v != null) Assert.isTrue(Math.abs(v) < 1e-9);
		}
	}

	public function testUltimateOscillatorFlatMarketReads50() {
		// Every bar identical: zero true range everywhere -> neutral 50.
		var uo = new UltimateOscillator(2, 3, 5);
		var bars = [for (i in 0...30) flatBar(100.0, i)];
		for (v in IndicatorBatch.run(uo, bars)) {
			if (v != null) Assert.isTrue(Math.abs(v - 50.0) < 1e-9);
		}
	}

	public function testUltimateOscillatorOutputStaysWithin0To100() {
		var uo = UltimateOscillator.classic();
		var bars = [for (i in 0...200) {
			var mid = 100.0 + Math.sin(i * 0.2) * 12.0;
			bar(mid, mid + 3.0, mid - 3.0, mid + 1.0, 10.0, i);
		}];
		for (v in IndicatorBatch.run(uo, bars)) {
			if (v != null) Assert.isTrue(v >= 0.0 && v <= 100.0);
		}
	}

	public function testUltimateOscillatorResetClearsState() {
		var uo = new UltimateOscillator(2, 3, 5);
		var bars = [for (i in 0...20) flatBar(100.0 + i, i)];
		IndicatorBatch.run(uo, bars);
		Assert.isTrue(uo.isReady());
		uo.reset();
		Assert.isTrue(!uo.isReady());
		Assert.isNull(uo.update(bars[0]));
	}

	public function testUltimateOscillatorBatchEqualsStreaming() {
		var bars = [for (i in 0...120) {
			var mid = 100.0 + Math.sin(i * 0.3) * 10.0;
			bar(mid, mid + 2.0, mid - 2.0, mid + 0.5, 10.0, i);
		}];
		var a = UltimateOscillator.classic();
		var b = UltimateOscillator.classic();
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}

	// ── VerticalHorizontalFilter ─────────────────────────────────────────────

	public function testVhfRejectsZeroPeriod() {
		try {
			new VerticalHorizontalFilter(0);
			Assert.fail("Should reject period == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testVhfAccessorsAndMetadata() {
		var vhf = new VerticalHorizontalFilter(28);
		Assert.equals(29, vhf.warmupPeriod());
		Assert.equals("VerticalHorizontalFilter", vhf.name());
		Assert.isTrue(!vhf.isReady());
	}

	public function testVhfReferenceValuesPureUptrend() {
		// Closes 1,2,…: every diff is 1 (Σ = period), the n-close span is
		// period − 1, so VHF = (period − 1) / period. For period 5: 4/5 = 0.8.
		var vhf = new VerticalHorizontalFilter(5);
		var out = IndicatorBatch.run(vhf, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.floatEquals(0.8, out[5]);
		Assert.equals(6, vhf.warmupPeriod());
	}

	public function testVhfChoppySeriesReadsLow() {
		var prices = [for (i in 0...40) i % 2 == 0 ? 10.0 : 11.0];
		var vhf = new VerticalHorizontalFilter(10);
		for (v in IndicatorBatch.run(vhf, prices)) {
			if (v != null) Assert.isTrue(v < 0.2);
		}
	}

	public function testVhfFlatSeriesYieldsZero() {
		var vhf = new VerticalHorizontalFilter(8);
		var prices = [for (_ in 0...20) 50.0];
		for (v in IndicatorBatch.run(vhf, prices)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testVhfStaysWithinUnitRange() {
		var prices = [for (i in 0...120) 50.0 + Math.sin(i * 0.3) * 10.0];
		var vhf = new VerticalHorizontalFilter(28);
		for (v in IndicatorBatch.run(vhf, prices)) {
			if (v != null) Assert.isTrue(v >= 0.0 && v <= 1.0);
		}
	}

	public function testVhfNonFiniteInputReturnsNone() {
		var vhf = new VerticalHorizontalFilter(3);
		Assert.isNull(vhf.update(Math.NaN));
		Assert.isNull(vhf.update(Math.POSITIVE_INFINITY));
		Assert.isTrue(!vhf.isReady());
	}

	public function testVhfResetClearsState() {
		var vhf = new VerticalHorizontalFilter(8);
		IndicatorBatch.run(vhf, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]);
		Assert.isTrue(vhf.isReady());
		vhf.reset();
		Assert.isTrue(!vhf.isReady());
		Assert.isNull(vhf.update(1.0));
	}

	public function testVhfBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 50.0 + Math.sin(i * 0.3) * 10.0];
		var a = new VerticalHorizontalFilter(28);
		var b = new VerticalHorizontalFilter(28);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (x in prices) b.update(x)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i]);
		}
	}
}
