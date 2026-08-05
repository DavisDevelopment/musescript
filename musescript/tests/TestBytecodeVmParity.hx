package musescript.tests;

import utest.Test;
import utest.Assert;
import haxe.io.FPHelper;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.BacktestResult;
import musescript.vm.MuseVm;

/**
 * P0 parity gate for the Tier-A stack VM (SPEC_BYTECODE_VM.md §4): the same
 * program, run over the same synthetic feed, must produce BYTE-IDENTICAL trades
 * and equity through the tree-walking `MuseInterp` and through `MuseVm`. The
 * subset here is `onBar`/`when`/`order` with NO indicators/lookback (the evo hot
 * path) — exactly what `MuseBytecodeCompiler` lowers. "A fast tier that lies is
 * worse than a slow one that doesn't", so this compares raw f64 bits, not
 * `floatEquals`.
 */
class TestBytecodeVmParity extends Test {
	static final PROGRAMS:Array<String> = [
		// bare bar-field compare + long/flat
		"strategy S { onBar {\n  when close > open: { long(1); }\n  when close < open: { flat(); }\n} }",
		// arithmetic into a local, reused
		"strategy S { onBar {\n  a = (high - low) * 2.0\n  when a > 1.0: { long(1); }\n  when a <= 1.0: { flat(); }\n} }",
		// short-circuit-free && (both operands evaluated)
		"strategy S { onBar {\n  when (close > open) && (high > low): { long(2); }\n  when close < open: { short(1); }\n} }",
		// || plus flat
		"strategy S { onBar {\n  when (close > open) || (volume > 0.0): { long(1); }\n  when close <= open: { flat(); }\n} }",
		// if-expression -> local, drives both sides (strategy surface reserves `?` for holes)
		"strategy S { onBar {\n  sig = if (close > open) { 1.0 } else { 0.0 - 1.0 }\n  when sig > 0.0: { long(1); }\n  when sig < 0.0: { short(1); }\n} }",
		// nested arithmetic in the condition
		"strategy S { onBar {\n  when close > (open + high) / 2.0: { long(1); }\n  when close < (open + low) / 2.0: { flat(); }\n} }",
		// V3: __cs CROSS (crossover/crossunder) + CALL_BUILTIN (sma) — real trades, real crosses
		"strategy S { onBar {\n  when crossover(close, sma(close, 8)): { long(1); }\n  when crossunder(close, sma(close, 8)): { flat(); }\n} }",
		// V3: rising/falling (__cs with an int lookback arg) + a builtin in the size expr
		"strategy S { onBar {\n  when rising(close, 3): { long(1); }\n  when falling(close, 3): { flat(); }\n} }",
		// V3: builtin feeding arithmetic feeding an order condition
		"strategy S { onBar {\n  fast = sma(close, 5)\n  slow = sma(close, 20)\n  when fast > slow: { long(1); }\n  when fast < slow: { flat(); }\n} }",
		// V3: LOOKBACK — bar-field series[n] (momentum) and a local series[n]
		"strategy S { onBar {\n  when close > close[1]: { long(1); }\n  when close < close[1]: { flat(); }\n} }",
		"strategy S { onBar {\n  m = sma(close, 5)\n  when m > m[2]: { long(1); }\n  when m < m[2]: { flat(); }\n} }",
		// V3: EField — read a field off a multi-output indicator (bbands), incl. a lookback of it
		"strategy S { onBar {\n  when close > bbands(close, 20).upper: { long(1); }\n  when close < bbands(close, 20).lower: { flat(); }\n} }",
		// V3: __scr macd multi-output field access driving orders
		"strategy S { onBar {\n  when macd(close).macd > macd(close).signal: { long(1); }\n  when macd(close).macd < macd(close).signal: { flat(); }\n} }",
		// P1.1: lookback of a CALL (withSeriesOffset re-entrancy) — sma(close,5)[1]
		"strategy S { onBar {\n  when sma(close, 5) > sma(close, 5)[1]: { long(1); }\n  when sma(close, 5) < sma(close, 5)[1]: { flat(); }\n} }",
		// P1.1 widen IND: slope / hl2 static dispatch
		"strategy S { onBar {\n  when slope(close, 8) > 0.0: { long(1); }\n  when slope(close, 8) < 0.0: { flat(); }\n} }",
		"strategy S { onBar {\n  when close > hl2(): { long(1); }\n  when close < hl2(): { flat(); }\n} }",
		// Cliff 4: scalar-returning np_* over window (CALL_BUILTIN → Float; window = heap Array handle)
		"strategy S { onBar {\n  when np_mean(window(close, 5)) > open: { long(1); }\n  when np_mean(window(close, 5)) < open: { flat(); }\n} }",
		"strategy S { onBar {\n  when np_sum(window(close, 8)) > 0.0: { long(1); }\n  when np_sum(window(close, 8)) <= 0.0: { flat(); }\n} }",
		"strategy S { onBar {\n  when np_dot(window(close, 5), window(open, 5)) > 0.0: { long(1); }\n  when np_dot(window(close, 5), window(open, 5)) <= 0.0: { flat(); }\n} }",
		// Cliff 2: OBJ-lane NdArrayF64 handle — zeros/asarray → mean/sum/get_flat (nums lane stays Float)
		"strategy S { onBar {\n  xs = np_zeros(3)\n  when np_mean(xs) == 0.0: { long(1); }\n  when np_sum(xs) != 0.0: { flat(); }\n} }",
		"strategy S { onBar {\n  xs = np_asarray([1.0, 2.0, 3.0])\n  when np_get_flat(xs, 1) == 2.0: { long(1); }\n  when np_sum(xs) == 6.0: { flat(); }\n} }",
		"strategy S { onBar {\n  zs = np_ones([4])\n  when np_mean(zs) == 1.0 && np_sum(zs) == 4.0: { long(1); }\n} }",
		// Cliff PD: packed pd_rank1d → OBJ NdArrayF64 → np_get_flat / np_mean (nums stays Float)
		"strategy S { onBar {\n  r = pd_rank1d([30.0, 10.0, 20.0])\n  when np_get_flat(r, 1) == 1.0: { long(1); }\n  when np_sum(r) != 6.0: { flat(); }\n} }",
		"strategy S { onBar {\n  when np_get_flat(pd_rank1d([1.0, 2.0, 3.0], true), 1) > 0.5: { long(1); }\n  when np_get_flat(pd_rank1d([1.0, 2.0, 3.0], true), 0) < 0.5: { flat(); }\n} }",
		// Cliff PD Series: pd_series / pd_shift → OBJ Series → pd_series_values → np_get_flat
		"strategy S { onBar {\n  s = pd_series([1.0, 2.0, 3.0])\n  when np_get_flat(pd_series_values(s), 1) == 2.0: { long(1); }\n  when np_sum(pd_series_values(s)) != 6.0: { flat(); }\n} }",
		"strategy S { onBar {\n  when np_get_flat(pd_series_values(pd_shift(pd_series(window(close, 4)), 1)), 3) > 0.0: { long(1); }\n  when np_get_flat(pd_series_values(pd_shift(pd_series([5.0, 6.0, 7.0]), 1)), 1) != 5.0: { flat(); }\n} }"
	];

