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
		"strategy S { onBar {\n  when np_get_flat(pd_series_values(pd_shift(pd_series(window(close, 4)), 1)), 3) > 0.0: { long(1); }\n  when np_get_flat(pd_series_values(pd_shift(pd_series([5.0, 6.0, 7.0]), 1)), 1) != 5.0: { flat(); }\n} }",
		// Cliff PD Frame: from_columns / xs_rank / get / groupby / join / frame shift
		"strategy S { onBar {\n  df = pd_from_columns({a: [1.0, 3.0], b: [2.0, 4.0]})\n  when pd_nrows(df) == 2.0 && pd_ncols(df) == 2.0: { long(1); }\n  when np_get_flat(pd_series_values(pd_get(df, \"a\")), 1) != 3.0: { flat(); }\n} }",
		"strategy S { onBar {\n  when np_get_flat(pd_series_values(pd_get(pd_xs_rank(pd_from_columns({x: [10.0, 30.0, 20.0]}), true), \"x\")), 1) > 0.5: { long(1); }\n} }",
		"strategy S { onBar {\n  g = pd_groupby_mean(pd_from_columns({k: [1.0, 1.0, 2.0], v: [10.0, 20.0, 30.0]}), \"k\")\n  when pd_nrows(g) == 2.0: { long(1); }\n} }",
		"strategy S { onBar {\n  L = pd_from_columns({id: [1.0, 2.0], x: [10.0, 20.0]})\n  R = pd_from_columns({id: [1.0, 2.0], y: [100.0, 200.0]})\n  when np_get_flat(pd_series_values(pd_get(pd_join(L, R, \"id\", \"inner\"), \"y\")), 0) == 100.0: { long(1); }\n} }",
		"strategy S { onBar {\n  when np_get_flat(pd_series_values(pd_get(pd_shift(pd_from_columns({a: [1.0, 2.0, 3.0]}), 1), \"a\")), 1) == 1.0: { long(1); }\n} }",
		// Cliff PD Series extras: ctor index/name + length/name scalars
		"strategy S { onBar {\n  s = pd_series([1.0, 2.0, 3.0], [10.0, 20.0, 30.0], \"x\")\n  when pd_series_length(s) == 3.0 && pd_series_name(s) == \"x\": { long(1); }\n  when np_get_flat(pd_series_values(s), 0) != 1.0: { flat(); }\n} }",
		"strategy S { onBar {\n  s = pd_series([4.0, 5.0], \"y\")\n  when pd_series_name(s) == \"y\" && pd_series_length(s) == 2.0: { long(1); }\n} }",
		// Cliff-2 widen (vm-np): runtime asarray + DetMath exp/log + pairwise + cumsum + reshape + matmul
		"strategy S { onBar {\n  xs = np_asarray([close, 1.0, 2.0])\n  when np_get_flat(xs, 1) == 1.0 && np_sum(xs) > 0.0: { long(1); }\n  when np_sum(xs) <= 0.0: { flat(); }\n} }",
		"strategy S { onBar {\n  e = np_exp(np_asarray([0.0, 1.0]))\n  when np_sum(e) > 3.0: { long(1); }\n  when np_sum(np_log(np_add(e, np_full([2], 1.0)))) > 0.0: { flat(); }\n} }",
		"strategy S { onBar {\n  ys = np_cumsum(np_add(np_asarray([1.0, close, 3.0]), np_ones(3)))\n  when np_sum(ys) > 0.0: { long(1); }\n} }",
		"strategy S { onBar {\n  r = np_reshape(np_asarray([1.0, 2.0, 3.0, 4.0]), [4])\n  when np_get_flat(r, 2) == 3.0: { long(1); }\n} }",
		"strategy S { onBar {\n  p = np_matmul([[1.0, 2.0], [3.0, 4.0]], [[5.0, 6.0], [7.0, 8.0]])\n  when np_sum(p) == 70.0: { long(1); }\n} }",
		// VM↔WASM NP close: unary/pairwise ufuncs + reduce/size/ndim (WASM N twin → VM H/B)
		"strategy S { onBar {\n  a = np_abs(np_negative(np_asarray([close, -1.0, 2.0])))\n  when np_sum(a) > 0.0: { long(1); }\n  when np_sum(a) <= 0.0: { flat(); }\n} }",
		"strategy S { onBar {\n  s = np_sign(np_asarray([-2.0, 0.0, 3.0]))\n  when np_sum(np_square(np_sqrt(np_asarray([4.0, 9.0])))) == 13.0 && np_get_flat(s, 0) == -1.0: { long(1); }\n} }",
		"strategy S { onBar {\n  c = np_clip(np_asarray([-2.0, 0.5, 3.0]), 0.0, 1.0)\n  when np_sum(c) == 1.5: { long(1); }\n} }",
		"strategy S { onBar {\n  m = np_minimum(np_asarray([1.0, 5.0]), np_asarray([3.0, 2.0]))\n  when np_sum(m) == 3.0 && np_sum(np_maximum(np_asarray([1.0, 5.0]), np_asarray([3.0, 2.0]))) == 8.0: { long(1); }\n} }",
		"strategy S { onBar {\n  xs = np_asarray([3.0, 1.0, 2.0])\n  when np_min(xs) == 1.0 && np_max(xs) == 3.0 && np_prod(np_asarray([2.0, 3.0])) == 6.0: { long(1); }\n} }",
		"strategy S { onBar {\n  when np_std(np_asarray([1.0, 1.0, 1.0])) == 0.0 && np_var(np_asarray([1.0, 1.0, 1.0])) == 0.0: { long(1); }\n} }",
		"strategy S { onBar {\n  xs = np_asarray([1.0, 2.0, 3.0])\n  when np_size(xs) == 3.0 && np_ndim(xs) == 1.0: { long(1); }\n} }"
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

	/** Cliff 2/4/PD: opaque / over-cap / non-1-D np_* and ungated frame pd_* refuse with VmUnsupported. */
	public function testNpPdOpaqueRefused() {
		var cases = [
			"strategy S { onBar {\n  when np_zeros(65) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_zeros([2, 2]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_reshape(np_zeros(3), [65]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_mean(window(close, 5), 0) > 0.0: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_asarray([[1.0, 2.0], [3.0, 4.0]]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_cumsum(np_asarray([1.0, 2.0]), 0) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_matmul([[1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]], [[1.0]]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_min(np_asarray([1.0, 2.0]), 0) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_clip(np_asarray([1.0]), close, 1.0) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_equal(np_asarray([1.0]), np_asarray([1.0])) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_vol_target_qty(np_asarray([0.01]), 0.1, 1.0) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_rank1d([1.0], true, false) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_get_flat(pd_rank1d([close, 1.0]), 0) > 0.0: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_series([1.0], pd_index_range(1)) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_series([1.0, 2.0], [1.0]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_series_values(pd_from_columns({a: [1.0]})) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when np_get_flat(pd_series_values(pd_shift(pd_series(window(close, 4)), close)), 0) > 0.0: { long(1); }\n} }",
			// Frame lane U: index/columns arity, over-cap, keys-agg, merge_asof, transform, Index
			"strategy S { onBar {\n  when pd_from_columns({a: [1.0]}, pd_index_range(1)) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_nrows(pd_from_columns({a: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0, 29.0, 30.0, 31.0, 32.0, 33.0, 34.0, 35.0, 36.0, 37.0, 38.0, 39.0, 40.0, 41.0, 42.0, 43.0, 44.0, 45.0, 46.0, 47.0, 48.0, 49.0, 50.0, 51.0, 52.0, 53.0, 54.0, 55.0, 56.0, 57.0, 58.0, 59.0, 60.0, 61.0, 62.0, 63.0, 64.0, 65.0]})) > 0.0: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_groupby_keys_agg(pd_from_columns({a: [1.0]}), [\"a\"]) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_merge_asof(pd_from_columns({t: [1.0]}), pd_from_columns({t: [1.0]}), \"t\") != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_groupby_transform(pd_from_columns({k: [1.0], v: [2.0]}), \"k\") != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_xs_rank(pd_from_columns({a: [1.0]}), true, false) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_join(pd_from_columns({id: [1.0]}), pd_from_columns({id: [1.0]}), \"id\", \"left\", true) != null: { long(1); }\n} }",
			"strategy S { onBar {\n  when pd_from_columns({a: [close]}) != null: { long(1); }\n} }"
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
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_min"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_max"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_prod"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_std"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_var"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_size"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_ndim"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_dot"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isScalarB("np_get_flat"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapProducer("window"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_zeros"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_asarray"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_full"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_exp"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_log"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_abs"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_sqrt"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_negative"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_square"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_sign"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_clip"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_minimum"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_maximum"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_add"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_cumsum"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_matmul"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isHeapNd("np_reshape"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_zeros"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_exp"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_abs"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_min"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_reshape"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_equal"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_transpose"));
		Assert.isTrue(musescript.vm.VmNpEligibility.isDocumentedUnsupported("np_vol_target_qty"));
		Assert.isFalse(musescript.vm.VmNpEligibility.isScalarB("np_zeros"));
		Assert.isTrue(musescript.vm.VmNpEligibility.arityOk("np_full", 2));
		Assert.isFalse(musescript.vm.VmNpEligibility.arityOk("np_cumsum", 2));
		Assert.isTrue(musescript.vm.VmNpEligibility.arityOk("np_clip", 3));
		Assert.isFalse(musescript.vm.VmNpEligibility.arityOk("np_min", 2));
		Assert.isTrue(musescript.vm.VmNpEligibility.fitsMatmulSide(8));
		Assert.isFalse(musescript.vm.VmNpEligibility.fitsMatmulSide(9));
		Assert.isTrue(musescript.vm.VmPdEligibility.isPdBuiltin("pd_xs_rank"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_rank1d"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_series"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_shift"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_series_values"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_from_columns"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_get"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_xs_rank"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_groupby_mean"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapPd("pd_join"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapSeries("pd_series"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapSeries("pd_get"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isHeapSeries("pd_shift"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isHeapSeries("pd_rank1d"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapFrame("pd_from_columns"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapFrame("pd_xs_rank"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isHeapFrame("pd_join"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isHeapFrame("pd_series"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_rank1d"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_series"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_shift"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_series_values"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_from_columns"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_xs_rank"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_join"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isScalarB("pd_nrows"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isScalarB("pd_ncols"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isScalarB("pd_series_length"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isScalarB("pd_series_name"));
		Assert.isFalse(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_series_length"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_merge_asof"));
		Assert.isTrue(musescript.vm.VmPdEligibility.isDocumentedUnsupported("pd_groupby_keys_agg"));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_rank1d", 1));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_rank1d", 2));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_rank1d", 3));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_series", 1));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_series", 2));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_series", 3));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_series", 4));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_shift", 1));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_shift", 2));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_shift", 3));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_series_values", 1));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_series_values", 2));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_from_columns", 1));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_from_columns", 2));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_xs_rank", 1));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_xs_rank", 2));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_xs_rank", 3));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_join", 3));
		Assert.isTrue(musescript.vm.VmPdEligibility.arityOk("pd_join", 4));
		Assert.isFalse(musescript.vm.VmPdEligibility.arityOk("pd_join", 5));
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
