package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.VolumeOscillator;
import musescript.indicators.lib.VolumeRsi;
import musescript.indicators.lib.VolumeWeightedMacd;
import musescript.indicators.lib.VolumeWeightedSr;
import musescript.indicators.lib.Vwma;
import musescript.indicators.lib.VwapStdDevBands;
import musescript.indicators.lib.Vzo;
import musescript.indicators.lib.Vpt;
import musescript.indicators.lib.Wad;
import musescript.indicators.lib.Tsv;
import musescript.indicators.lib.TwiggsMoneyFlow;
import musescript.indicators.lib.TradeVolumeIndex;
import musescript.indicators.lib.Pvi;
import musescript.indicators.lib.Qstick;
import musescript.indicators.lib.Smi;
import musescript.indicators.lib.Rsx;
import musescript.indicators.lib.Rvi;
import musescript.indicators.lib.RviVolatility;

/**
 * Batch 44: 18 volume studies & volume-derived oscillators ported from
 * wickra-core. Known-value cases transcribed directly from the Rust fixture
 * blocks; batch_equals_streaming verifies IndicatorBatch.run equals
 * streaming updates.
 */
class TestPortBatch44 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i };
	}

	static function flatBar(price:Float, volume:Float, i:Int):Bar {
		return bar(price, price, price, price, volume, i);
	}

	static function assertScalarSeriesEqual(batched:Array<Null<Float>>, streamed:Array<Null<Float>>) {
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── VolumeOscillator ─────────────────────────────────────────────────────

	public function testVolumeOscillatorRejectsBadPeriods() {
		try { new VolumeOscillator(0, 5); Assert.fail("Should reject zero fast"); } catch (e:Dynamic) Assert.pass();
		try { new VolumeOscillator(5, 0); Assert.fail("Should reject zero slow"); } catch (e:Dynamic) Assert.pass();
		try { new VolumeOscillator(10, 10); Assert.fail("Should reject fast == slow"); } catch (e:Dynamic) Assert.pass();
		try { new VolumeOscillator(28, 14); Assert.fail("Should reject fast > slow"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVolumeOscillatorAccessorsAndMetadata() {
		var vo = new VolumeOscillator(14, 28);
		Assert.equals(14, vo.periods().fast);
		Assert.equals(28, vo.periods().slow);
		Assert.equals("VolumeOscillator", vo.name());
		Assert.equals(28, vo.warmupPeriod());
		Assert.isTrue(!vo.isReady());
	}

	public function testVolumeOscillatorConstantVolumeYieldsZero() {
		// Both SMAs equal the constant volume, so (fast - slow) / slow = 0.
		var vo = new VolumeOscillator(3, 6);
		var bars = [for (i in 0...30) flatBar(10.0, 500.0, i)];
		var out = IndicatorBatch.run(vo, bars);
		for (v in out) if (v != null) Assert.floatEquals(0.0, v);
	}

	public function testVolumeOscillatorZeroVolumeWindowYieldsZero() {
		// All bars carry zero volume — slow SMA is 0, defensive branch returns 0.
		var vo = new VolumeOscillator(2, 4);
		var bars = [for (i in 0...10) flatBar(10.0, 0.0, i)];
		var out = IndicatorBatch.run(vo, bars);
		Assert.floatEquals(0.0, out[3]);
	}

	public function testVolumeOscillatorReferenceValue() {
		// fast=2, slow=4 over volumes [10, 20, 30, 40, 50]:
		//   index 3: fast=(40+30)/2=35, slow=(10+20+30+40)/4=25, VO = 40.
		//   index 4: fast=(50+40)/2=45, slow=(20+30+40+50)/4=35, VO = 1000/35.
		var vo = new VolumeOscillator(2, 4);
		var bars = [for (i in 0...5) flatBar(10.0, 10.0 * (i + 1), i)];
		var out = IndicatorBatch.run(vo, bars);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.isNull(out[2]);
		Assert.floatEquals(40.0, out[3]);
		Assert.floatEquals(1000.0 / 35.0, out[4]);
	}

	public function testVolumeOscillatorBatchEqualsStreaming() {
		var bars = [for (i in 0...80) flatBar(10.0, 100.0 + (i % 11) * 5.0, i)];
		var a = new VolumeOscillator(14, 28);
		var b = new VolumeOscillator(14, 28);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	public function testVolumeOscillatorResetClearsState() {
		var bars = [for (i in 0...60) flatBar(10.0, 100.0 + i, i)];
		var vo = new VolumeOscillator(14, 28);
		IndicatorBatch.run(vo, bars);
		Assert.isTrue(vo.isReady());
		vo.reset();
		Assert.isTrue(!vo.isReady());
		Assert.isNull(vo.update(bars[0]));
	}

	// ── VolumeRsi ────────────────────────────────────────────────────────────

	static function volCandle(volume:Float, i:Int):Bar {
		return bar(100.0, 101.0, 99.0, 100.5, volume, i);
	}

	public function testVolumeRsiRejectsZeroPeriod() {
		try { new VolumeRsi(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVolumeRsiAccessorsAndMetadata() {
		var v = new VolumeRsi(14);
		Assert.equals(14, v.period);
		Assert.equals(15, v.warmupPeriod());
		Assert.equals("VolumeRsi", v.name());
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.value());
	}

	public function testVolumeRsiFirstEmissionAtWarmupPeriod() {
		var v = new VolumeRsi(3);
		var bars = [for (i in 0...6) volCandle(1000.0 + i, i)];
		var out = IndicatorBatch.run(v, bars);
		// warmup_period == period + 1 == 4: first emission at index 3.
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testVolumeRsiRisingVolumeIsOneHundred() {
		// Every change positive -> avg_loss 0 -> RSI 100.
		var v = new VolumeRsi(5);
		var bars = [for (i in 1...41) volCandle(i * 100.0, i - 1)];
		var out = IndicatorBatch.run(v, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(100.0, last);
	}

	public function testVolumeRsiFallingVolumeIsZero() {
		var v = new VolumeRsi(5);
		var bars = [for (i in 1...41) volCandle(5000.0 - i * 100.0, i - 1)];
		var out = IndicatorBatch.run(v, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(0.0, last);
	}

	public function testVolumeRsiFlatVolumeIsNeutral() {
		// Unchanged volume -> no gains and no losses -> neutral 50.
		var v = new VolumeRsi(3);
		var bars = [for (i in 0...20) volCandle(2000.0, i)];
		var out = IndicatorBatch.run(v, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(50.0, last);
	}

	public function testVolumeRsiOutputInRange() {
		var v = new VolumeRsi(14);
		var bars = [for (i in 0...200) volCandle(1000.0 + Math.sin(i * 0.3) * 600.0, i)];
		for (x in IndicatorBatch.run(v, bars)) {
			if (x != null) Assert.isTrue(x >= 0.0 && x <= 100.0);
		}
	}

	public function testVolumeRsiResetClearsState() {
		var v = new VolumeRsi(3);
		var bars = [for (i in 0...20) volCandle(1000.0 + i, i)];
		IndicatorBatch.run(v, bars);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.value());
		Assert.isNull(v.update(volCandle(1000.0, 0)));
	}

	public function testVolumeRsiBatchEqualsStreaming() {
		var bars = [for (i in 0...120) volCandle(1000.0 + Math.sin(i * 0.25) * 500.0, i)];
		var a = new VolumeRsi(14);
		var b = new VolumeRsi(14);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── VolumeWeightedMacd ───────────────────────────────────────────────────

	public function testVolumeWeightedMacdRejectsInvalidPeriods() {
		try { new VolumeWeightedMacd(0, 26, 9); Assert.fail("Should reject zero fast"); } catch (e:Dynamic) Assert.pass();
		try { new VolumeWeightedMacd(26, 12, 9); Assert.fail("Should reject fast > slow"); } catch (e:Dynamic) Assert.pass();
		try { new VolumeWeightedMacd(12, 12, 9); Assert.fail("Should reject fast == slow"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVolumeWeightedMacdAccessorsAndMetadata() {
		var m = new VolumeWeightedMacd(12, 26, 9);
		var p = m.periods();
		Assert.equals(12, p.fast);
		Assert.equals(26, p.slow);
		Assert.equals(9, p.signal);
		Assert.equals(34, m.warmupPeriod());
		Assert.equals("VolumeWeightedMacd", m.name());
		Assert.isTrue(!m.isReady());
		Assert.isNull(m.value());
	}

	public function testVolumeWeightedMacdFirstEmissionAtWarmupPeriod() {
		var m = new VolumeWeightedMacd(2, 4, 3);
		Assert.equals(6, m.warmupPeriod()); // 4 + 3 - 1
		var bars = [for (i in 0...20) flatBar(100.0 + i, 1000.0, i)];
		var out = IndicatorBatch.run(m, bars);
		for (i in 0...5) Assert.isNull(out[i]);
		Assert.notNull(out[5]);
	}

	public function testVolumeWeightedMacdUptrendHasPositiveMacd() {
		// A steady advance with equal volume -> fast VWMA leads slow -> macd > 0.
		var m = new VolumeWeightedMacd(3, 6, 3);
		var bars = [for (i in 0...60) flatBar(100.0 + i, 1000.0, i)];
		var out = IndicatorBatch.run(m, bars);
		var last:Null<VolumeWeightedMacdOutput> = null;
		for (x in out) if (x != null) last = x;
		Assert.isTrue(last.macd > 0.0, 'uptrend should give positive macd, got ${last.macd}');
	}

	public function testVolumeWeightedMacdHistogramIsMacdMinusSignal() {
		var m = new VolumeWeightedMacd(3, 6, 3);
		var bars = [for (i in 0...60) flatBar(100.0 + Math.sin(i * 0.3) * 5.0, 1000.0 + i, i)];
		for (o in IndicatorBatch.run(m, bars)) {
			if (o != null) Assert.floatEquals(o.macd - o.signal, o.histogram);
		}
	}

	public function testVolumeWeightedMacdEqualVolumeIsFinite() {
		// With constant volume, VWMA reduces to SMA; still a well-defined series.
		var m = new VolumeWeightedMacd(3, 6, 3);
		var bars = [for (i in 0...60) flatBar(100.0 + Math.sin(i * 0.2) * 4.0, 2000.0, i)];
		for (o in IndicatorBatch.run(m, bars)) {
			if (o != null) Assert.isTrue(Math.isFinite(o.macd) && Math.isFinite(o.signal));
		}
	}

	public function testVolumeWeightedMacdResetClearsState() {
		var m = new VolumeWeightedMacd(3, 6, 3);
		var bars = [for (i in 0...40) flatBar(100.0 + i, 1000.0, i)];
		IndicatorBatch.run(m, bars);
		Assert.isTrue(m.isReady());
		m.reset();
		Assert.isTrue(!m.isReady());
		Assert.isNull(m.value());
		Assert.isNull(m.update(flatBar(100.0, 1000.0, 0)));
	}

	public function testVolumeWeightedMacdBatchEqualsStreaming() {
		var bars = [for (i in 0...120) flatBar(100.0 + Math.sin(i * 0.25) * 9.0, 1000.0 + i, i)];
		var a = new VolumeWeightedMacd(12, 26, 9);
		var b = new VolumeWeightedMacd(12, 26, 9);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].macd, streamed[i].macd);
				Assert.floatEquals(batched[i].signal, streamed[i].signal);
				Assert.floatEquals(batched[i].histogram, streamed[i].histogram);
			}
		}
	}

	// ── VolumeWeightedSr ─────────────────────────────────────────────────────

	static function hlvBar(h:Float, l:Float, v:Float, i:Int):Bar {
		return bar(l, h, l, (h + l) / 2.0, v, i);
	}

	public function testVolumeWeightedSrRejectsZeroPeriod() {
		try { new VolumeWeightedSr(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVolumeWeightedSrAccessorsAndMetadata() {
		var v = new VolumeWeightedSr(20);
		Assert.equals(20, v.period);
		Assert.equals(20, v.warmupPeriod());
		Assert.equals("VolumeWeightedSr", v.name());
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.value());
	}

	public function testVolumeWeightedSrFirstEmissionAtWarmupPeriod() {
		var v = new VolumeWeightedSr(4);
		var bars = [for (i in 0...6) hlvBar(102.0, 98.0, 1000.0, i)];
		var out = IndicatorBatch.run(v, bars);
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testVolumeWeightedSrSupportBelowResistance() {
		var v = new VolumeWeightedSr(10);
		var bars = [for (i in 0...30) hlvBar(110.0 + Math.sin(i * 0.3) * 5.0, 90.0 + Math.cos(i * 0.3) * 5.0, 1000.0 + i, i)];
		for (o in IndicatorBatch.run(v, bars)) {
			if (o != null) Assert.isTrue(o.support <= o.resistance);
		}
	}

	public function testVolumeWeightedSrWeightsTowardHighVolumeBars() {
		// Three low-volume bars at [98,102] and one heavy bar at [108,112]; the
		// resistance should be pulled toward the heavy bar's high.
		var v = new VolumeWeightedSr(4);
		var bars = [
			hlvBar(102.0, 98.0, 100.0, 0),
			hlvBar(102.0, 98.0, 100.0, 1),
			hlvBar(102.0, 98.0, 100.0, 2),
			hlvBar(112.0, 108.0, 9000.0, 3),
		];
		var out = IndicatorBatch.run(v, bars);
		var last:Null<VolumeWeightedSrOutput> = null;
		for (x in out) if (x != null) last = x;
		Assert.isTrue(last.resistance > 108.0, 'resistance ${last.resistance} should lean to the heavy bar');
	}

	public function testVolumeWeightedSrZeroVolumeFallsBackToEqualWeight() {
		var v = new VolumeWeightedSr(3);
		var bars = [
			hlvBar(102.0, 98.0, 0.0, 0),
			hlvBar(104.0, 96.0, 0.0, 1),
			hlvBar(106.0, 94.0, 0.0, 2),
		];
		var out = IndicatorBatch.run(v, bars);
		var last:Null<VolumeWeightedSrOutput> = null;
		for (x in out) if (x != null) last = x;
		// Equal-weight averages: high mean = 104, low mean = 96.
		Assert.floatEquals(104.0, last.resistance);
		Assert.floatEquals(96.0, last.support);
	}

	public function testVolumeWeightedSrResetClearsState() {
		var v = new VolumeWeightedSr(4);
		IndicatorBatch.run(v, [for (i in 0...6) hlvBar(102.0, 98.0, 1000.0, i)]);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.value());
		Assert.isNull(v.update(hlvBar(102.0, 98.0, 1000.0, 0)));
	}

	public function testVolumeWeightedSrBatchEqualsStreaming() {
		var bars = [for (i in 0...120) hlvBar(110.0 + Math.sin(i * 0.25) * 9.0, 90.0 + Math.cos(i * 0.25) * 9.0, 1000.0 + i, i)];
		var a = new VolumeWeightedSr(20);
		var b = new VolumeWeightedSr(20);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].support, streamed[i].support);
				Assert.floatEquals(batched[i].resistance, streamed[i].resistance);
			}
		}
	}

	// ── Vwma ─────────────────────────────────────────────────────────────────

	public function testVwmaRejectsZeroPeriod() {
		try { new Vwma(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVwmaAccessorsAndMetadata() {
		var v = new Vwma(5);
		Assert.equals(5, v.period);
		Assert.equals("VWMA", v.name());
		Assert.isNull(v.value());
		for (i in 1...6) v.update(flatBar(100.0 + i, 1.0, i));
		Assert.notNull(v.value());
	}

	public function testVwmaReferenceValue() {
		// VWMA(2): (10·1 + 20·3) / (1 + 3) = 17.5; slide: (20·3 + 30·1)/4 = 22.5.
		var vwma = new Vwma(2);
		Assert.isNull(vwma.update(flatBar(10.0, 1.0, 0)));
		Assert.floatEquals(17.5, vwma.update(flatBar(20.0, 3.0, 1)));
		Assert.floatEquals(22.5, vwma.update(flatBar(30.0, 1.0, 2)));
	}

	public function testVwmaZeroVolumeWindowFallsBackToUnweightedMean() {
		var vwma = new Vwma(2);
		Assert.isNull(vwma.update(flatBar(10.0, 0.0, 0)));
		// Both bars have zero volume: fall back to mean(10, 20) = 15.
		Assert.floatEquals(15.0, vwma.update(flatBar(20.0, 0.0, 1)));
	}

	public function testVwmaConstantSeriesYieldsTheConstant() {
		var vwma = new Vwma(5);
		var bars = [for (i in 0...30) flatBar(42.0, 3.0, i)];
		var out = IndicatorBatch.run(vwma, bars);
		for (i in 4...out.length) {
			if (out[i] != null) Assert.floatEquals(42.0, out[i]);
		}
	}

	public function testVwmaHighVolumeBarPullsTheAverage() {
		var vwma = new Vwma(3);
		vwma.update(flatBar(10.0, 1.0, 0));
		vwma.update(flatBar(10.0, 1.0, 1));
		var v = vwma.update(flatBar(20.0, 100.0, 2));
		var simpleMean = (10.0 + 10.0 + 20.0) / 3.0;
		Assert.isTrue(v > simpleMean, '${v} should exceed simple mean ${simpleMean}');
	}

	public function testVwmaFirstEmissionAtWarmupPeriod() {
		var vwma = new Vwma(4);
		Assert.equals(4, vwma.warmupPeriod());
		for (i in 0...3) Assert.isNull(vwma.update(flatBar(10.0, 1.0, i)));
		Assert.notNull(vwma.update(flatBar(10.0, 1.0, 3)));
	}

	public function testVwmaResetClearsState() {
		var vwma = new Vwma(3);
		IndicatorBatch.run(vwma, [for (i in 0...10) flatBar(10.0 + i, 2.0, i)]);
		Assert.isTrue(vwma.isReady());
		vwma.reset();
		Assert.isTrue(!vwma.isReady());
		Assert.isNull(vwma.update(flatBar(10.0, 1.0, 0)));
	}

	public function testVwmaBatchEqualsStreaming() {
		var bars = [for (i in 0...50) flatBar(100.0 + Math.sin(i * 0.3) * 8.0, 1.0 + (i % 7), i)];
		var a = new Vwma(8);
		var b = new Vwma(8);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── VwapStdDevBands ──────────────────────────────────────────────────────

	static function hlcvBar(h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return bar(c, h, l, c, v, i);
	}

	public function testVwapStdDevBandsRejectsNonPositiveMultiplier() {
		try { new VwapStdDevBands(0.0); Assert.fail("Should reject zero multiplier"); } catch (e:Dynamic) Assert.pass();
		try { new VwapStdDevBands(-1.0); Assert.fail("Should reject negative multiplier"); } catch (e:Dynamic) Assert.pass();
		try { new VwapStdDevBands(Math.NaN); Assert.fail("Should reject NaN multiplier"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVwapStdDevBandsAccessorsAndMetadata() {
		var v = new VwapStdDevBands(2.0);
		Assert.floatEquals(2.0, v.multiplier);
		Assert.equals(1, v.warmupPeriod());
		Assert.equals("VwapStdDevBands", v.name());
	}

	public function testVwapStdDevBandsZeroVolumeReturnsNull() {
		var v = new VwapStdDevBands(2.0);
		Assert.isNull(v.update(hlcvBar(10.0, 10.0, 10.0, 0.0, 0)));
	}

	public function testVwapStdDevBandsConstantPriceCollapsesBands() {
		var v = new VwapStdDevBands(2.0);
		var bars = [for (i in 0...10) hlcvBar(10.0, 10.0, 10.0, 5.0, i)];
		var out = IndicatorBatch.run(v, bars);
		var last:Null<VwapStdDevBandsOutput> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(10.0, last.middle);
		Assert.floatEquals(0.0, last.stddev);
		Assert.floatEquals(10.0, last.upper);
		Assert.floatEquals(10.0, last.lower);
	}

	public function testVwapStdDevBandsUpperAboveMiddleAboveLower() {
		var v = new VwapStdDevBands(2.0);
		var bars = [for (i in 0...50) {
			var m = 100.0 + Math.sin(i * 0.2) * 5.0;
			hlcvBar(m + 1.0, m - 1.0, m, 1.0 + (i % 5), i);
		}];
		for (o in IndicatorBatch.run(v, bars)) {
			if (o != null) {
				Assert.isTrue(o.upper >= o.middle);
				Assert.isTrue(o.middle >= o.lower);
				Assert.isTrue(o.stddev >= 0.0);
			}
		}
	}

	public function testVwapStdDevBandsReferenceValues() {
		// Two equal-volume bars at typical prices 8 and 12: VWAP = 10,
		// variance = (64 + 144)/2 - 100 = 4, sigma = 2. Multiplier 1.5:
		// upper = 13, lower = 7.
		var v = new VwapStdDevBands(1.5);
		v.update(hlcvBar(8.0, 8.0, 8.0, 1.0, 0));
		var out = v.update(hlcvBar(12.0, 12.0, 12.0, 1.0, 1));
		Assert.floatEquals(10.0, out.middle);
		Assert.floatEquals(2.0, out.stddev);
		Assert.floatEquals(13.0, out.upper);
		Assert.floatEquals(7.0, out.lower);
	}

	public function testVwapStdDevBandsResetClearsState() {
		var v = new VwapStdDevBands(2.0);
		IndicatorBatch.run(v, [for (i in 0...10) hlcvBar(i + 1.0, i - 1.0, i + 0.0, 1.0, i)]);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		// After reset a zero-volume bar still returns null.
		Assert.isNull(v.update(hlcvBar(10.0, 10.0, 10.0, 0.0, 0)));
	}

	public function testVwapStdDevBandsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) hlcvBar(i + 2.0, i + 0.0, i + 1.0, 1.0 + (i % 4), i)];
		var a = new VwapStdDevBands(2.0);
		var b = new VwapStdDevBands(2.0);
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].upper, streamed[i].upper);
				Assert.floatEquals(batched[i].middle, streamed[i].middle);
				Assert.floatEquals(batched[i].lower, streamed[i].lower);
				Assert.floatEquals(batched[i].stddev, streamed[i].stddev);
			}
		}
	}

	// ── Vzo ──────────────────────────────────────────────────────────────────

	public function testVzoRejectsZeroPeriod() {
		try { new Vzo(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testVzoAccessorsAndMetadata() {
		var v = new Vzo(14);
		Assert.equals(14, v.period);
		Assert.equals("VZO", v.name());
		Assert.equals(15, v.warmupPeriod());
	}

	public function testVzoStrictlyRisingSeriesSaturatesToPlus100() {
		// Every bar is an up-day with identical volume -> VZO = +100.
		var bars = [for (i in 0...60) flatBar(10.0 + i, 100.0, i)];
		var v = new Vzo(5);
		var out = IndicatorBatch.run(v, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(100.0, last);
	}

	public function testVzoStrictlyFallingSeriesSaturatesToMinus100() {
		var bars = [for (i in 0...60) flatBar(200.0 - i, 100.0, i)];
		var v = new Vzo(5);
		var out = IndicatorBatch.run(v, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(-100.0, last);
	}

	public function testVzoFlatCloseYieldsZero() {
		// signed_volume = 0 forever -> VP EMA stays at 0 -> ratio = 0.
		var bars = [for (i in 0...40) flatBar(10.0, 100.0, i)];
		var v = new Vzo(5);
		for (x in IndicatorBatch.run(v, bars)) {
			if (x != null) Assert.floatEquals(0.0, x);
		}
	}

	public function testVzoZeroVolumeWindowYieldsZero() {
		// All bars carry zero volume -> tv == 0 -> defensive branch fires.
		var bars = [for (i in 0...20) flatBar(10.0 + i, 0.0, i)];
		var v = new Vzo(3);
		var out = IndicatorBatch.run(v, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(0.0, last);
	}

	public function testVzoBatchEqualsStreaming() {
		var bars = [for (i in 0...100) flatBar(100.0 + Math.sin(i * 0.3) * 5.0, 50.0 + (i % 7) * 10.0, i)];
		var a = new Vzo(14);
		var b = new Vzo(14);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	public function testVzoResetClearsState() {
		var bars = [for (i in 0...40) flatBar(10.0 + i, 100.0, i)];
		var v = new Vzo(5);
		IndicatorBatch.run(v, bars);
		Assert.isTrue(v.isReady());
		v.reset();
		Assert.isTrue(!v.isReady());
		Assert.isNull(v.update(bars[0]));
	}

	// ── Vpt ──────────────────────────────────────────────────────────────────

	public function testVptReferenceValues() {
		// closes [10, 11, 9], volumes [100, 200, 300]:
		//   bar 1: baseline 0. bar 2: += 200·(11-10)/10 = 20. bar 3: += 300·(9-11)/11.
		var vpt = new Vpt();
		var out = IndicatorBatch.run(vpt, [
			flatBar(10.0, 100.0, 0),
			flatBar(11.0, 200.0, 1),
			flatBar(9.0, 300.0, 2),
		]);
		Assert.floatEquals(0.0, out[0]);
		Assert.floatEquals(20.0, out[1]);
		Assert.floatEquals(20.0 - 600.0 / 11.0, out[2]);
	}

	public function testVptAccessorsAndMetadata() {
		var vpt = new Vpt();
		Assert.equals("VPT", vpt.name());
		Assert.isNull(vpt.value());
		vpt.update(flatBar(100.0, 50.0, 0));
		Assert.floatEquals(0.0, vpt.value());
	}

	public function testVptZeroPreviousCloseContributesZero() {
		var vpt = new Vpt();
		vpt.update(flatBar(0.0, 100.0, 0)); // baseline; prev_close = 0
		var v = vpt.update(flatBar(50.0, 200.0, 1));
		// ROC fallback is 0, so total stays at 0.
		Assert.floatEquals(0.0, v);
	}

	public function testVptEmitsFromFirstCandleAtZero() {
		var vpt = new Vpt();
		Assert.equals(1, vpt.warmupPeriod());
		Assert.floatEquals(0.0, vpt.update(flatBar(100.0, 50.0, 0)));
	}

	public function testVptConstantCloseKeepsLineFlat() {
		var vpt = new Vpt();
		var bars = [for (i in 0...20) flatBar(100.0, 500.0, i)];
		for (v in IndicatorBatch.run(vpt, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testVptResetClearsState() {
		var vpt = new Vpt();
		IndicatorBatch.run(vpt, [
			flatBar(10.0, 100.0, 0),
			flatBar(11.0, 100.0, 1),
			flatBar(12.0, 100.0, 2),
		]);
		Assert.isTrue(vpt.isReady());
		vpt.reset();
		Assert.isTrue(!vpt.isReady());
		Assert.isNull(vpt.value());
	}

	public function testVptBatchEqualsStreaming() {
		var bars = [for (i in 0...60) flatBar(100.0 + Math.sin(i * 0.3) * 8.0, 10.0 + (i % 5), i)];
		var a = new Vpt();
		var b = new Vpt();
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── Wad ──────────────────────────────────────────────────────────────────

	static function wadBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(l, h, l, c, 1000.0, i);
	}

	public function testWadAccessorsAndMetadata() {
		var wad = new Wad();
		Assert.equals(2, wad.warmupPeriod());
		Assert.equals("Wad", wad.name());
		Assert.isTrue(!wad.isReady());
		Assert.isNull(wad.value());
	}

	public function testWadFirstBarSeedsWithoutOutput() {
		var wad = new Wad();
		Assert.isNull(wad.update(wadBar(101.0, 99.0, 100.0, 0)));
		Assert.notNull(wad.update(wadBar(102.0, 100.0, 101.0, 1)));
	}

	public function testWadUpCloseAccumulates() {
		// close rises 100 -> 101; true low = min(100, 100) = 100; AD = 1.
		var wad = new Wad();
		wad.update(wadBar(101.0, 99.0, 100.0, 0));
		Assert.floatEquals(1.0, wad.update(wadBar(102.0, 100.0, 101.0, 1)));
	}

	public function testWadDownCloseDistributes() {
		// close falls 100 -> 99; true high = max(101, 100) = 101; AD = -2.
		var wad = new Wad();
		wad.update(wadBar(102.0, 100.0, 100.0, 0));
		Assert.floatEquals(-2.0, wad.update(wadBar(101.0, 98.0, 99.0, 1)));
	}

	public function testWadUnchangedCloseAddsNothing() {
		var wad = new Wad();
		wad.update(wadBar(101.0, 99.0, 100.0, 0));
		Assert.floatEquals(0.0, wad.update(wadBar(105.0, 95.0, 100.0, 1)));
	}

	public function testWadPureUptrendIsMonotone() {
		var wad = new Wad();
		var bars = [for (i in 0...30) wadBar(101.0 + i, 99.0 + i, 100.0 + i, i)];
		var prev = Math.NEGATIVE_INFINITY;
		for (v in IndicatorBatch.run(wad, bars)) {
			if (v != null) {
				Assert.isTrue(v >= prev, "WAD must rise in an uptrend");
				prev = v;
			}
		}
	}

	public function testWadResetClearsState() {
		var wad = new Wad();
		IndicatorBatch.run(wad, [for (i in 0...10) wadBar(101.0 + i, 99.0 + i, 100.0 + i, i)]);
		Assert.isTrue(wad.isReady());
		wad.reset();
		Assert.isTrue(!wad.isReady());
		Assert.isNull(wad.value());
		Assert.isNull(wad.update(wadBar(101.0, 99.0, 100.0, 0)));
	}

	public function testWadBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.3) * 8.0;
			wadBar(base + 2.0, base - 2.0, base + 0.5, i);
		}];
		var a = new Wad();
		var b = new Wad();
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── Tsv ──────────────────────────────────────────────────────────────────

	public function testTsvRejectsZeroPeriod() {
		try { new Tsv(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testTsvAccessorsAndMetadata() {
		var t = new Tsv(18);
		Assert.equals(18, t.period);
		Assert.equals("TSV", t.name());
		Assert.equals(19, t.warmupPeriod());
	}

	public function testTsvConstantCloseYieldsZero() {
		var bars = [for (i in 0...30) flatBar(10.0, 100.0, i)];
		var t = new Tsv(5);
		for (v in IndicatorBatch.run(t, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testTsvReferenceWindowSum() {
		// closes [10,11,13,12,14,15], volumes [50,100,200,150,50,200]:
		// flows [_, 100, 400, -150, 100, 200], period 3:
		//   bar 3 -> 350, bar 4 -> 350, bar 5 -> 150.
		var t = new Tsv(3);
		var out = IndicatorBatch.run(t, [
			flatBar(10.0, 50.0, 0),
			flatBar(11.0, 100.0, 1),
			flatBar(13.0, 200.0, 2),
			flatBar(12.0, 150.0, 3),
			flatBar(14.0, 50.0, 4),
			flatBar(15.0, 200.0, 5),
		]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.isNull(out[2]);
		Assert.floatEquals(350.0, out[3]);
		Assert.floatEquals(350.0, out[4]);
		Assert.floatEquals(150.0, out[5]);
	}

	public function testTsvBatchEqualsStreaming() {
		var bars = [for (i in 0...80) flatBar(100.0 + Math.sin(i * 0.3) * 5.0, 50.0 + (i % 7) * 10.0, i)];
		var a = new Tsv(18);
		var b = new Tsv(18);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	public function testTsvResetClearsState() {
		var bars = [for (i in 0...40) flatBar(10.0 + i, 100.0, i)];
		var t = new Tsv(10);
		IndicatorBatch.run(t, bars);
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.isNull(t.update(bars[0]));
	}

	// ── TwiggsMoneyFlow ──────────────────────────────────────────────────────

	static function tmfBar(h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return bar(l, h, l, c, v, i);
	}

	public function testTwiggsMoneyFlowRejectsZeroPeriod() {
		try { new TwiggsMoneyFlow(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testTwiggsMoneyFlowFlatBarsDriveTmfToZero() {
		// Flat bars give a zero two-bar range -> ad falls back to 0 -> TMF 0.
		var tmf = new TwiggsMoneyFlow(2);
		var bars = [for (i in 0...6) tmfBar(100.0, 100.0, 100.0, 1000.0, i)];
		var out = IndicatorBatch.run(tmf, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(0.0, last);
	}

	public function testTwiggsMoneyFlowAccessorsAndMetadata() {
		var tmf = new TwiggsMoneyFlow(21);
		Assert.equals(21, tmf.period);
		Assert.equals(22, tmf.warmupPeriod());
		Assert.equals("TwiggsMoneyFlow", tmf.name());
		Assert.isTrue(!tmf.isReady());
		Assert.isNull(tmf.value());
	}

	public function testTwiggsMoneyFlowFirstEmissionAtWarmupPeriod() {
		var tmf = new TwiggsMoneyFlow(3);
		var bars = [for (i in 0...8) tmfBar(101.0 + i, 99.0 + i, 100.0 + i, 1000.0, i)];
		var out = IndicatorBatch.run(tmf, bars);
		// warmup_period == period + 1 == 4: first emission at index 3.
		for (i in 0...3) Assert.isNull(out[i]);
		Assert.notNull(out[3]);
	}

	public function testTwiggsMoneyFlowClosesAtTrueHighIsPositive() {
		// Every bar closes at its high -> strong buying pressure -> TMF -> +1.
		var tmf = new TwiggsMoneyFlow(3);
		var bars = [for (i in 0...12) bar(99.0 + i, 101.0 + i, 99.0 + i, 101.0 + i, 1000.0, i)];
		var out = IndicatorBatch.run(tmf, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.isTrue(last > 0.9, 'closing at the high should drive TMF near +1, got ${last}');
	}

	public function testTwiggsMoneyFlowClosesAtTrueLowIsNegative() {
		var tmf = new TwiggsMoneyFlow(3);
		var bars = [for (i in 0...12) bar(101.0 - i, 101.0 - i, 99.0 - i, 99.0 - i, 1000.0, i)];
		var out = IndicatorBatch.run(tmf, bars);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.isTrue(last < -0.5, 'closing at the low should drive TMF negative, got ${last}');
	}

	public function testTwiggsMoneyFlowZeroVolumeYieldsZero() {
		var tmf = new TwiggsMoneyFlow(3);
		var bars = [for (i in 0...10) tmfBar(101.0 + i, 99.0 + i, 100.0 + i, 0.0, i)];
		for (v in IndicatorBatch.run(tmf, bars)) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testTwiggsMoneyFlowOutputInRange() {
		var tmf = new TwiggsMoneyFlow(21);
		var bars = [for (i in 0...200) {
			var base = 100.0 + Math.sin(i * 0.3) * 12.0;
			tmfBar(base + 2.0, base - 2.0, base + 0.5, 1000.0, i);
		}];
		for (v in IndicatorBatch.run(tmf, bars)) {
			if (v != null) Assert.isTrue(v >= -1.0 && v <= 1.0, 'TMF out of range: ${v}');
		}
	}

	public function testTwiggsMoneyFlowResetClearsState() {
		var tmf = new TwiggsMoneyFlow(3);
		IndicatorBatch.run(tmf, [for (i in 0...12) tmfBar(101.0 + i, 99.0 + i, 100.0 + i, 1000.0, i)]);
		Assert.isTrue(tmf.isReady());
		tmf.reset();
		Assert.isTrue(!tmf.isReady());
		Assert.isNull(tmf.value());
		Assert.isNull(tmf.update(tmfBar(101.0, 99.0, 100.0, 1000.0, 0)));
	}

	public function testTwiggsMoneyFlowBatchEqualsStreaming() {
		var bars = [for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.25) * 9.0;
			tmfBar(base + 2.0, base - 1.5, base + 0.5, 1000.0 + i, i);
		}];
		var a = new TwiggsMoneyFlow(21);
		var b = new TwiggsMoneyFlow(21);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── TradeVolumeIndex ─────────────────────────────────────────────────────

	public function testTradeVolumeIndexRejectsInvalidMinTick() {
		try { new TradeVolumeIndex(-1.0); Assert.fail("Should reject negative min_tick"); } catch (e:Dynamic) Assert.pass();
		try { new TradeVolumeIndex(Math.NaN); Assert.fail("Should reject NaN min_tick"); } catch (e:Dynamic) Assert.pass();
		// A min_tick of 0 is allowed.
		Assert.notNull(new TradeVolumeIndex(0.0));
	}

	public function testTradeVolumeIndexAccessorsAndMetadata() {
		var tvi = new TradeVolumeIndex(0.25);
		Assert.floatEquals(0.25, tvi.minTick);
		Assert.equals(2, tvi.warmupPeriod());
		Assert.equals("TradeVolumeIndex", tvi.name());
		Assert.isTrue(!tvi.isReady());
		Assert.isNull(tvi.value());
	}

	public function testTradeVolumeIndexFirstBarSeedsWithoutOutput() {
		var tvi = new TradeVolumeIndex(0.5);
		Assert.isNull(tvi.update(flatBar(100.0, 1000.0, 0)));
		Assert.notNull(tvi.update(flatBar(101.0, 1000.0, 1)));
	}

	public function testTradeVolumeIndexUptrendAccumulatesVolume() {
		// Each step of +1 exceeds the 0.5 tick -> direction +1 -> add volume.
		var tvi = new TradeVolumeIndex(0.5);
		var out = IndicatorBatch.run(tvi, [
			flatBar(100.0, 1000.0, 0), // seed
			flatBar(101.0, 500.0, 1),  // +1 -> +500
			flatBar(102.0, 300.0, 2),  // +1 -> +300
		]);
		Assert.floatEquals(500.0, out[1]);
		Assert.floatEquals(800.0, out[2]);
	}

	public function testTradeVolumeIndexSmallMoveHoldsLastDirection() {
		// After an up-move, a sub-tick wobble keeps adding in the up direction.
		var tvi = new TradeVolumeIndex(1.0);
		var out = IndicatorBatch.run(tvi, [
			flatBar(100.0, 1000.0, 0), // seed
			flatBar(102.0, 400.0, 1),  // +2 > tick -> dir +1, +400
			flatBar(102.2, 100.0, 2),  // +0.2 < tick -> hold dir +1, +100
		]);
		Assert.floatEquals(400.0, out[1]);
		Assert.floatEquals(500.0, out[2]);
	}

	public function testTradeVolumeIndexDowntrendDistributesVolume() {
		var tvi = new TradeVolumeIndex(0.5);
		var out = IndicatorBatch.run(tvi, [
			flatBar(100.0, 1000.0, 0),
			flatBar(99.0, 200.0, 1), // -1 -> -200
			flatBar(98.0, 300.0, 2), // -1 -> -300
		]);
		Assert.floatEquals(-500.0, out[2]);
	}

	public function testTradeVolumeIndexResetClearsState() {
		var tvi = new TradeVolumeIndex(0.5);
		IndicatorBatch.run(tvi, [flatBar(100.0, 1.0, 0), flatBar(101.0, 1.0, 1), flatBar(102.0, 1.0, 2)]);
		Assert.isTrue(tvi.isReady());
		tvi.reset();
		Assert.isTrue(!tvi.isReady());
		Assert.isNull(tvi.value());
		Assert.isNull(tvi.update(flatBar(100.0, 1.0, 0)));
	}

	public function testTradeVolumeIndexBatchEqualsStreaming() {
		var bars = [for (i in 0...80) flatBar(100.0 + Math.sin(i * 0.3) * 5.0, 1000.0 + i, i)];
		var a = new TradeVolumeIndex(0.5);
		var b = new TradeVolumeIndex(0.5);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── Pvi ──────────────────────────────────────────────────────────────────

	public function testPviAccessorsAndMetadata() {
		var p = new Pvi();
		Assert.equals(1, p.warmupPeriod());
		Assert.equals("PVI", p.name());
		Assert.isNull(p.value());
		p.update(flatBar(10.0, 100.0, 0));
		Assert.floatEquals(1000.0, p.value());
	}

	public function testPviFirstBarSeedsBaseline() {
		var p = new Pvi();
		Assert.floatEquals(1000.0, p.update(flatBar(10.0, 100.0, 0)));
	}

	public function testPviVolumeRiseAppliesPercentChange() {
		// 1000 * (1 + (11 - 10)/10) = 1100.
		var p = new Pvi();
		p.update(flatBar(10.0, 100.0, 0));
		Assert.floatEquals(1100.0, p.update(flatBar(11.0, 200.0, 1)));
	}

	public function testPviVolumeFallLeavesIndexUnchanged() {
		var p = new Pvi();
		p.update(flatBar(10.0, 200.0, 0));
		Assert.floatEquals(1000.0, p.update(flatBar(11.0, 100.0, 1)));
	}

	public function testPviEqualVolumeLeavesIndexUnchanged() {
		var p = new Pvi();
		p.update(flatBar(10.0, 100.0, 0));
		Assert.floatEquals(1000.0, p.update(flatBar(11.0, 100.0, 1)));
	}

	public function testPviZeroPreviousCloseContributesNoReturn() {
		var p = new Pvi();
		p.update(flatBar(0.0, 100.0, 0));
		Assert.floatEquals(1000.0, p.update(flatBar(5.0, 200.0, 1)));
	}

	public function testPviCustomBaseline() {
		var p = new Pvi(100.0);
		Assert.floatEquals(100.0, p.update(flatBar(10.0, 100.0, 0)));
	}

	public function testPviBatchEqualsStreaming() {
		var bars = [for (i in 0...80) flatBar(100.0 + Math.sin(i * 0.3) * 5.0, 50.0 + (i % 7) * 10.0, i)];
		var a = new Pvi();
		var b = new Pvi();
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	public function testPviResetClearsState() {
		var p = new Pvi();
		IndicatorBatch.run(p, [flatBar(10.0, 100.0, 0), flatBar(11.0, 200.0, 1)]);
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.isNull(p.value());
	}

	// ── Qstick ───────────────────────────────────────────────────────────────

	static function ocBar(o:Float, c:Float, i:Int):Bar {
		var h = Math.max(o, c) + 1.0;
		var l = Math.min(o, c) - 1.0;
		return bar(o, h, l, c, 1.0, i);
	}

	public function testQstickRejectsZeroPeriod() {
		try { new Qstick(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testQstickAccessorsAndMetadata() {
		var q = new Qstick(5);
		Assert.equals(5, q.period);
		Assert.equals(5, q.warmupPeriod());
		Assert.equals("Qstick", q.name());
		Assert.isTrue(!q.isReady());
	}

	public function testQstickWarmupEmitsFirstValueAtPeriod() {
		var q = new Qstick(3);
		var out = IndicatorBatch.run(q, [for (i in 0...3) ocBar(10.0, 11.0, i)]);
		Assert.isNull(out[0]);
		Assert.isNull(out[1]);
		Assert.notNull(out[2]);
	}

	public function testQstickConstantBodiesYieldTheBody() {
		// Every bar closes 1.5 above its open -> Qstick converges to 1.5.
		var q = new Qstick(4);
		var out = IndicatorBatch.run(q, [for (i in 0...10) ocBar(10.0, 11.5, i)]);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(1.5, last);
	}

	public function testQstickSellingPressureIsNegative() {
		var q = new Qstick(3);
		var out = IndicatorBatch.run(q, [for (i in 0...6) ocBar(11.0, 10.0, i)]);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.isTrue(last < 0.0, 'qstick ${last} should be negative');
	}

	public function testQstickResetClearsState() {
		var q = new Qstick(3);
		IndicatorBatch.run(q, [for (i in 0...6) ocBar(10.0, 11.0, i)]);
		Assert.isTrue(q.isReady());
		q.reset();
		Assert.isTrue(!q.isReady());
	}

	public function testQstickBatchEqualsStreaming() {
		var bars = [for (i in 0...40) ocBar(100.0 + Math.sin(i * 0.3), 100.0 + Math.cos(i * 0.4), i)];
		var a = new Qstick(7);
		var b = new Qstick(7);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	// ── Smi ──────────────────────────────────────────────────────────────────

	static function smiBar(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 1.0, i);
	}

	public function testSmiRejectsZeroPeriod() {
		try { new Smi(0, 3, 3); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
		try { new Smi(5, 0, 3); Assert.fail("Should reject zero dPeriod"); } catch (e:Dynamic) Assert.pass();
		try { new Smi(5, 3, 0); Assert.fail("Should reject zero d2Period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testSmiAccessorsAndMetadata() {
		var smi = new Smi(5, 3, 3);
		var p = smi.periods();
		Assert.equals(5, p.period);
		Assert.equals(3, p.dPeriod);
		Assert.equals(3, p.d2Period);
		Assert.equals(9, smi.warmupPeriod());
		Assert.equals("SMI", smi.name());
	}

	public function testSmiClassicFactory() {
		var smi = Smi.classic();
		var p = smi.periods();
		Assert.equals(5, p.period);
		Assert.equals(3, p.dPeriod);
		Assert.equals(3, p.d2Period);
	}

	public function testSmiCloseAtHighPushesTowardPlus100() {
		var smi = Smi.classic();
		var last:Null<Float> = null;
		for (i in 0...80) {
			var h = 100.0 + i;
			var l = h - 2.0;
			last = smi.update(smiBar(h, l, h, i));
		}
		Assert.isTrue(last > 50.0, 'close-at-high series should drive SMI well above 0: ${last}');
	}

	public function testSmiCloseAtLowPushesTowardMinus100() {
		var smi = Smi.classic();
		var last:Null<Float> = null;
		for (i in 0...80) {
			var h = 100.0 - i;
			var l = h - 2.0;
			last = smi.update(smiBar(h, l, l, i));
		}
		Assert.isTrue(last < -50.0, 'close-at-low series should drive SMI well below 0: ${last}');
	}

	public function testSmiWarmupEmitsFirstValueAtWarmupPeriod() {
		var smi = new Smi(3, 2, 2);
		// period 3 + d 2 + d2 2 - 2 = 5.
		Assert.equals(5, smi.warmupPeriod());
		var got:Null<Float> = null;
		for (i in 0...5) got = smi.update(smiBar(11.0, 9.0, 10.0, i));
		Assert.notNull(got);
	}

	public function testSmiFlatCloseYieldsZeroDisplacement() {
		// Every close is exactly at the centre of the range -> SMI converges to 0.
		var smi = Smi.classic();
		var last:Null<Float> = null;
		for (i in 0...60) last = smi.update(smiBar(11.0, 9.0, 10.0, i));
		Assert.floatEquals(0.0, last);
	}

	public function testSmiZeroRangeHoldsPreviousValue() {
		// High == low on every bar -> r2 <= 0 after warmup -> hold None.
		var smi = new Smi(3, 2, 2);
		for (i in 0...7) {
			Assert.isNull(smi.update(smiBar(10.0, 10.0, 10.0, i)));
		}
	}

	public function testSmiBatchEqualsStreaming() {
		var bars = [for (i in 0...80) {
			var c = 100.0 + Math.sin(i * 0.3) * 8.0;
			smiBar(c + 1.0, c - 1.0, c, i);
		}];
		var a = Smi.classic();
		var b = Smi.classic();
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	public function testSmiResetClearsState() {
		var smi = Smi.classic();
		for (i in 0...40) smi.update(smiBar(11.0, 9.0, 10.0, i));
		Assert.isTrue(smi.isReady());
		smi.reset();
		Assert.isTrue(!smi.isReady());
	}

	// ── Rsx ──────────────────────────────────────────────────────────────────

	public function testRsxRejectsZeroLength() {
		try { new Rsx(0); Assert.fail("Should reject zero length"); } catch (e:Dynamic) Assert.pass();
	}

	public function testRsxAccessorsAndMetadata() {
		var rsx = new Rsx(14);
		Assert.equals(14, rsx.length);
		Assert.isNull(rsx.value());
		Assert.equals(15, rsx.warmupPeriod());
		Assert.equals("RSX", rsx.name());
	}

	public function testRsxWarmupThenEmits() {
		var rsx = new Rsx(3);
		// 1 input seeds prev; then 3 changes settle -> first Some on input 4.
		Assert.isNull(rsx.update(10.0));
		Assert.isNull(rsx.update(11.0));
		Assert.isNull(rsx.update(12.0));
		Assert.notNull(rsx.update(13.0));
	}

	public function testRsxFlatMarketIsNeutral() {
		// No movement -> absolute cascade is zero -> neutral 50.
		var rsx = new Rsx(5);
		var out = IndicatorBatch.run(rsx, [for (_ in 0...40) 7.0]);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.floatEquals(50.0, last);
	}

	public function testRsxOutputStaysInRange() {
		var prices = [for (i in 0...120) 100.0 + Math.sin(i * 0.35) * 12.0];
		var rsx = new Rsx(14);
		for (v in IndicatorBatch.run(rsx, prices)) {
			if (v != null) Assert.isTrue(v >= 0.0 && v <= 100.0, 'RSX ${v} left [0, 100]');
		}
	}

	public function testRsxStrongUptrendIsHigh() {
		var prices = [for (i in 1...61) (i : Float)];
		var rsx = new Rsx(14);
		var out = IndicatorBatch.run(rsx, prices);
		var last:Null<Float> = null;
		for (x in out) if (x != null) last = x;
		Assert.isTrue(last > 80.0, 'strong uptrend should push RSX high, got ${last}');
	}

	public function testRsxIgnoresNonFiniteInput() {
		var rsx = new Rsx(3);
		var out = IndicatorBatch.run(rsx, [1.0, 2.0, 3.0, 4.0, 5.0]);
		var ready:Null<Float> = null;
		for (x in out) if (x != null) ready = x;
		Assert.floatEquals(ready, rsx.update(Math.NaN));
		Assert.floatEquals(ready, rsx.update(Math.POSITIVE_INFINITY));
	}

	public function testRsxResetClearsState() {
		var rsx = new Rsx(5);
		IndicatorBatch.run(rsx, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(rsx.isReady());
		rsx.reset();
		Assert.isTrue(!rsx.isReady());
		Assert.isNull(rsx.update(1.0));
	}

	public function testRsxBatchEqualsStreaming() {
		var prices = [for (i in 1...61) 50.0 + Math.sin(i * 0.5) * 10.0];
		var a = new Rsx(14);
		var b = new Rsx(14);
		assertScalarSeriesEqual(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	// ── Rvi ──────────────────────────────────────────────────────────────────

	static function rviBar(o:Float, h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(o, h, l, c, 1.0, i);
	}

	public function testRviRejectsZeroPeriod() {
		try { new Rvi(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testRviAccessorsAndMetadata() {
		var r = new Rvi(10);
		Assert.equals(10, r.period);
		Assert.equals(10, r.warmupPeriod());
		Assert.equals("RVI", r.name());
		Assert.isNull(r.value());
		for (i in 0...10) r.update(rviBar(10.0, 11.0, 9.0, 10.5, i));
		Assert.notNull(r.value());
	}

	public function testRviReferenceValuePeriod2() {
		// num sum = 0.5 + 0.5 = 1.0; den sum = 2.0 + 1.5 = 3.5; RVI = 1/3.5.
		var r = new Rvi(2);
		Assert.isNull(r.update(rviBar(10.0, 11.0, 9.0, 10.5, 0)));
		Assert.floatEquals(1.0 / 3.5, r.update(rviBar(10.5, 11.5, 10.0, 11.0, 1)));
	}

	public function testRviWarmupEmitsFirstValueAtPeriod() {
		var r = new Rvi(3);
		for (i in 0...2) Assert.isNull(r.update(rviBar(10.0, 11.0, 9.0, 10.5, i)));
		Assert.notNull(r.update(rviBar(10.5, 11.5, 10.0, 11.0, 2)));
	}

	public function testRviPureUptrendIsPositive() {
		// Every bar closes above its open and has a non-zero range: RVI > 0.
		var r = new Rvi(5);
		for (i in 0...10) {
			var o = 10.0 + i;
			var c = o + 0.5;
			r.update(rviBar(o, c + 0.2, o - 0.2, c, i));
		}
		Assert.isTrue(r.value() > 0.0, 'uptrend RVI should be positive: ${r.value()}');
	}

	public function testRviZeroRangeWindowHoldsValue() {
		// Window of perfectly flat bars: ratio undefined, indicator holds.
		var r = new Rvi(3);
		r.update(rviBar(10.0, 10.0, 10.0, 10.0, 0));
		r.update(rviBar(10.0, 10.0, 10.0, 10.0, 1));
		Assert.isNull(r.update(rviBar(10.0, 10.0, 10.0, 10.0, 2)));
	}

	public function testRviBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var o = 100.0 + Math.sin(i * 0.3) * 5.0;
			var c = o + Math.cos(i * 0.1);
			rviBar(o, Math.max(o, c) + 0.5, Math.min(o, c) - 0.5, c, i);
		}];
		var a = new Rvi(10);
		var b = new Rvi(10);
		assertScalarSeriesEqual(IndicatorBatch.run(a, bars), [for (x in bars) b.update(x)]);
	}

	public function testRviResetClearsState() {
		var r = new Rvi(5);
		for (i in 0...10) r.update(rviBar(10.0, 11.0, 9.0, 10.5, i));
		Assert.isTrue(r.isReady());
		r.reset();
		Assert.isTrue(!r.isReady());
		Assert.isNull(r.update(rviBar(10.0, 11.0, 9.0, 10.5, 0)));
	}

	// ── RviVolatility ────────────────────────────────────────────────────────

	public function testRviVolatilityRejectsZeroPeriod() {
		try { new RviVolatility(0); Assert.fail("Should reject zero period"); } catch (e:Dynamic) Assert.pass();
	}

	public function testRviVolatilityRejectsPeriodOne() {
		try { new RviVolatility(1); Assert.fail("Should reject period 1"); } catch (e:Dynamic) Assert.pass();
	}

	public function testRviVolatilityAccessorsAndMetadata() {
		var rvi = new RviVolatility(14);
		Assert.equals(14, rvi.period);
		Assert.equals("RVIVolatility", rvi.name());
		Assert.isNull(rvi.value());
		Assert.equals(27, rvi.warmupPeriod());
		Assert.isTrue(!rvi.isReady());
	}

	public function testRviVolatilityConstantSeriesYieldsFifty() {
		// Flat input -> zero stddev and "unchanged" direction -> 50.
		var rvi = new RviVolatility(5);
		var out = IndicatorBatch.run(rvi, [for (_ in 0...40) 42.0]);
		for (i in 9...out.length) {
			if (out[i] != null) Assert.floatEquals(50.0, out[i]);
		}
	}

	public function testRviVolatilityPureUptrendSaturatesToOneHundred() {
		var rvi = new RviVolatility(5);
		var prices = [for (i in 1...41) (i : Float)];
		var out = IndicatorBatch.run(rvi, prices);
		for (i in 9...out.length) {
			if (out[i] != null) Assert.floatEquals(100.0, out[i]);
		}
	}

	public function testRviVolatilityPureDowntrendSaturatesToZero() {
		var rvi = new RviVolatility(5);
		var prices = [for (i in 0...40) (40.0 - i)];
		var out = IndicatorBatch.run(rvi, prices);
		for (i in 9...out.length) {
			if (out[i] != null) Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testRviVolatilityOutputIsBounded() {
		var rvi = new RviVolatility(10);
		var prices = [for (i in 0...200) 100.0 + Math.sin(i * 0.3) * 12.0];
		for (v in IndicatorBatch.run(rvi, prices)) {
			if (v != null) Assert.isTrue(v >= 0.0 && v <= 100.0, 'RVI out of range: ${v}');
		}
	}

	public function testRviVolatilityFirstEmissionAtWarmupPeriod() {
		var rvi = new RviVolatility(5);
		Assert.equals(9, rvi.warmupPeriod());
		var prices = [for (i in 0...30) 100.0 + Math.sin(i * 0.4) * 3.0];
		var out = IndicatorBatch.run(rvi, prices);
		for (i in 0...8) Assert.isNull(out[i]);
		Assert.notNull(out[8]);
	}

	public function testRviVolatilityBatchEqualsStreaming() {
		var prices = [for (i in 0...120) 100.0 + Math.sin(i * 0.25) * 9.0];
		var a = new RviVolatility(10);
		var b = new RviVolatility(10);
		assertScalarSeriesEqual(IndicatorBatch.run(a, prices), [for (p in prices) b.update(p)]);
	}

	public function testRviVolatilityResetClearsState() {
		var rvi = new RviVolatility(5);
		IndicatorBatch.run(rvi, [for (i in 1...41) (i : Float)]);
		Assert.isTrue(rvi.isReady());
		rvi.reset();
		Assert.isTrue(!rvi.isReady());
		Assert.isNull(rvi.value());
		Assert.isNull(rvi.update(1.0));
	}

	public function testRviVolatilityIgnoresNonFiniteInput() {
		var rvi = new RviVolatility(5);
		var out = IndicatorBatch.run(rvi, [for (i in 1...41) (i : Float)]);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.floatEquals(last, rvi.update(Math.NaN));
		Assert.floatEquals(last, rvi.update(Math.POSITIVE_INFINITY));
	}
}
