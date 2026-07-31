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
		"strategy S { onBar {\n  when close > (open + high) / 2.0: { long(1); }\n  when close < (open + low) / 2.0: { flat(); }\n} }"
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
		var src = "strategy S { onBar {\n  when close > sma(close, 5): { long(1); }\n} }";
		var threw = false;
		try {
			MuseVm.runBacktest(new HarnessContext(), new MuseParser().parse(src), BarFeed.synthetic(64, 3));
		} catch (e:musescript.vm.MuseBytecodeCompiler.VmUnsupported) {
			threw = true;
		}
		Assert.isTrue(threw, "indicator program should throw VmUnsupported, not compile");
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
