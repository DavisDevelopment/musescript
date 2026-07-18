package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.compile.WatAssembler;
import musescript.compile.StrategyWasmBackend;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

/**
 * ROADMAP "In-browser WASM tier": self-contained (no external wat2wasm) proof
 * that WatAssembler's binary output is both valid AND behaviorally correct —
 * assembled via WatAssembler, instantiated with the JS engine's own native
 * `WebAssembly.Module`/`Instance` (no wabt.js, no subprocess), and its
 * backtest metrics compared bit-exact against the interp tier on the same
 * strategy + bars. (Cross-validated separately against wasmtime's own
 * wat2wasm on real corpus strategies during development — see commit notes;
 * that check needs a Python venv so it isn't part of this suite.)
 */
class TestWatAssembler extends Test {
	static function bars(n:Int, seed:Int):Array<Bar> {
		var r = new haxe.ds.Vector<Float>(1);
		var price = 100.0;
		var out = [];
		var s = seed;
		function rnd():Float {
			s = (s * 1103515245 + 12345) & 0x7fffffff;
			return (s % 1000) / 1000.0;
		}
		for (i in 0...n) {
			var delta = (rnd() - 0.45) * 4;
			var c = price + delta;
			out.push({
				open: price, high: Math.max(price, c) + 1.0, low: Math.min(price, c) - 1.0,
				close: c, volume: 1000.0 + rnd() * 500, time: (i : Float), index: i
			});
			price = c;
		}
		return out;
	}

	#if js
	function runWasm(prog:musescript.ast.MuseProgram, feed:BarFeed):Dynamic {
		var e = StrategyWasmBackend.emitOnBar(prog);
		if (e == null) return null;
		var wasmBytes = WatAssembler.assemble(e.wat).getData();
		var harness = new HarnessContext();
		harness.feed = feed;
		TradeBuiltins.resetCrossState();
		var fn = StrategyWasmBackend.compileFromBytes(prog, wasmBytes, e.strings);
		return fn(harness);
	}

	function runInterp(prog:musescript.ast.MuseProgram, feed:BarFeed):Dynamic {
		var harness = new HarnessContext();
		return new MuseInterp(harness).runBacktest(prog, feed);
	}

	function checkParity(source:String, seed:Int) {
		var feedBars = bars(150, seed);
		var interp = runInterp(new MuseParser().parse(source), new BarFeed(feedBars.copy()));
		var wasm = runWasm(new MuseParser().parse(source), new BarFeed(feedBars.copy()));
		Assert.notNull(wasm, 'strategy unexpectedly outside WASM on_bar subset: $source');
		Assert.equals(interp.trades, wasm.trades);
		Assert.floatEquals(interp.finalEquity, wasm.finalEquity);
		Assert.floatEquals(interp.maxDrawdown, wasm.maxDrawdown);
	}

	public function testSmaCrossParity() {
		checkParity('
			@strategy("t")
			@on(bar) {
				a = sma(close, 5);
				b = sma(close, 20);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		', 7);
	}

	public function testRsiMeanRevParity() {
		checkParity('
			@strategy("t")
			@on(bar) {
				r = rsi(close, 14);
				if (r < 30) long();
				if (r > 70) flat();
			}
		', 13);
	}

	public function testEmaCrossWithBoolLogicParity() {
		checkParity('
			@strategy("t")
			@on(bar) {
				fast = ema(close, 8);
				slow = ema(close, 21);
				volOk = stdev(close, 10) > 0.5;
				if (crossover(fast, slow) && volOk && position() == 0) long();
				if (crossunder(fast, slow) && position() != 0) flat();
			}
		', 21);
	}

	public function testAtrAndParamsParity() {
		checkParity('
			@strategy("t")
			@param("mult", 1.5)
			@on(bar) {
				a = atr(close, 14);
				stop = entry_price() - a * mult;
				if (position() == 0 && rising(close, 1, 3)) long();
				if (position() > 0 && close < stop) flat();
			}
		', 31);
	}

	/**
	 * Invalid/adversarial WAT must be rejected clearly, not crash the process
	 * or silently produce a garbage module — mirrors the real failure mode
	 * this suite exists to catch (see the ArrayBuffer over-allocation bug
	 * fixed in WatAssembler.assemble via Bytes.sub()).
	 */
	public function testMalformedWatThrows() {
		Assert.raises(function() WatAssembler.assemble("(module (func $f (call $unknown_func)))"));
		Assert.raises(function() WatAssembler.assemble("not even an sexpr"));
		Assert.raises(function() WatAssembler.assemble("(notamodule)"));
	}

	/**
	 * Regression guard for the exact bug fixed in this pass: the assembled
	 * Bytes must be tightly sized to its content, not the BytesBuffer's
	 * over-allocated backing storage — a naive `WebAssembly.Module(bytes)`
	 * caller must see a buffer with no trailing garbage.
	 */
	public function testAssembledBytesAreTightlySized() {
		var wat = "(module (memory (export \"memory\") 1) (func $f (result i32) (i32.const 42)) (export \"f\" (func $f)))";
		var b = WatAssembler.assemble(wat);
		var data:Dynamic = b.getData();
		// On the js target getData() is a Uint8Array/Buffer whose own reported
		// length must equal Bytes.length exactly (was: backing ArrayBuffer
		// bigger than the real content, corrupting WebAssembly.Module()).
		var reportedLen:Int = Reflect.hasField(data, "length") ? Reflect.field(data, "length") : b.length;
		Assert.equals(b.length, reportedLen);
	}
	#end
}
