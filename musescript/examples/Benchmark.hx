package musescript.examples;

import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.compile.MuseCompiler;
import musescript.compile.JsBackend;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.BacktestResult;
import musescript.builtins.TradeBuiltins;

/**
 * Example 06 — interp vs compiled JS vs strategy WASM on-bar hot path.
 */
class Benchmark {
	static function main() {
		Sys.println("=== MuseScript 06-benchmark ===");

		var source = '
		{
			@strategy("bench_ma")
			@param("fast", 10)
			@param("slow", 30)
			@on(bar) {
				var maFast = sma("close", fast);
				var maSlow = sma("close", slow);
				if (crossover(maFast, maSlow)) long();
				if (crossunder(maFast, maSlow)) flat();
			}
		}
		';

		var prog = new MuseParser().parse(source, "bench.ms");
		var emitted = JsBackend.emitSource(prog);
		Sys.println("emitted JS: " + (emitted != null ? "yes (" + emitted.length + " chars)" : "no (fallback)"));
		var wat = musescript.compile.StrategyWasmBackend.emitWat(prog);
		Sys.println("emitted WAT: " + (wat != null ? "yes (" + wat.length + " chars)" : "no"));

		var bars = 5000;
		var rounds = 3;
		var compiledJs = MuseCompiler.compileEx(prog, { target: "js", strict: true });
		#if js
		var compiledWasm = MuseCompiler.compileEx(prog, { target: "wasm", strict: true });
		#end

		function runInterp():BacktestResult {
			TradeBuiltins.resetCrossState();
			var h = new HarnessContext();
			h.params.register("fast", 10);
			h.params.register("slow", 30);
			return new MuseInterp(h).runBacktest(prog, BarFeed.synthetic(bars, 99));
		}

		function runCompiled(fn:Dynamic):BacktestResult {
			TradeBuiltins.resetCrossState();
			var h = new HarnessContext();
			h.params.register("fast", 10);
			h.params.register("slow", 30);
			Reflect.setField(h, "feed", BarFeed.synthetic(bars, 99));
			return cast fn(h);
		}

		runInterp();
		runCompiled(compiledJs.fn);
		#if js
		runCompiled(compiledWasm.fn);
		#end

		var t0 = haxe.Timer.stamp();
		var ri:BacktestResult = null;
		for (_ in 0...rounds) ri = runInterp();
		var interpMs = (haxe.Timer.stamp() - t0) * 1000 / rounds;

		var t1 = haxe.Timer.stamp();
		var rc:BacktestResult = null;
		for (_ in 0...rounds) rc = runCompiled(compiledJs.fn);
		var jsMs = (haxe.Timer.stamp() - t1) * 1000 / rounds;

		#if js
		var t2 = haxe.Timer.stamp();
		var rw:BacktestResult = null;
		for (_ in 0...rounds) rw = runCompiled(compiledWasm.fn);
		var wasmMs = (haxe.Timer.stamp() - t2) * 1000 / rounds;
		#end

		Sys.println('bars=$bars rounds=$rounds');
		Sys.println('interp:     ${round2(interpMs)} ms  trades=${ri.trades}');
		Sys.println('compile-js: ${round2(jsMs)} ms  trades=${rc.trades}  backend=${compiledJs.backend}');
		#if js
		Sys.println('compile-wasm:${round2(wasmMs)} ms  trades=${rw.trades}  backend=${compiledWasm.backend}');
		#end
		if (jsMs > 0) Sys.println('js speedup: ${round2(interpMs / jsMs)}x');
		#if js
		if (wasmMs > 0) Sys.println('wasm speedup: ${round2(interpMs / wasmMs)}x');
		#end
	}

	static function round2(x:Float):Float {
		return Math.round(x * 100) / 100;
	}
}
