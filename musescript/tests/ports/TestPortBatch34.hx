package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.TdSetup;
import musescript.indicators.lib.TdCountdown;
import musescript.indicators.lib.TdSequential;
import musescript.indicators.lib.TdCombo;
import musescript.indicators.lib.TdCamouflage;
import musescript.indicators.lib.TdClop;
import musescript.indicators.lib.TdClopwin;
import musescript.indicators.lib.TdDifferential;
import musescript.indicators.lib.TdTrap;
import musescript.indicators.lib.TdOpen;

/**
 * Batch 34: 10 Tom DeMark indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch34 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Int):Bar {
		return {open: o, high: h, low: l, close: c, volume: v, time: (i : Float), index: i};
	}

	/** Rust td_setup fixture helper: flat candle at `close`. */
	static function flatC(close:Float, i:Int):Bar {
		return bar(close, close, close, close, 0.0, i);
	}

	/** Rust td_countdown/td_sequential/td_combo fixture helper c(high, low, close). */
	static function hlc(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(c, h, l, c, 0.0, i);
	}

	/** Rust td_clop/td_clopwin fixture helper c(open, close). */
	static function oc(o:Float, c:Float, i:Int):Bar {
		var high = Math.max(o, c) + 1.0;
		var low = Math.min(o, c) - 1.0;
		return bar(o, high, low, c, 0.0, i);
	}

	/** Rust td_camouflage/td_open fixture helper c(open, high, low, close). */
	static function ohlc(o:Float, h:Float, l:Float, c:Float, i:Int):Bar {
		return bar(o, h, l, c, 0.0, i);
	}

	/** Rust td_trap fixture helper c(high, low, close) with midpoint open. */
	static function trapC(h:Float, l:Float, c:Float, i:Int):Bar {
		return bar((h + l) / 2.0, h, l, c, 0.0, i);
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

	// ── TdSetup ──────────────────────────────────────────────────────────────

	public function testTdSetupPureUptrendReachesSellSetup9() {
		// Every close is strictly greater than four bars ago, so the sell
		// streak advances by one per bar from the moment lookback is filled.
		var candles = [for (i in 1...21) flatC(i, i)];
		var setup = TdSetup.classic();
		var out = IndicatorBatch.run(setup, candles);
		for (i in 0...4) {
			Assert.isNull(out[i], 'index ${i} must be null during warmup');
		}
		Assert.floatEquals(-1.0, out[4]);
		Assert.floatEquals(-2.0, out[5]);
		Assert.floatEquals(-9.0, out[12]);
		Assert.floatEquals(-9.0, out[13]);
		Assert.floatEquals(-9.0, out[19]);
	}

	public function testTdSetupPureDowntrendReachesBuySetup9() {
		var candles = [for (i in 0...20) flatC(20 - i, i)];
		var setup = TdSetup.classic();
		var out = IndicatorBatch.run(setup, candles);
		Assert.floatEquals(1.0, out[4]);
		Assert.floatEquals(9.0, out[12]);
		Assert.floatEquals(9.0, out[19]);
	}

	public function testTdSetupFlatSeriesEmitsZeroAfterWarmup() {
		var candles = [for (i in 0...20) flatC(42.0, i)];
		var setup = TdSetup.classic();
		var out = IndicatorBatch.run(setup, candles);
		for (i in 4...out.length) {
			Assert.floatEquals(0.0, out[i]);
		}
	}

	public function testTdSetupStreakResetsOnDirectionFlip() {
		// First 4 closes are warmup. Then 4 strictly-lower closes -> buy
		// streak 1..=4. The next close is higher than its reference -> the
		// buy streak resets and the sell streak starts at 1.
		var candles = [
			flatC(10.0, 0), flatC(10.0, 1), flatC(10.0, 2), flatC(10.0, 3),
			flatC(9.0, 4), flatC(8.0, 5), flatC(7.0, 6), flatC(6.0, 7),
			flatC(11.0, 8),
		];
		var setup = TdSetup.classic();
		var out = IndicatorBatch.run(setup, candles);
		Assert.floatEquals(1.0, out[4]);
		Assert.floatEquals(4.0, out[7]);
		Assert.floatEquals(-1.0, out[8]);
	}

	public function testTdSetupRejectsZeroArguments() {
		try {
			new TdSetup(0, 9);
			Assert.fail("Should reject lookback == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new TdSetup(4, 0);
			Assert.fail("Should reject target == 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testTdSetupBatchEqualsStreaming() {
		var candles = [for (i in 0...80) flatC(100.0 + Math.sin(i * 0.3) * 5.0, i)];
		var a = TdSetup.classic();
		var b = TdSetup.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	public function testTdSetupResetClearsState() {
		var candles = [for (i in 1...21) flatC(i, i)];
		var setup = TdSetup.classic();
		IndicatorBatch.run(setup, candles);
		Assert.isTrue(setup.isReady());
		setup.reset();
		Assert.isTrue(!setup.isReady());
		Assert.isNull(setup.update(candles[0]));
		Assert.isNull(setup.value());
	}

	public function testTdSetupAccessorsAndMetadata() {
		var setup = new TdSetup(4, 9);
		Assert.same([4, 9], setup.params());
		Assert.equals(5, setup.warmupPeriod());
		Assert.equals("TDSetup", setup.name());
		Assert.isNull(setup.value());
	}

	// ── TdCountdown ──────────────────────────────────────────────────────────

	public function testTdCountdownPureUptrendRunsSellCountdownToMinus13() {
		var candles = [for (i in 1...41) hlc(i + 0.5, i - 0.5, i, i)];
		var td = TdCountdown.classic();
		var out = IndicatorBatch.run(td, candles);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		// At idx 12 the sell setup completes; on the same bar the countdown
		// rule fires once because close > high[i-2] for a strictly-rising
		// series, so countdown == -1.
		Assert.floatEquals(-1.0, out[12]);
		// After enough bars the countdown saturates at -13.
		Assert.floatEquals(-13.0, out[30]);
	}

	public function testTdCountdownPureDowntrendRunsBuyCountdownToPlus13() {
		var candles = [for (k in 0...40) {
			var i = 40 - k;
			hlc(i + 0.5, i - 0.5, i, k);
		}];
		var td = TdCountdown.classic();
		var out = IndicatorBatch.run(td, candles);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		Assert.floatEquals(1.0, out[12]);
		Assert.floatEquals(13.0, out[30]);
	}

	public function testTdCountdownFlatSeriesNeverArmsCountdown() {
		var candles = [for (i in 0...30) hlc(10.5, 9.5, 10.0, i)];
		var td = TdCountdown.classic();
		var out = IndicatorBatch.run(td, candles);
		for (v in out) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testTdCountdownBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = TdCountdown.classic();
		var b = TdCountdown.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	public function testTdCountdownRejectsInvalidParams() {
		var badParams = [[0, 9, 2, 13], [4, 0, 2, 13], [4, 9, 0, 13], [4, 9, 2, 0]];
		for (p in badParams) {
			try {
				new TdCountdown(p[0], p[1], p[2], p[3]);
				Assert.fail('Should reject params ${p}');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testTdCountdownResetClearsState() {
		var candles = [for (i in 1...31) hlc(i + 0.5, i - 0.5, i, i)];
		var td = TdCountdown.classic();
		IndicatorBatch.run(td, candles);
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.update(candles[0]));
	}

	public function testTdCountdownAccessorsAndMetadata() {
		var td = TdCountdown.classic();
		Assert.same([4, 9, 2, 13], td.params());
		Assert.equals(5, td.warmupPeriod());
		Assert.equals("TDCountdown", td.name());
	}

	// ── TdSequential ─────────────────────────────────────────────────────────

	public function testTdSequentialPureUptrendCompletesSellSetupThenCountdown() {
		var candles = [for (i in 1...41) hlc(i + 0.5, i - 0.5, i, i)];
		var td = TdSequential.classic();
		var out = IndicatorBatch.run(td, candles);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		var at12 = out[12];
		Assert.notNull(at12);
		Assert.floatEquals(-9.0, at12.setup);
		Assert.floatEquals(-1.0, at12.direction); // countdown direction armed
		var later = out[30];
		Assert.floatEquals(-1.0, later.direction);
		Assert.floatEquals(-13.0, later.countdown);
	}

	public function testTdSequentialPureDowntrendCompletesBuySetupThenCountdown() {
		var candles = [for (k in 0...40) {
			var i = 40 - k;
			hlc(i + 0.5, i - 0.5, i, k);
		}];
		var td = TdSequential.classic();
		var out = IndicatorBatch.run(td, candles);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		var at12 = out[12];
		Assert.floatEquals(9.0, at12.setup);
		Assert.floatEquals(1.0, at12.direction); // buy direction armed
		var later = out[30];
		Assert.floatEquals(1.0, later.direction);
		Assert.floatEquals(13.0, later.countdown);
	}

	public function testTdSequentialFlatSeriesEmitsZeroSetupAndNoCountdown() {
		var candles = [for (i in 0...30) hlc(10.5, 9.5, 10.0, i)];
		var td = TdSequential.classic();
		var out = IndicatorBatch.run(td, candles);
		for (i in 5...out.length) {
			var o = out[i];
			Assert.notNull(o);
			Assert.floatEquals(0.0, o.setup);
			Assert.floatEquals(0.0, o.countdown);
			Assert.floatEquals(0.0, o.direction);
		}
	}

	public function testTdSequentialBatchEqualsStreaming() {
		var candles = [for (i in 0...60) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = TdSequential.classic();
		var b = TdSequential.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i].setup, streamed[i].setup);
				Assert.floatEquals(batched[i].countdown, streamed[i].countdown);
				Assert.floatEquals(batched[i].direction, streamed[i].direction);
			}
		}
	}

	public function testTdSequentialRejectsInvalidParams() {
		var badParams = [[0, 9, 2, 13], [4, 0, 2, 13], [4, 9, 0, 13], [4, 9, 2, 0]];
		for (p in badParams) {
			try {
				new TdSequential(p[0], p[1], p[2], p[3]);
				Assert.fail('Should reject params ${p}');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testTdSequentialResetClearsState() {
		var candles = [for (i in 1...21) hlc(i + 0.5, i - 0.5, i, i)];
		var td = TdSequential.classic();
		IndicatorBatch.run(td, candles);
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.update(candles[0]));
	}

	public function testTdSequentialAccessorsAndMetadata() {
		var td = TdSequential.classic();
		Assert.same([4, 9, 2, 13], td.params());
		Assert.equals(5, td.warmupPeriod());
		Assert.equals("TDSequential", td.name());
	}

	// ── TdCombo ──────────────────────────────────────────────────────────────

	public function testTdComboPureUptrendArmsSellComboAndAdvances() {
		var candles = [for (i in 1...41) hlc(i + 0.5, i - 0.5, i, i)];
		var combo = TdCombo.classic();
		var out = IndicatorBatch.run(combo, candles);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		// At idx 12 the setup completes and combo direction is sell; the
		// combo rule fires once on the same bar, so combo == -1.
		Assert.floatEquals(-1.0, out[12]);
		// By idx 30 the combo has saturated at -13.
		Assert.floatEquals(-13.0, out[30]);
	}

	public function testTdComboPureDowntrendArmsBuyComboAndAdvances() {
		var candles = [for (k in 0...40) {
			var i = 40 - k;
			hlc(i + 0.5, i - 0.5, i, k);
		}];
		var combo = TdCombo.classic();
		var out = IndicatorBatch.run(combo, candles);
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		Assert.floatEquals(1.0, out[12]);
		Assert.floatEquals(13.0, out[30]);
	}

	public function testTdComboFlatSeriesNeverArmsCombo() {
		var candles = [for (i in 0...40) hlc(10.5, 9.5, 10.0, i)];
		var combo = TdCombo.classic();
		var out = IndicatorBatch.run(combo, candles);
		for (v in out) {
			if (v != null) Assert.floatEquals(0.0, v);
		}
	}

	public function testTdComboBatchEqualsStreaming() {
		var candles = [for (i in 0...80) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = TdCombo.classic();
		var b = TdCombo.classic();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	public function testTdComboRejectsInvalidParams() {
		var badParams = [[0, 9, 2, 13], [4, 0, 2, 13], [4, 9, 0, 13], [4, 9, 2, 0]];
		for (p in badParams) {
			try {
				new TdCombo(p[0], p[1], p[2], p[3]);
				Assert.fail('Should reject params ${p}');
			} catch (e:Dynamic) {
				Assert.pass();
			}
		}
	}

	public function testTdComboResetClearsState() {
		var candles = [for (i in 1...31) hlc(i + 0.5, i - 0.5, i, i)];
		var combo = TdCombo.classic();
		IndicatorBatch.run(combo, candles);
		Assert.isTrue(combo.isReady());
		combo.reset();
		Assert.isTrue(!combo.isReady());
		Assert.isNull(combo.update(candles[0]));
	}

	public function testTdComboAccessorsAndMetadata() {
		var combo = TdCombo.classic();
		Assert.same([4, 9, 2, 13], combo.params());
		Assert.equals(5, combo.warmupPeriod());
		Assert.equals("TDCombo", combo.name());
	}

	// ── TdCamouflage ─────────────────────────────────────────────────────────

	public function testTdCamouflageAccessorsAndMetadata() {
		var td = new TdCamouflage();
		Assert.equals(2, td.warmupPeriod());
		Assert.equals("TDCamouflage", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdCamouflageFirstBarSeedsWithoutSignal() {
		var td = new TdCamouflage();
		Assert.floatEquals(0.0, td.update(ohlc(10.0, 11.0, 9.0, 10.0, 0)));
		Assert.notNull(td.update(ohlc(10.0, 11.0, 8.0, 9.5, 1)));
	}

	public function testTdCamouflageBullishBuy() {
		// prev close 10. Current: close 9.5 < 10 (lower close), close 9.5 > open 9.0,
		// low 7.0 < prev low 8.0 -> buy.
		var td = new TdCamouflage();
		td.update(ohlc(10.0, 11.0, 8.0, 10.0, 0));
		Assert.floatEquals(1.0, td.update(ohlc(9.0, 10.0, 7.0, 9.5, 1)));
	}

	public function testTdCamouflageBearishSell() {
		// prev close 10. Current: close 10.5 > 10, close 10.5 < open 11.0,
		// high 12.0 > prev high 11.0 -> sell.
		var td = new TdCamouflage();
		td.update(ohlc(10.0, 11.0, 8.0, 10.0, 0));
		Assert.floatEquals(-1.0, td.update(ohlc(11.0, 12.0, 10.0, 10.5, 1)));
	}

	public function testTdCamouflageNoPatternIsZero() {
		var td = new TdCamouflage();
		td.update(ohlc(10.0, 11.0, 9.0, 10.0, 0));
		Assert.floatEquals(0.0, td.update(ohlc(10.0, 11.5, 9.5, 11.0, 1)));
	}

	public function testTdCamouflageResetClearsState() {
		var td = new TdCamouflage();
		td.update(ohlc(10.0, 11.0, 9.0, 10.0, 0));
		td.update(ohlc(9.0, 10.0, 7.0, 9.5, 1));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.floatEquals(0.0, td.update(ohlc(10.0, 11.0, 9.0, 10.0, 2)));
	}

	public function testTdCamouflageBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var b = 100.0 + Math.sin(i * 0.4) * 5.0;
			ohlc(b, b + 1.0, b - 1.0, b + 0.2, i);
		}];
		var a = new TdCamouflage();
		var b = new TdCamouflage();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	// ── TdClop ───────────────────────────────────────────────────────────────

	public function testTdClopAccessorsAndMetadata() {
		var td = new TdClop();
		Assert.equals(2, td.warmupPeriod());
		Assert.equals("TDClop", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdClopFirstBarSeedsWithoutSignal() {
		var td = new TdClop();
		Assert.floatEquals(0.0, td.update(oc(10.0, 11.0, 0)));
		Assert.notNull(td.update(oc(9.0, 12.0, 1)));
	}

	public function testTdClopBullishBuy() {
		// prev body [10, 11]. Current open 9 < both, close 12 > both -> buy.
		var td = new TdClop();
		td.update(oc(10.0, 11.0, 0));
		Assert.floatEquals(1.0, td.update(oc(9.0, 12.0, 1)));
	}

	public function testTdClopBearishSell() {
		// prev body [10, 11]. Current open 12 > both, close 9 < both -> sell.
		var td = new TdClop();
		td.update(oc(10.0, 11.0, 0));
		Assert.floatEquals(-1.0, td.update(oc(12.0, 9.0, 1)));
	}

	public function testTdClopNoPatternIsZero() {
		var td = new TdClop();
		td.update(oc(10.0, 11.0, 0));
		Assert.floatEquals(0.0, td.update(oc(10.5, 11.5, 1)));
	}

	public function testTdClopResetClearsState() {
		var td = new TdClop();
		td.update(oc(10.0, 11.0, 0));
		td.update(oc(9.0, 12.0, 1));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.floatEquals(0.0, td.update(oc(10.0, 11.0, 2)));
	}

	public function testTdClopBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var b = 100.0 + Math.sin(i * 0.4) * 5.0;
			oc(b, b + 0.5, i);
		}];
		var a = new TdClop();
		var b = new TdClop();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	// ── TdClopwin ────────────────────────────────────────────────────────────

	public function testTdClopwinAccessorsAndMetadata() {
		var td = new TdClopwin();
		Assert.equals(2, td.warmupPeriod());
		Assert.equals("TDClopwin", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdClopwinFirstBarSeedsWithoutSignal() {
		var td = new TdClopwin();
		Assert.floatEquals(0.0, td.update(oc(10.0, 14.0, 0)));
		Assert.notNull(td.update(oc(11.0, 13.0, 1)));
	}

	public function testTdClopwinBullishInsideBodyBuy() {
		// prev body [10, 14]. Current open 11, close 13 both inside, close>open -> +1.
		var td = new TdClopwin();
		td.update(oc(10.0, 14.0, 0));
		Assert.floatEquals(1.0, td.update(oc(11.0, 13.0, 1)));
	}

	public function testTdClopwinBearishInsideBodySell() {
		// prev body [10, 14]. Current open 13, close 11 inside, close<open -> -1.
		var td = new TdClopwin();
		td.update(oc(10.0, 14.0, 0));
		Assert.floatEquals(-1.0, td.update(oc(13.0, 11.0, 1)));
	}

	public function testTdClopwinOutsideBodyIsZero() {
		var td = new TdClopwin();
		td.update(oc(10.0, 14.0, 0));
		// close 16 outside the prior body -> 0.
		Assert.floatEquals(0.0, td.update(oc(11.0, 16.0, 1)));
	}

	public function testTdClopwinResetClearsState() {
		var td = new TdClopwin();
		td.update(oc(10.0, 14.0, 0));
		td.update(oc(11.0, 13.0, 1));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.floatEquals(0.0, td.update(oc(10.0, 14.0, 2)));
	}

	public function testTdClopwinBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var b = 100.0 + Math.sin(i * 0.4) * 5.0;
			oc(b, b + 0.3, i);
		}];
		var a = new TdClopwin();
		var b = new TdClopwin();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	// ── TdDifferential ───────────────────────────────────────────────────────

	public function testTdDifferentialBuySignal() {
		// Prev bar: high=10, low=8, close=9 -> buying=1, selling=1.
		// Curr bar: high=9, low=7, close=8.5 -> close<prev.close (8.5<9),
		// buying=1.5 > 1, selling=0.5 < 1 -> buy signal +1.
		var td = new TdDifferential();
		Assert.isNull(td.update(hlc(10.0, 8.0, 9.0, 0)));
		Assert.floatEquals(1.0, td.update(hlc(9.0, 7.0, 8.5, 1)));
	}

	public function testTdDifferentialSellSignal() {
		// Prev bar: high=10, low=8, close=9 -> buying=1, selling=1.
		// Curr bar: high=12, low=9.8, close=10.5 ->
		//   buying = 0.7 < 1; selling = 1.5 > 1; close>prev -> sell.
		var td = new TdDifferential();
		Assert.isNull(td.update(hlc(10.0, 8.0, 9.0, 0)));
		Assert.floatEquals(-1.0, td.update(hlc(12.0, 9.8, 10.5, 1)));
	}

	public function testTdDifferentialNoSignalOnNeutralBar() {
		// Identical bars -> equality everywhere -> zero.
		var td = new TdDifferential();
		Assert.isNull(td.update(hlc(10.0, 8.0, 9.0, 0)));
		Assert.floatEquals(0.0, td.update(hlc(10.0, 8.0, 9.0, 1)));
	}

	public function testTdDifferentialBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var a = new TdDifferential();
		var b = new TdDifferential();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	public function testTdDifferentialOutputOnlyInCanonicalSet() {
		// Every emitted value is in {-1, 0, +1}.
		var candles = [for (i in 0...120) {
			var m = 100.0 + Math.sin(i * 0.5) * 5.0;
			hlc(m + 1.0, m - 1.0, m, i);
		}];
		var td = new TdDifferential();
		for (v in IndicatorBatch.run(td, candles)) {
			if (v != null) {
				Assert.isTrue(v == -1.0 || v == 0.0 || v == 1.0, 'unexpected value ${v}');
			}
		}
	}

	public function testTdDifferentialResetClearsState() {
		var td = new TdDifferential();
		td.update(hlc(10.0, 8.0, 9.0, 0));
		td.update(hlc(11.0, 9.0, 10.0, 1));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.update(hlc(10.0, 8.0, 9.0, 2)));
		Assert.isNull(td.value());
	}

	public function testTdDifferentialAccessorsAndMetadata() {
		var td = new TdDifferential();
		Assert.equals(2, td.warmupPeriod());
		Assert.equals("TDDifferential", td.name());
		Assert.isNull(td.value());
	}

	// ── TdTrap ───────────────────────────────────────────────────────────────

	public function testTdTrapAccessorsAndMetadata() {
		var td = new TdTrap();
		Assert.equals(3, td.warmupPeriod());
		Assert.equals("TDTrap", td.name());
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.value());
	}

	public function testTdTrapFirstTwoBarsSeedWithoutSignal() {
		var td = new TdTrap();
		Assert.floatEquals(0.0, td.update(trapC(110.0, 90.0, 100.0, 0)));
		Assert.floatEquals(0.0, td.update(trapC(108.0, 95.0, 102.0, 1)));
		Assert.notNull(td.update(trapC(112.0, 100.0, 110.0, 2)));
	}

	public function testTdTrapInsideThenBreakoutUpBuys() {
		// bar0 wide [90,110]; bar1 inside [95,108]; bar2 close 109 > 108 -> +1.
		var td = new TdTrap();
		td.update(trapC(110.0, 90.0, 100.0, 0));
		td.update(trapC(108.0, 95.0, 102.0, 1)); // inside bar (high<110, low>90)
		Assert.floatEquals(1.0, td.update(trapC(112.0, 100.0, 109.0, 2)));
	}

	public function testTdTrapInsideThenBreakdownSells() {
		var td = new TdTrap();
		td.update(trapC(110.0, 90.0, 100.0, 0));
		td.update(trapC(108.0, 95.0, 102.0, 1)); // inside bar
		Assert.floatEquals(-1.0, td.update(trapC(100.0, 92.0, 94.0, 2))); // close 94 < 95
	}

	public function testTdTrapNoInsideBarIsZero() {
		var td = new TdTrap();
		td.update(trapC(110.0, 90.0, 100.0, 0));
		td.update(trapC(115.0, 85.0, 100.0, 1)); // outside bar, not inside
		Assert.floatEquals(0.0, td.update(trapC(120.0, 110.0, 118.0, 2)));
	}

	public function testTdTrapInsideButNoBreakoutIsZero() {
		var td = new TdTrap();
		td.update(trapC(110.0, 90.0, 100.0, 0));
		td.update(trapC(108.0, 95.0, 102.0, 1)); // inside bar
		Assert.floatEquals(0.0, td.update(trapC(107.0, 96.0, 103.0, 2))); // close within [95,108]
	}

	public function testTdTrapResetClearsState() {
		var td = new TdTrap();
		td.update(trapC(110.0, 90.0, 100.0, 0));
		td.update(trapC(108.0, 95.0, 102.0, 1));
		td.update(trapC(112.0, 100.0, 109.0, 2));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.floatEquals(0.0, td.update(trapC(110.0, 90.0, 100.0, 3)));
	}

	public function testTdTrapBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var b = 100.0 + Math.sin(i * 0.4) * 6.0;
			trapC(b + 2.0, b - 2.0, b, i);
		}];
		var a = new TdTrap();
		var b = new TdTrap();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	// ── TdOpen ───────────────────────────────────────────────────────────────

	public function testTdOpenBuySignalOnGapDownWithRecovery() {
		// Prev bar: low=10. Curr open=9 < 10, curr high=11 > 10 -> buy +1.
		var td = new TdOpen();
		Assert.isNull(td.update(ohlc(10.0, 11.0, 10.0, 10.5, 0)));
		Assert.floatEquals(1.0, td.update(ohlc(9.0, 11.0, 8.5, 9.5, 1)));
	}

	public function testTdOpenSellSignalOnGapUpWithFade() {
		// Prev bar: high=12. Curr open=13 > 12, curr low=11 < 12 -> sell -1.
		var td = new TdOpen();
		Assert.isNull(td.update(ohlc(10.0, 12.0, 9.0, 11.0, 0)));
		Assert.floatEquals(-1.0, td.update(ohlc(13.0, 13.5, 11.0, 11.5, 1)));
	}

	public function testTdOpenNoSignalOnNormalOpenWithinRange() {
		// Open within previous range -> neither gap condition fires.
		var td = new TdOpen();
		Assert.isNull(td.update(ohlc(10.0, 12.0, 9.0, 11.0, 0)));
		Assert.floatEquals(0.0, td.update(ohlc(10.5, 11.5, 9.5, 11.0, 1)));
	}

	public function testTdOpenGapDownWithoutRecoveryIsZero() {
		// Open below prev.low, but high stays below prev.low too -> no signal.
		var td = new TdOpen();
		Assert.isNull(td.update(ohlc(10.0, 12.0, 10.0, 11.0, 0)));
		// Curr open=9, curr high=9.5 -> high < prev.low (10) -> no buy.
		Assert.floatEquals(0.0, td.update(ohlc(9.0, 9.5, 8.5, 9.0, 1)));
	}

	public function testTdOpenBatchEqualsStreaming() {
		var candles = [for (i in 0...40) {
			var m = 100.0 + Math.sin(i * 0.3) * 5.0;
			ohlc(m, m + 1.0, m - 1.0, m + 0.3, i);
		}];
		var a = new TdOpen();
		var b = new TdOpen();
		var batched = IndicatorBatch.run(a, candles);
		var streamed = [for (x in candles) b.update(x)];
		assertScalarBatchEqualsStreaming(batched, streamed);
	}

	public function testTdOpenOutputOnlyInCanonicalSet() {
		var candles = [for (i in 0...120) {
			var m = 100.0 + Math.sin(i * 0.5) * 5.0;
			ohlc(m, m + 1.0, m - 1.0, m + 0.3, i);
		}];
		var td = new TdOpen();
		for (v in IndicatorBatch.run(td, candles)) {
			if (v != null) {
				Assert.isTrue(v == -1.0 || v == 0.0 || v == 1.0, 'unexpected value ${v}');
			}
		}
	}

	public function testTdOpenResetClearsState() {
		var td = new TdOpen();
		td.update(ohlc(10.0, 11.0, 9.0, 10.0, 0));
		td.update(ohlc(10.5, 11.5, 9.5, 10.5, 1));
		Assert.isTrue(td.isReady());
		td.reset();
		Assert.isTrue(!td.isReady());
		Assert.isNull(td.update(ohlc(10.0, 11.0, 9.0, 10.0, 2)));
		Assert.isNull(td.value());
	}

	public function testTdOpenAccessorsAndMetadata() {
		var td = new TdOpen();
		Assert.equals(2, td.warmupPeriod());
		Assert.equals("TDOpen", td.name());
		Assert.isNull(td.value());
	}
}