	public function testInterpVsVmByteParity() {
		for (src in PROGRAMS) {
			var interpRes = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), BarFeed.synthetic(400, 11));
			var vmRes = MuseVm.runBacktest(new HarnessContext(), new MuseParser().parse(src), BarFeed.synthetic(400, 11));
			assertParity(src, interpRes, vmRes);
		}
	}

	/** A program that touches an indicator is OUTSIDE the P0 subset and must
	 * throw `VmUnsupported` (deterministic fallback boundary — §8), not silently
	 * miscompile. */
	public function testOutOfSubsetThrows() {
		// Array literals are still outside the P0 subset (sma()/crossover() now compile via V3).
		var src = "strategy S { onBar {\n  xs = [1.0, 2.0, 3.0]\n  when close > 0.0: { long(1); }\n} }";
		var threw = false;
		try {
			MuseVm.runBacktest(new HarnessContext(), new MuseParser().parse(src), BarFeed.synthetic(64, 3));
		} catch (e:musescript.vm.MuseBytecodeCompiler.VmUnsupported) {
			threw = true;
		}
		Assert.isTrue(threw, "indicator program should throw VmUnsupported, not compile");
	}

	/** Cliff 2/4/PD: opaque / over-cap / non-1-D np_* and frame pd_* refuse with VmUnsupported. */
	public function testNpPdOpaqueRefused() {
		var cases = [
			"strategy S { onBar {\n  when np_zeros(65) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_zeros([2, 2]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_reshape(np_zeros(3), [3]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_mean(window(close, 5), 0) > 0.0: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_asarray([close, 1.0]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_nrows(pd_from_columns({a: [1.0]})) > 0.0: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_xs_rank(pd_from_columns({a: [1.0]}), true) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_rank1d([1.0], true, false) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_get_flat(pd_rank1d([close, 1.0]), 0) > 0.0: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_series([1.0], pd_index_range(1)) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_shift(pd_from_columns({a: [1.0, 2.0]}), 1) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_series_values(pd_from_columns({a: [1.0]})) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_get_flat(pd_series_values(pd_shift(pd_series(window(close, 4)), close)), 0) > 0.0: { long(1); }\n} }"
		];
		for (src in cases) {
			var threw = false;
			try {
				MuseVm.runBacktest(new HarnessContext(), new MuseParser().parse(src), BarFeed.synthetic(32, 2));
			} catch (e:musescript.vm.MuseBytecodeCompiler.VmUnsupported) {
				threw = true;
			}
			Assert.isTrue(threw, "expected VmUnsupported for opaque ND/PD:\n" + src);
		}
	}

	public function testVmNpEligibilityCatalog() {
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_mean"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_sum"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_dot"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_get_flat"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapProducer("window"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_zeros"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_asarray"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_zeros"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_reshape"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isScalarB("np_zeros"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isPdBuiltin("pd_xs_rank"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_rank1d"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_series"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_shift"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_series_values"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapSeries("pd_series"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapSeries("pd_shift"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isHeapSeries("pd_rank1d"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_rank1d"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_series"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_shift"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_series_values"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isScalarB("pd_nrows"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_from_columns"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_xs_rank"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_series_length"));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_rank1d", 1));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_rank1d", 2));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_rank1d", 3));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_series", 1));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_series", 2));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_shift", 1));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_shift", 2));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_shift", 3));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_series_values", 1));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_series_values", 2));
	}

	function assertParity(src:String, a:BacktestResult, b:BacktestResult) {
		Assert.equals(a.trades, b.trades, 'trades differ for:\n$src');
		Assert.equals(fbits(a.finalEquity), fbits(b.finalEquity), 'finalEquity bits differ for:\n$src');
		Assert.equals(a.equity.length, b.equity.length, 'equity length differs for:\n$src');
		var n = a.equity.length < b.equity.length ? a.equity.length : b.equity.length;
		for (i in 0...n)
			if (fbits(a.equity[i]) != fbits(b.equity[i])) {
				Assert.fail('equity[$i] bits differ (${a.equity[i]} vs ${b.equity[i]}) for:\n$src');
				break;
			}
	}

	static function fbits(f:Float):String {
		var b = FPHelper.doubleToI64(f);
		return StringTools.hex(b.high, 8) + StringTools.hex(b.low, 8);
	}
}
