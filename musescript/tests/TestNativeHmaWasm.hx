package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.StrategyWasmBackend;
import musescript.builtins.TradeBuiltins;

/**
 * Native-WASM `hma` parity. `hma` (Hull MA) was the champion of the corpus-evo runs but until now
 * had no native WASM lowering, so every hma genome fell back to the interp path (StrategyWasmEmitter
 * emitting `call $host_eval`), which GraalWasmHost can't even run -- excluding the single best
 * strategy family from the fast, parallel backend. This asserts the new $hma/$wma_at runtime funcs
 * are (a) actually selected (no host_eval escape) and (b) bar-for-bar identical to the interp `hma`
 * builtin over a real tape, on the SAME in-process WASM host the corpus run uses.
 *
 * Mirrors TestHybridWasm's assertParity convention: reset the module-level cross state before each
 * independent run, and only run the WASM half where a host is available (js/python targets, Node's
 * WebAssembly + the in-tree WAT assembler).
 */
class TestNativeHmaWasm extends Test {
	function assertParity(source:String, feed:BarFeed):Void {
		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(source), feed);

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			TradeBuiltins.resetCrossState();
			var wasmHarness = new HarnessContext();
			Reflect.setField(wasmHarness, "feed", feed);
			var wasmResult = StrategyWasmBackend.compile(new MuseParser().parse(source))(wasmHarness);
			Assert.equals(interpResult.trades, wasmResult.trades, 'hma trade count parity');
			Assert.floatEquals(interpResult.finalEquity, wasmResult.finalEquity, 'hma final-equity parity');
		}
		#end
	}

	/** The exact shape the corpus champion took: price crossing its own Hull MA. Proves hma now
	 * lowers natively (no escape) AND produces identical trades/equity to the interp. */
	public function testHmaCrossoverLowersNativelyAndMatchesInterp() {
		var source = '{
			@strategy("hma_cross")
			@on(bar) {
				var h = hma(close, 8);
				if (crossover(close, h)) long();
				if (crossunder(close, h)) flat();
			}
		}';
		var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $hma") >= 0, "expected a native 'call $hma' in the WAT");
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, "hma must NOT fall back to host_eval anymore");

		assertParity(source, BarFeed.synthetic(400, 13));
	}

	/** DIAGNOSTIC: the exact degenerate CorpusSeed shape -- a `flat()` guarded by a REPEATED
	 * crossover/crossunder in a short-circuiting `||`. This is where the GraalWasm corpus run and
	 * the interp fallback disagreed on the real tape (same trades, but interp held positions for a
	 * 0.76 Sharpe while WASM flattened same-bar for 0). Checks whether the mainstream
	 * MuseInterp.runBacktest vs the WASM backend agree on it -- if this fails, it's a genuine
	 * backend parity violation on repeated-callsite crossover state, not an hma issue. */
	public function testRepeatedCrossInOrFlatShapeParity() {
		var source = '{
			@strategy("degenerate_shape")
			@on(bar) {
				var f = sma(close, 8);
				if (crossover(close, f)) long();
				if (crossunder(close, f)) short();
				if (crossunder(close, f) || crossover(close, f)) flat();
			}
		}';
		var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, "sma shape should lower natively");
		assertParity(source, BarFeed.synthetic(500, 17));
	}

	/** STRESS: a long, large-magnitude, exponentially-trending tape (NVDA-like: $0.05 -> ~$200 over
	 * ~1000 bars with oscillation so crossovers actually fire). Real corpus runs diverged here where
	 * the short synthetic tapes above agreed, so this reproduces the real-data condition in-suite. */
	public function testHmaParityOnLongTrendingLargeMagnitudeTape() {
		var bars:Array<musescript.harness.Bar> = [];
		var base = 0.05;
		for (i in 0...1000) {
			base *= 1.0083; // ~exp growth to ~$200
			var osc = 1.0 + 0.06 * Math.sin(i / 6.0) + 0.02 * Math.sin(i / 1.7);
			var c = base * osc;
			bars.push({open: c, high: c * 1.01, low: c * 0.99, close: c, volume: 1000, time: i, index: i});
		}
		var source = '{
			@strategy("hma_stress")
			@on(bar) {
				var h = hma(close, 8);
				if (crossover(close, h)) long();
				if (crossunder(close, h)) flat();
			}
		}';
		assertParity(source, new BarFeed(bars));
	}

	/** A different window + a shorter tape (exercises the sqrt(period) smoothing and the warmup
	 * boundary where hma is still NaN) -- warmup-region parity is where an off-by-one in the
	 * native $hma vs the streaming Hma.hx would show up as a spurious early trade on one side. */
	public function testHmaOtherWindowParityIncludingWarmup() {
		var source = '{
			@strategy("hma_slow")
			@on(bar) {
				var fast = hma(close, 5);
				var slow = hma(close, 21);
				if (crossover(fast, slow)) long();
				if (crossunder(fast, slow)) flat();
			}
		}';
		var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, 'both hma windows must lower natively');
		assertParity(source, BarFeed.synthetic(120, 29));
	}
}
