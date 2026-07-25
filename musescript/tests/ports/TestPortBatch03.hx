package musescript.tests.ports;

import musescript.harness.Bar;
import musescript.indicators.lib.*;
import utest.Test;
import utest.Assert;

/**
 * Port tests for batch 03: Alpha, AnchoredRsi, AnchoredVwap, AndrewsPitchfork, Apo, AtrBands, AtrRatchet, AtrTrailingStop.
 *
 * Ported from Wickra's test suites.
 */
class TestPortBatch03 extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, i:Float):Bar {
		return { open: o, high: h, low: l, close: c, volume: v, time: i, index: Std.int(i) };
	}

	// ====== ALPHA TESTS ======

	function test_alpha_capm_perfect_fit_yields_zero_alpha() {
		// asset = 2 * bench, constant beta of 2, no alpha; with rf = 0 the
		// CAPM-implied return matches the asset's mean perfectly.
		var a = new Alpha(20, 0.0);
		var inputs:Array<musescript.indicators.lib.Alpha.Pair> = [];
		for (i in 1...21) {
			inputs.push({ a: 2.0 * i * 0.01, b: i * 0.01 });
		}
		var out = [];
		for (input in inputs) {
			out.push(a.update(input));
		}
		Assert.notNull(out[19]);
		Assert.floatEquals(0.0, out[19], 1e-9);
	}

	function test_alpha_constant_alpha_offset_recovered() {
		// asset = bench + 0.005 (additive alpha of 0.5%), beta == 1.
		var a = new Alpha(20, 0.0);
		var inputs:Array<musescript.indicators.lib.Alpha.Pair> = [];
		for (i in 1...21) {
			inputs.push({ a: i * 0.01 + 0.005, b: i * 0.01 });
		}
		var out = [];
		for (input in inputs) {
			out.push(a.update(input));
		}
		Assert.notNull(out[19]);
		Assert.floatEquals(0.005, out[19], 1e-6);
	}

	function test_alpha_batch_equals_streaming() {
		var inputs:Array<musescript.indicators.lib.Alpha.Pair> = [];
		for (i in 0...50) {
			var b = Math.sin(i * 0.2) * 0.01;
			inputs.push({ a: 1.5 * b + 0.002, b: b });
		}
		// Batch approach
		var a1 = new Alpha(10, 0.0);
		var batch_out = [];
		for (input in inputs) {
			batch_out.push(a1.update(input));
		}
		// Streaming approach
		var a2 = new Alpha(10, 0.0);
		var stream_out = [];
		for (input in inputs) {
			stream_out.push(a2.update(input));
		}
		for (i in 0...inputs.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i], stream_out[i], 1e-9);
			} else if (batch_out[i] == null && stream_out[i] == null) {
				// Both null, ok
			} else {
				Assert.fail("Batch and streaming mismatch at index " + i);
			}
		}
	}

	// ====== ANCHORED RSI TESTS ======

	function test_anchored_rsi_first_bar_seeds_and_returns_none() {
		var indicator = new AnchoredRsi();
		Assert.isNull(indicator.update(100.0));
		Assert.isFalse(indicator.isReady());
		// Second bar produces the first value.
		var result = indicator.update(101.0);
		Assert.notNull(result);
		Assert.isTrue(indicator.isReady());
	}

	function test_anchored_rsi_pure_uptrend_saturates_at_100() {
		var indicator = new AnchoredRsi();
		var out = [];
		for (price in [10.0, 11.0, 12.0, 13.0]) {
			out.push(indicator.update(price));
		}
		Assert.notNull(out[3]);
		Assert.floatEquals(100.0, out[3], 1e-9);
	}

	function test_anchored_rsi_pure_downtrend_saturates_at_0() {
		var indicator = new AnchoredRsi();
		var out = [];
		for (price in [13.0, 12.0, 11.0, 10.0]) {
			out.push(indicator.update(price));
		}
		Assert.notNull(out[3]);
		Assert.floatEquals(0.0, out[3], 1e-9);
	}

	function test_anchored_rsi_flat_window_reads_50() {
		var indicator = new AnchoredRsi();
		var out = [];
		for (price in [42.0, 42.0, 42.0]) {
			out.push(indicator.update(price));
		}
		Assert.notNull(out[2]);
		Assert.floatEquals(50.0, out[2], 1e-9);
	}

	function test_anchored_rsi_cumulative_reference_values() {
		// prices 10 -> 11 (+1) -> 9 (-2) -> 12 (+3)
		// after bar2: sum_gain=1, sum_loss=2 -> rs=0.5 -> 100 - 100/1.5 = 33.3333
		// after bar3: sum_gain=4, sum_loss=2 -> rs=2.0 -> 100 - 100/3   = 66.6667
		var indicator = new AnchoredRsi();
		var out = [];
		for (price in [10.0, 11.0, 9.0, 12.0]) {
			out.push(indicator.update(price));
		}
		Assert.notNull(out[1]);
		Assert.floatEquals(100.0, out[1], 1e-6);
		Assert.notNull(out[2]);
		Assert.floatEquals(33.333333, out[2], 1e-5);
		Assert.notNull(out[3]);
		Assert.floatEquals(66.666666, out[3], 1e-5);
	}

	function test_anchored_rsi_batch_equals_streaming() {
		var prices = [];
		for (i in 1...41) {
			prices.push(Math.sin(i * 0.3) * 5.0 + i);
		}
		var a = new AnchoredRsi();
		var batch_out = [];
		for (p in prices) {
			batch_out.push(a.update(p));
		}
		var b = new AnchoredRsi();
		var stream_out = [];
		for (p in prices) {
			stream_out.push(b.update(p));
		}
		for (i in 0...prices.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i], stream_out[i], 1e-9);
			} else if (batch_out[i] == null && stream_out[i] == null) {
				// ok
			} else {
				Assert.fail("Mismatch at index " + i);
			}
		}
	}

	// ====== ANCHORED VWAP TESTS ======

	function test_anchored_vwap_first_bar_with_zero_volume_returns_none() {
		var v = new AnchoredVwap();
		var bar1 = bar(50.0, 50.0, 50.0, 50.0, 0.0, 0);
		Assert.isNull(v.update(bar1));
		Assert.isFalse(v.isReady());
		// The next bar with volume works.
		var bar2 = bar(10.0, 10.0, 10.0, 10.0, 4.0, 1);
		var result = v.update(bar2);
		Assert.notNull(result);
		Assert.floatEquals(10.0, result, 1e-9);
	}

	function test_anchored_vwap_equal_volumes_yield_mean_typical_price() {
		// typical_price of a flat OHLC bar equals the price.
		var v = new AnchoredVwap();
		var bars = [
			bar(10.0, 10.0, 10.0, 10.0, 1.0, 0),
			bar(20.0, 20.0, 20.0, 20.0, 1.0, 1),
			bar(30.0, 30.0, 30.0, 30.0, 1.0, 2)
		];
		var out = [];
		for (bar in bars) {
			out.push(v.update(bar));
		}
		Assert.notNull(out[2]);
		Assert.floatEquals(20.0, out[2], 1e-9);
	}

	function test_anchored_vwap_weighted_average_reference() {
		// Two bars: 10@1, 20@3 -> (10 + 60) / 4 = 17.5.
		var v = new AnchoredVwap();
		var bars = [
			bar(10.0, 10.0, 10.0, 10.0, 1.0, 0),
			bar(20.0, 20.0, 20.0, 20.0, 3.0, 1)
		];
		var out = [];
		for (bar in bars) {
			out.push(v.update(bar));
		}
		Assert.notNull(out[1]);
		Assert.floatEquals(17.5, out[1], 1e-9);
	}

	function test_anchored_vwap_batch_equals_streaming() {
		var candles = [];
		for (i in 1...30) {
			candles.push(bar(i, i, i, i, 1.0, i - 1));
		}
		var a = new AnchoredVwap();
		var batch_out = [];
		for (c in candles) {
			batch_out.push(a.update(c));
		}
		var b = new AnchoredVwap();
		var stream_out = [];
		for (c in candles) {
			stream_out.push(b.update(c));
		}
		for (i in 0...candles.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i], stream_out[i], 1e-9);
			}
		}
	}

	// ====== ANDREWS PITCHFORK TESTS ======

	function test_andrews_pitchfork_none_before_three_pivots() {
		var p = new AndrewsPitchfork(2);
		var bars = [
			bar(101.0, 101.0, 99.0, 100.0, 1000.0, 0),
			bar(102.0, 102.0, 100.0, 101.0, 1000.0, 1),
			bar(101.0, 101.0, 99.0, 100.0, 1000.0, 2)
		];
		for (bar in bars) {
			var result = p.update(bar);
			Assert.isNull(result);
		}
	}

	function test_andrews_pitchfork_eventually_emits_on_swings() {
		var p = new AndrewsPitchfork(2);
		var out = [];
		for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.5) * 10.0;
			var b = bar(base, base + 1.0, base - 1.0, base, 1000.0, i);
			out.push(p.update(b));
		}
		var hasValue = false;
		for (v in out) {
			if (v != null) hasValue = true;
		}
		Assert.isTrue(hasValue, "a swinging series should form a pitchfork");
		Assert.isTrue(p.isReady());
	}

	function test_andrews_pitchfork_batch_equals_streaming() {
		var candles = [];
		for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.5) * 10.0;
			candles.push(bar(base, base + 1.0, base - 1.0, base, 1000.0, i));
		}
		var a = new AndrewsPitchfork(2);
		var batch_out = [];
		for (c in candles) {
			batch_out.push(a.update(c));
		}
		var b = new AndrewsPitchfork(2);
		var stream_out = [];
		for (c in candles) {
			stream_out.push(b.update(c));
		}
		for (i in 0...candles.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i].median, stream_out[i].median, 1e-9);
				Assert.floatEquals(batch_out[i].upper, stream_out[i].upper, 1e-9);
				Assert.floatEquals(batch_out[i].lower, stream_out[i].lower, 1e-9);
			}
		}
	}

	// ====== APO TESTS ======

	function test_apo_constant_series_converges_to_zero() {
		// Both EMAs reproduce the constant exactly, so APO is 0.
		var apo = new Apo(3, 5);
		var out = [];
		for (i in 0...30) {
			out.push(apo.update(42.0));
		}
		for (i in 4...out.length) {
			if (out[i] != null) {
				Assert.floatEquals(0.0, out[i], 1e-9);
			}
		}
	}

	function test_apo_warmup_emits_first_value_at_slow_period() {
		var apo = new Apo(2, 4);
		Assert.equals(4, apo.warmupPeriod());
		Assert.isNull(apo.update(1.0));
		Assert.isNull(apo.update(2.0));
		Assert.isNull(apo.update(3.0));
		Assert.notNull(apo.update(4.0));
	}

	function test_apo_pure_uptrend_is_positive() {
		// Fast EMA leads the slow EMA on an uptrend, so APO > 0.
		var apo = new Apo(12, 26);
		var out = [];
		for (i in 1...201) {
			out.push(apo.update(i));
		}
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.isTrue(last > 0.0);
	}

	function test_apo_batch_equals_streaming() {
		var prices = [];
		for (i in 1...121) {
			prices.push(100.0 + Math.sin(i * 0.2) * 5.0);
		}
		var a = new Apo(12, 26);
		var batch_out = [];
		for (p in prices) {
			batch_out.push(a.update(p));
		}
		var b = new Apo(12, 26);
		var stream_out = [];
		for (p in prices) {
			stream_out.push(b.update(p));
		}
		for (i in 0...prices.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i], stream_out[i], 1e-9);
			}
		}
	}

	// ====== ATR BANDS TESTS ======

	function test_atr_bands_flat_market_collapses_bands() {
		var candles = [];
		for (i in 0...30) {
			candles.push(bar(10.0, 10.0, 10.0, 10.0, 1.0, i));
		}
		var ab = new AtrBands(5, 3.0);
		var out = [];
		for (c in candles) {
			out.push(ab.update(c));
		}
		var last = null;
		for (v in out) if (v != null) last = v;
		Assert.notNull(last);
		Assert.floatEquals(10.0, last.upper, 1e-6);
		Assert.floatEquals(10.0, last.middle, 1e-6);
		Assert.floatEquals(10.0, last.lower, 1e-6);
	}

	function test_atr_bands_upper_above_middle_above_lower() {
		var candles = [];
		for (i in 0...50) {
			var m = 100.0 + Math.sin(i * 0.2) * 5.0;
			candles.push(bar(m, m + 1.0, m - 1.0, m, 1.0, i));
		}
		var ab = new AtrBands(14, 3.0);
		for (c in candles) {
			var out = ab.update(c);
			if (out != null) {
				Assert.isTrue(out.upper >= out.middle);
				Assert.isTrue(out.middle >= out.lower);
			}
		}
	}

	function test_atr_bands_batch_equals_streaming() {
		var candles = [];
		for (i in 0...40) {
			candles.push(bar(i + 2.0, i + 2.0, i, i + 1.0, 1.0, i));
		}
		var a = new AtrBands(10, 2.5);
		var batch_out = [];
		for (c in candles) {
			batch_out.push(a.update(c));
		}
		var b = new AtrBands(10, 2.5);
		var stream_out = [];
		for (c in candles) {
			stream_out.push(b.update(c));
		}
		for (i in 0...candles.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i].upper, stream_out[i].upper, 1e-9);
				Assert.floatEquals(batch_out[i].middle, stream_out[i].middle, 1e-9);
				Assert.floatEquals(batch_out[i].lower, stream_out[i].lower, 1e-9);
			}
		}
	}

	function test_atr_bands_reference_values_constant_spread() {
		// Five identical candles with TR = 2 each: ATR seeds to 2 on bar 5.
		var candles = [];
		for (i in 0...5) {
			candles.push(bar(10.0, 11.0, 9.0, 10.0, 1.0, i));
		}
		var ab = new AtrBands(5, 3.0);
		var out = [];
		for (c in candles) {
			out.push(ab.update(c));
		}
		Assert.isNull(out[0]);
		Assert.isNull(out[3]);
		Assert.notNull(out[4]);
		var v = out[4];
		Assert.floatEquals(10.0, v.middle, 1e-6);
		Assert.floatEquals(16.0, v.upper, 1e-6);
		Assert.floatEquals(4.0, v.lower, 1e-6);
	}

	// ====== ATR RATCHET TESTS ======

	function test_atr_ratchet_first_emission_at_warmup_period() {
		var r = new AtrRatchet(5, 4.0, 0.1);
		var candles = [];
		for (i in 0...12) {
			var base = 100.0 + i;
			candles.push(bar(base, base + 1.0, base - 1.0, base, 1000.0, i));
		}
		var out = [];
		for (c in candles) {
			out.push(r.update(c));
		}
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[4]);
	}

	function test_atr_ratchet_uptrend_keeps_stop_below_price() {
		var r = new AtrRatchet(5, 4.0, 0.05);
		var candles = [];
		for (i in 0...60) {
			var base = 100.0 + 2.0 * i;
			candles.push(bar(base, base + 1.0, base - 1.0, base + 0.5, 1000.0, i));
		}
		for (i in 0...candles.length) {
			var o = r.update(candles[i]);
			if (o != null) {
				Assert.equals(1.0, o.direction);
				Assert.isTrue(o.value < candles[i].close);
			}
		}
	}

	function test_atr_ratchet_batch_equals_streaming() {
		var candles = [];
		for (i in 0...120) {
			var base = 100.0 + Math.sin(i * 0.25) * 9.0;
			candles.push(bar(base, base + 2.0, base - 1.5, base + 0.5, 1000.0, i));
		}
		var batch = new AtrRatchet(14, 4.0, 0.1);
		var batch_out = [];
		for (c in candles) {
			batch_out.push(batch.update(c));
		}
		var b = new AtrRatchet(14, 4.0, 0.1);
		var stream_out = [];
		for (c in candles) {
			stream_out.push(b.update(c));
		}
		for (i in 0...candles.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i].value, stream_out[i].value, 1e-9);
				Assert.floatEquals(batch_out[i].direction, stream_out[i].direction, 1e-9);
			}
		}
	}

	// ====== ATR TRAILING STOP TESTS ======

	function test_atr_trailing_stop_reference_values_flat_market() {
		// Flat candles H=11, L=9, C=10 -> TR=2 -> ATR=2; loss = 3·2 = 6.
		// Seed stop = close - loss = 10 - 6 = 4, and it holds there.
		var candles = [];
		for (i in 0...20) {
			candles.push(bar(10.0, 11.0, 9.0, 10.0, 1.0, i));
		}
		var ts = new AtrTrailingStop(5, 3.0);
		for (c in candles) {
			var v = ts.update(c);
			if (v != null) {
				Assert.floatEquals(4.0, v, 1e-9);
			}
		}
	}

	function test_atr_trailing_stop_uptrend_stop_ratchets_up_and_stays_below_price() {
		var candles = [];
		for (i in 0...50) {
			var base = 100.0 + i;
			candles.push(bar(base, base + 1.0, base - 1.0, base, 1.0, i));
		}
		var ts = new AtrTrailingStop(14, 3.0);
		var emitted = [];
		for (c in candles) {
			var o = ts.update(c);
			if (o != null) {
				emitted.push({ stop: o, close: c.close });
			}
		}
		for (i in 0...emitted.length - 1) {
			Assert.isTrue(emitted[i + 1].stop >= emitted[i].stop - 1e-6);
		}
		for (pair in emitted) {
			Assert.isTrue(pair.stop < pair.close);
		}
	}

	function test_atr_trailing_stop_batch_equals_streaming() {
		var candles = [];
		for (i in 0...80) {
			var mid = 100.0 + Math.sin(i * 0.3) * 8.0;
			candles.push(bar(mid, mid + 1.5, mid - 1.5, mid + 0.5, 1.0, i));
		}
		var a = new AtrTrailingStop(14, 3.0);
		var batch_out = [];
		for (c in candles) {
			batch_out.push(a.update(c));
		}
		var b = new AtrTrailingStop(14, 3.0);
		var stream_out = [];
		for (c in candles) {
			stream_out.push(b.update(c));
		}
		for (i in 0...candles.length) {
			if (batch_out[i] != null && stream_out[i] != null) {
				Assert.floatEquals(batch_out[i], stream_out[i], 1e-9);
			}
		}
	}
}
