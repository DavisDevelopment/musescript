package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.TdDemarker;
import musescript.indicators.lib.TdDwave;
import musescript.indicators.lib.TdLines;
import musescript.indicators.lib.TdMovingAverage;
import musescript.indicators.lib.TdPressure;
import musescript.indicators.lib.TdPropulsion;
import musescript.indicators.lib.TdRangeProjection;
import musescript.indicators.lib.TdRei;
import musescript.indicators.lib.TdRiskLevel;

/**
 * Batch 35: 9 Tom DeMark family indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch35 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	/** Rust test helper `c(high, low, close, ts)`: open = close, volume = 0. */
	static function hlc(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 0.0, i);
	}

	/** Rust TdMovingAverage test helper `c(median)`. */
	static function medianBar(m:Float, i:Int):Bar {
		return bar(m, m + 1.0, m - 1.0, m, 1000.0, i);
	}

	static function assertScalarBatchEqualsStreaming(batched:Array<Null<Float>>, streamed:Array<Null<Float>>) {
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── TdDemarker ───────────────────────────────────────────────────────────

	public function testTdDemarkerFlatMarketEmitsNeutral05() {
		// All highs and lows equal -> DeMax == DeMin == 0 every bar -> the
		// denominator is zero and the indicator must fall back to 0.5.
		var candles = [for (i in 0...30) hlc(11.0, 9.0, 10.0, i)];
		var dm = new TdDemarker(14);
		var out = IndicatorBatch.run(dm, candles);
		for (i in 14...out.length) {
			if (out[i] != null) Assert.floatEquals(0.5, out[i]);
		}
	}

	public function testTdDemarkerPureUptrendPegsAtOne() {
		var candles = [for (i in 0...20) hlc(11.0 + i, 9.0 + i, 10.0 + i, i)];
		var dm = new TdDemarker(5);
		var out = IndicatorBatch.run(dm, candles);
		for (i in 6...out.length) {
			if (out[i] != null) Assert.floatEquals(1.0, out[i]);
		}
	}

	public function testTdDemarkerPureDowntrendPegsAtZero() {
		var candles = [for (i in 0...20) hlc(11.0 - i, 9.0 - i, 10.0 - i, i)];
		var dm = new TdDemarker(5);
		var out = IndicatorBatch.run(dm, candles);
		for (i in 6...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testTdDemarkerStaysInUnitInterval() {
		var candles = [for (i in 0...200) {
			var m = 50.0 + Math.sin(i * 0.2) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var dm = new TdDemarker(14);
		for (v in IndicatorBatch.run(dm, candles)) {
			if (v != null) Assert.isTrue(v >= 0.0 && v <= 1.0, 'out of range: ${v}');
		}
	}

	public function testTdDemarkerBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = new TdDemarker(14);
		var b = new TdDemarker(14);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, candles), [for (x in candles) b.update(x)]);
	}

	public function testTdDemarkerRejectsZeroPeriod() {
		try {
			new TdDemarker(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdDemarkerResetClearsState() {
		var candles = [for (i in 0...30) hlc(11.0 + i, 9.0 + i, 10.0 + i, i)];
		var dm = new TdDemarker(14);
		IndicatorBatch.run(dm, candles);
		Assert.isTrue(dm.isReady());
		dm.reset();
		Assert.isTrue(!dm.isReady());
		Assert.isNull(dm.update(candles[0]));
		Assert.isNull(dm.value());
	}

	public function testTdDemarkerAccessorsAndMetadata() {
		var dm = new TdDemarker(14);
		Assert.equals(14, dm.getPeriod());
		Assert.equals(15, dm.warmupPeriod());
		Assert.equals("TDDeMarker", dm.name());
	}

	// ── TdDwave ──────────────────────────────────────────────────────────────

	static function dwaveBar(h:Float, l:Float, i:Int):Bar {
		var mid = (h + l) / 2;
		return bar(mid, h, l, mid, 1000.0, i);
	}

	static function zigzag():Array<Bar> {
		return [for (i in 0...200) {
			var base = 100.0 + Math.sin(i * 0.5) * 10.0;
			dwaveBar(base + 1.0, base - 1.0, i);
		}];
	}

	public function testTdDwaveRejectsZeroStrength() {
		try {
			new TdDwave(0);
			Assert.fail("Should reject strength 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdDwaveAccessorsAndMetadata() {
		var td = new TdDwave(2);
		Assert.equals(2, td.getStrength());
		Assert.equals(5, td.warmupPeriod());
		Assert.equals("TDDWave", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdDwaveCountsWavesOnSwings() {
		var td = new TdDwave(2);
		var out = IndicatorBatch.run(td, zigzag());
		var anySome = false;
		for (v in out) if (v != null) anySome = true;
		Assert.isTrue(anySome);
		Assert.isTrue(td.isReady());
	}

	public function testTdDwaveSameDirectionPivotsExtendOneLeg() {
		// Strictly decreasing lows mean no bar is ever a low pivot, so the
		// confirmed pivots are all highs; consecutive same-direction highs
		// never advance the wave past leg 1.
		var td = new TdDwave(1);
		var bars = [
			[10.0, 100.0], [20.0, 99.0], [12.0, 98.0], [30.0, 97.0],
			[15.0, 96.0], [25.0, 95.0], [14.0, 94.0], [14.0, 93.0],
		];
		var vals:Array<Float> = [];
		for (i in 0...bars.length) {
			var v = td.update(dwaveBar(bars[i][0], bars[i][1], i));
			if (v != null) vals.push(v);
		}
		Assert.isTrue(vals.length > 0);
		for (v in vals) Assert.floatEquals(1.0, v);
	}

	public function testTdDwaveSameDirectionLowPivotsExtendOneLeg() {
		// Mirror case: strictly increasing highs, so pivots are all lows.
		var td = new TdDwave(1);
		var bars = [
			[100.0, 10.0], [101.0, 5.0], [102.0, 8.0], [103.0, 2.0],
			[104.0, 6.0], [105.0, 4.0], [106.0, 7.0], [107.0, 7.0],
		];
		var vals:Array<Float> = [];
		for (i in 0...bars.length) {
			var v = td.update(dwaveBar(bars[i][0], bars[i][1], i));
			if (v != null) vals.push(v);
		}
		Assert.isTrue(vals.length > 0);
		for (v in vals) Assert.floatEquals(1.0, v);
	}

	public function testTdDwaveWaveStaysInOneToEight() {
		var td = new TdDwave(2);
		for (v in IndicatorBatch.run(td, zigzag())) {
			if (v != null) Assert.isTrue(v >= 1.0 && v <= 8.0, 'wave out of range: ${v}');
		}
	}

	public function testTdDwaveFlatInputNeverCounts() {
		// A perfectly flat series has no distinct swing highs/lows.
		var td = new TdDwave(2);
		var candles = [for (i in 0...40) dwaveBar(100.0, 100.0, i)];
		for (v in IndicatorBatch.run(td, candles)) Assert.isNull(v);
	}

	public function testTdDwaveResetClearsState() {
		var td = new TdDwave(2);
		IndicatorBatch.run(td, zigzag());
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdDwaveBatchEqualsStreaming() {
		var candles = zigzag();
		var a = new TdDwave(2);
		var b = new TdDwave(2);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, candles), [for (x in candles) b.update(x)]);
	}

	// ── TdLines ──────────────────────────────────────────────────────────────

	public function testTdLinesUptrendCompletesSellSetupAndSetsSupport() {
		// Strictly rising series -> sell setup completes at bar index 12.
		var candles = [for (i in 1...21) hlc(i + 0.5, i - 0.5, i, i)];
		var lines = TdLines.classic();
		var out = IndicatorBatch.run(lines, candles);
		var early = out[5];
		Assert.notNull(early);
		Assert.isTrue(Math.isNaN(early.support));
		Assert.isTrue(Math.isNaN(early.resistance));
		// After completion at idx 12, support is the low of bar idx 4 = 4.5.
		var after = out[12];
		Assert.notNull(after);
		Assert.isTrue(Math.isNaN(after.resistance));
		Assert.floatEquals(4.5, after.support);
		var finalOut = out[19];
		Assert.floatEquals(4.5, finalOut.support);
	}

	public function testTdLinesDowntrendCompletesBuySetupAndSetsResistance() {
		// Strictly decreasing series 20..1.
		var candles = [for (i in 0...20) {
			var v = 20 - i;
			hlc(v + 0.5, v - 0.5, v, i);
		}];
		var lines = TdLines.classic();
		var out = IndicatorBatch.run(lines, candles);
		// Buy setup completes at idx 12; the high at idx 4 is 16 + 0.5.
		var after = out[12];
		Assert.notNull(after);
		Assert.isTrue(Math.isNaN(after.support));
		Assert.floatEquals(16.5, after.resistance);
	}

	public function testTdLinesFlatSeriesNeverSetsLevels() {
		// All closes equal -> neither setup advances -> both levels stay NaN.
		var candles = [for (i in 0...30) hlc(10.5, 9.5, 10.0, i)];
		var lines = TdLines.classic();
		for (v in IndicatorBatch.run(lines, candles)) {
			if (v != null) {
				Assert.isTrue(Math.isNaN(v.support));
				Assert.isTrue(Math.isNaN(v.resistance));
			}
		}
	}

	public function testTdLinesBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = TdLines.classic();
		var b = TdLines.classic();
		var av = IndicatorBatch.run(a, candles);
		var bv = [for (x in candles) b.update(x)];
		Assert.equals(av.length, bv.length);
		for (i in 0...av.length) {
			Assert.equals(av[i] == null, bv[i] == null, 'row ${i} option mismatch');
			if (av[i] != null && bv[i] != null) {
				Assert.equals(Math.isNaN(av[i].support), Math.isNaN(bv[i].support), 'row ${i} support nan flag');
				Assert.equals(Math.isNaN(av[i].resistance), Math.isNaN(bv[i].resistance), 'row ${i} resistance nan flag');
				if (!Math.isNaN(av[i].support)) Assert.floatEquals(av[i].support, bv[i].support);
				if (!Math.isNaN(av[i].resistance)) Assert.floatEquals(av[i].resistance, bv[i].resistance);
			}
		}
	}

	public function testTdLinesRejectsInvalidParams() {
		try {
			new TdLines(0, 9);
			Assert.fail("Should reject lookback 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TdLines(4, 0);
			Assert.fail("Should reject target 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdLinesResetClearsState() {
		var candles = [for (i in 1...21) hlc(i + 0.5, i - 0.5, i, i)];
		var lines = TdLines.classic();
		IndicatorBatch.run(lines, candles);
		Assert.isTrue(lines.isReady());
		lines.reset();
		Assert.isTrue(!lines.isReady());
		Assert.isNull(lines.update(candles[0]));
	}

	public function testTdLinesAccessorsAndMetadata() {
		var lines = TdLines.classic();
		var p = lines.params();
		Assert.equals(4, p.lookback);
		Assert.equals(9, p.target);
		Assert.equals(5, lines.warmupPeriod());
		Assert.equals("TDLines", lines.name());
	}

	// ── TdMovingAverage ──────────────────────────────────────────────────────

	public function testTdMovingAverageRejectsInvalidPeriods() {
		try {
			new TdMovingAverage(0, 13);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TdMovingAverage(13, 5);
			Assert.fail("Should reject st1 > st2");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TdMovingAverage(5, 5);
			Assert.fail("Should reject st1 == st2");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdMovingAverageAccessorsAndMetadata() {
		var td = new TdMovingAverage(5, 13);
		var p = td.periods();
		Assert.equals(5, p.st1);
		Assert.equals(13, p.st2);
		Assert.equals(13, td.warmupPeriod());
		Assert.equals("TDMovingAverage", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdMovingAverageFirstEmissionAtWarmupPeriod() {
		var td = new TdMovingAverage(2, 4);
		var candles = [for (i in 0...8) medianBar(100.0 + i, i)];
		var out = IndicatorBatch.run(td, candles);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testTdMovingAverageFastLeadsSlowInUptrend() {
		var td = new TdMovingAverage(3, 7);
		var candles = [for (i in 0...40) medianBar(100.0 + i, i)];
		var out = IndicatorBatch.run(td, candles);
		var last = out[out.length - 1];
		Assert.isTrue(last.st1 > last.st2, "fast MA should lead in an uptrend");
	}

	public function testTdMovingAverageFastBelowSlowInDowntrend() {
		var td = new TdMovingAverage(3, 7);
		var candles = [for (i in 0...40) medianBar(200.0 - i, i)];
		var out = IndicatorBatch.run(td, candles);
		var last = out[out.length - 1];
		Assert.isTrue(last.st1 < last.st2, "fast MA should trail in a downtrend");
	}

	public function testTdMovingAverageFlatSeriesEqualLines() {
		var td = new TdMovingAverage(2, 4);
		var candles = [for (i in 0...10) medianBar(50.0, i)];
		var out = IndicatorBatch.run(td, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(50.0, last.st1);
		Assert.floatEquals(50.0, last.st2);
	}

	public function testTdMovingAverageResetClearsState() {
		var td = new TdMovingAverage(2, 4);
		IndicatorBatch.run(td, [for (i in 0...10) medianBar(100.0 + i, i)]);
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
		Assert.isNull(td.update(medianBar(100.0, 0)));
	}

	public function testTdMovingAverageBatchEqualsStreaming() {
		var candles = [for (i in 0...80) medianBar(100.0 + Math.sin(i * 0.25) * 9.0, i)];
		var a = new TdMovingAverage(5, 13);
		var b = new TdMovingAverage(5, 13);
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].st1, streamed[i].st1);
				Assert.floatEquals(batched[i].st2, streamed[i].st2);
			}
		}
	}

	// ── TdPressure ───────────────────────────────────────────────────────────

	public function testTdPressurePureBullishCandlesYieldFullPositivePressure() {
		// Every bar closes at its high (close == high, open == low) -> +100.
		var candles = [for (i in 0...20) bar(9.0, 11.0, 9.0, 11.0, 100.0, i)];
		var p = new TdPressure(5);
		var out = IndicatorBatch.run(p, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(100.0, last);
	}

	public function testTdPressurePureBearishCandlesYieldFullNegativePressure() {
		var candles = [for (i in 0...20) bar(11.0, 11.0, 9.0, 9.0, 100.0, i)];
		var p = new TdPressure(5);
		var out = IndicatorBatch.run(p, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(-100.0, last);
	}

	public function testTdPressureNeutralDojiCloseEqOpenYieldsZero() {
		var candles = [for (i in 0...20) bar(10.0, 11.0, 9.0, 10.0, 100.0, i)];
		var p = new TdPressure(5);
		var out = IndicatorBatch.run(p, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(0.0, last);
	}

	public function testTdPressureZeroRangeBarsContributeZero() {
		// Mix one zero-range bar with otherwise-bullish bars; the zero-range
		// bar must be silently skipped (not produce NaN or inf).
		var candles:Array<Bar> = [];
		for (i in 0...5) candles.push(bar(9.0, 11.0, 9.0, 11.0, 100.0, i));
		candles.push(bar(10.0, 10.0, 10.0, 10.0, 0.0, 5));
		for (i in 6...11) candles.push(bar(9.0, 11.0, 9.0, 11.0, 100.0, i));
		var p = new TdPressure(5);
		for (v in IndicatorBatch.run(p, candles)) {
			if (v != null) {
				Assert.isTrue(Math.isFinite(v), 'non-finite output: ${v}');
				Assert.isTrue(v >= -100.0 && v <= 100.0, 'out of range: ${v}');
			}
		}
	}

	public function testTdPressureFlatZeroVolumeWindowEmitsZero() {
		var candles = [for (i in 0...10) bar(10.0, 11.0, 9.0, 10.5, 0.0, i)];
		var p = new TdPressure(5);
		var out = IndicatorBatch.run(p, candles);
		var last = out[out.length - 1];
		Assert.floatEquals(0.0, last);
	}

	public function testTdPressureBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			bar(m, m + 1.0, m - 1.0, m + 0.3, 100.0, i);
		}];
		var a = new TdPressure(5);
		var b = new TdPressure(5);
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, candles), [for (x in candles) b.update(x)]);
	}

	public function testTdPressureRejectsZeroPeriod() {
		try {
			new TdPressure(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdPressureResetClearsState() {
		var candles = [for (i in 0...20) bar(9.0, 11.0, 9.0, 11.0, 100.0, i)];
		var p = new TdPressure(5);
		IndicatorBatch.run(p, candles);
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.update(candles[0]));
		Assert.isNull(p.value());
	}

	public function testTdPressureAccessorsAndMetadata() {
		var p = new TdPressure(5);
		Assert.equals(5, p.getPeriod());
		Assert.equals(5, p.warmupPeriod());
		Assert.equals("TDPressure", p.name());
	}

	// ── TdPropulsion ─────────────────────────────────────────────────────────

	static function ohlc(o:Float, h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(o, h, l, c, 0.0, i);
	}

	public function testTdPropulsionAccessorsAndMetadata() {
		var td = new TdPropulsion();
		Assert.equals(2, td.warmupPeriod());
		Assert.equals("TDPropulsion", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdPropulsionFirstBarSeedsWithoutSignal() {
		var td = new TdPropulsion();
		Assert.floatEquals(0.0, td.update(ohlc(10.0, 11.0, 9.0, 10.0, 0)));
		Assert.notNull(td.update(ohlc(10.5, 12.0, 10.0, 11.5, 1)));
	}

	public function testTdPropulsionUp() {
		// prev close 10, high 11. Current open 10.5 >= 10, close 11.5 > 11 -> +1.
		var td = new TdPropulsion();
		td.update(ohlc(9.5, 11.0, 9.0, 10.0, 0));
		Assert.floatEquals(1.0, td.update(ohlc(10.5, 12.0, 10.0, 11.5, 1)));
	}

	public function testTdPropulsionDown() {
		// prev close 10, low 9. Current open 9.5 <= 10, close 8.5 < 9 -> -1.
		var td = new TdPropulsion();
		td.update(ohlc(10.5, 11.0, 9.0, 10.0, 0));
		Assert.floatEquals(-1.0, td.update(ohlc(9.5, 10.0, 8.0, 8.5, 1)));
	}

	public function testTdPropulsionNoThrustIsZero() {
		var td = new TdPropulsion();
		td.update(ohlc(9.5, 11.0, 9.0, 10.0, 0));
		// close 10.5 not above prior high 11 -> 0.
		Assert.floatEquals(0.0, td.update(ohlc(10.5, 10.8, 10.0, 10.5, 1)));
	}

	public function testTdPropulsionResetClearsState() {
		var td = new TdPropulsion();
		td.update(ohlc(9.5, 11.0, 9.0, 10.0, 0));
		td.update(ohlc(10.5, 12.0, 10.0, 11.5, 1));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.floatEquals(0.0, td.update(ohlc(9.5, 11.0, 9.0, 10.0, 0)));
	}

	public function testTdPropulsionBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var base = 100.0 + Math.sin(i * 0.4) * 5.0;
			ohlc(base, base + 1.0, base - 1.0, base + 0.3, i);
		}];
		var a = new TdPropulsion();
		var b = new TdPropulsion();
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, candles), [for (x in candles) b.update(x)]);
	}

	// ── TdRangeProjection ────────────────────────────────────────────────────

	public function testTdRangeProjectionBullishBarUsesDoubleHighPivot() {
		// open=10, high=12, low=9, close=11 -> close > open
		// pivot_sum = 2*12 + 9 + 11 = 44; half = 22.
		// projHigh = 22 - 9 = 13; projLow = 22 - 12 = 10.
		var p = new TdRangeProjection();
		var v = p.update(ohlc(10.0, 12.0, 9.0, 11.0, 0));
		Assert.floatEquals(13.0, v.high);
		Assert.floatEquals(10.0, v.low);
	}

	public function testTdRangeProjectionBearishBarUsesDoubleLowPivot() {
		// open=11, high=12, low=9, close=10 -> close < open
		// pivot_sum = 12 + 2*9 + 10 = 40; half = 20.
		var p = new TdRangeProjection();
		var v = p.update(ohlc(11.0, 12.0, 9.0, 10.0, 0));
		Assert.floatEquals(11.0, v.high);
		Assert.floatEquals(8.0, v.low);
	}

	public function testTdRangeProjectionDojiUsesDoubleClosePivot() {
		// open=close=10, high=12, low=9 -> doji branch.
		// pivot_sum = 12 + 9 + 2*10 = 41; half = 20.5.
		var p = new TdRangeProjection();
		var v = p.update(ohlc(10.0, 12.0, 9.0, 10.0, 0));
		Assert.floatEquals(11.5, v.high);
		Assert.floatEquals(8.5, v.low);
	}

	public function testTdRangeProjectionBatchEqualsStreaming() {
		var candles = [for (i in 0...30) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			ohlc(m, m + 1.0, m - 1.0, m + 0.3, i);
		}];
		var a = new TdRangeProjection();
		var b = new TdRangeProjection();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].high, streamed[i].high);
				Assert.floatEquals(batched[i].low, streamed[i].low);
			}
		}
	}

	public function testTdRangeProjectionResetClearsState() {
		var p = new TdRangeProjection();
		p.update(ohlc(10.0, 12.0, 9.0, 11.0, 0));
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.value());
	}

	public function testTdRangeProjectionAccessorsAndMetadata() {
		var p = new TdRangeProjection();
		Assert.equals(1, p.warmupPeriod());
		Assert.equals("TDRangeProjection", p.name());
		Assert.isNull(p.value());
	}

	// ── TdRei ────────────────────────────────────────────────────────────────

	public function testTdReiFlatMarketYieldsNeutralZero() {
		// All highs and lows equal -> denominator is identically zero, so the
		// indicator emits its neutral fallback of 0.
		var candles = [for (i in 0...40) hlc(11.0, 9.0, 10.0, i)];
		var rei = TdRei.classic();
		var out = IndicatorBatch.run(rei, candles);
		for (i in rei.warmupPeriod()...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testTdReiPureUptrendPegsAt100() {
		// Slow steady uptrend (slope 0.1) keeps both overlap conditions
		// holding; every numerator equals the denominator -> REI = 100.
		var candles = [for (i in 0...40) {
			var m = 100.0 + i * 0.1;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var rei = TdRei.classic();
		var out = IndicatorBatch.run(rei, candles);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(100.0, last);
	}

	public function testTdReiPureDowntrendPegsAtMinus100() {
		var candles = [for (i in 0...40) {
			var m = 100.0 - i * 0.1;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var rei = TdRei.classic();
		var out = IndicatorBatch.run(rei, candles);
		var last:Null<Float> = null;
		for (v in out) if (v != null) last = v;
		Assert.floatEquals(-100.0, last);
	}

	public function testTdReiStaysInMinus100To100() {
		var candles = [for (i in 0...200) {
			var m = 50.0 + Math.sin(i * 0.2) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var rei = TdRei.classic();
		for (v in IndicatorBatch.run(rei, candles)) {
			if (v != null) Assert.isTrue(v >= -100.0 && v <= 100.0, 'out of range: ${v}');
		}
	}

	public function testTdReiBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = TdRei.classic();
		var b = TdRei.classic();
		assertScalarBatchEqualsStreaming(IndicatorBatch.run(a, candles), [for (x in candles) b.update(x)]);
	}

	public function testTdReiRejectsZeroPeriod() {
		try {
			new TdRei(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdReiResetClearsState() {
		var candles = [for (i in 0...40) {
			var m = 100.0 + i * 0.1;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var rei = TdRei.classic();
		IndicatorBatch.run(rei, candles);
		Assert.isTrue(rei.isReady());
		rei.reset();
		Assert.isTrue(!rei.isReady());
		Assert.isNull(rei.update(candles[0]));
		Assert.isNull(rei.value());
	}

	public function testTdReiAccessorsAndMetadata() {
		var rei = TdRei.classic();
		Assert.equals(5, rei.getPeriod());
		Assert.equals(6 + 5, rei.warmupPeriod());
		Assert.equals("TDREI", rei.name());
	}

	// ── TdRiskLevel ──────────────────────────────────────────────────────────

	public function testTdRiskLevelUptrendSetsSellRiskAboveHighestHigh() {
		// Strictly rising closes -> sell setup completes at idx 12; the
		// highest high during the run is the bar at idx 12 (high 13.5, true
		// range max(1.0, |13.5-12|, |12.5-12|) = 1.5) -> sell_risk = 15.0.
		var candles = [for (i in 1...21) hlc(i + 0.5, i - 0.5, i, i)];
		var td = TdRiskLevel.classic();
		var out = IndicatorBatch.run(td, candles);
		var after = out[12];
		Assert.notNull(after);
		Assert.isTrue(Math.isNaN(after.buyRisk));
		Assert.floatEquals(15.0, after.sellRisk);
	}

	public function testTdRiskLevelFlatSeriesNeverSetsLevels() {
		var candles = [for (i in 0...30) hlc(10.5, 9.5, 10.0, i)];
		var td = TdRiskLevel.classic();
		for (v in IndicatorBatch.run(td, candles)) {
			if (v != null) {
				Assert.isTrue(Math.isNaN(v.buyRisk));
				Assert.isTrue(Math.isNaN(v.sellRisk));
			}
		}
	}

	public function testTdRiskLevelBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = TdRiskLevel.classic();
		var b = TdRiskLevel.classic();
		var av = IndicatorBatch.run(a, candles);
		var bv = [for (x in candles) b.update(x)];
		Assert.equals(av.length, bv.length);
		for (i in 0...av.length) {
			Assert.equals(av[i] == null, bv[i] == null, 'row ${i} option mismatch');
			if (av[i] != null && bv[i] != null) {
				Assert.equals(Math.isNaN(av[i].buyRisk), Math.isNaN(bv[i].buyRisk));
				Assert.equals(Math.isNaN(av[i].sellRisk), Math.isNaN(bv[i].sellRisk));
				if (!Math.isNaN(av[i].buyRisk)) Assert.floatEquals(av[i].buyRisk, bv[i].buyRisk);
				if (!Math.isNaN(av[i].sellRisk)) Assert.floatEquals(av[i].sellRisk, bv[i].sellRisk);
			}
		}
	}

	public function testTdRiskLevelRejectsInvalidParams() {
		try {
			new TdRiskLevel(0, 9);
			Assert.fail("Should reject lookback 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TdRiskLevel(4, 0);
			Assert.fail("Should reject target 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdRiskLevelResetClearsState() {
		var candles = [for (i in 1...21) hlc(i + 0.5, i - 0.5, i, i)];
		var td = TdRiskLevel.classic();
		IndicatorBatch.run(td, candles);
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.update(candles[0]));
	}

	public function testTdRiskLevelAccessorsAndMetadata() {
		var td = TdRiskLevel.classic();
		var p = td.params();
		Assert.equals(4, p.lookback);
		Assert.equals(9, p.target);
		Assert.equals(5, td.warmupPeriod());
		Assert.equals("TDRiskLevel", td.name());
	}
}
