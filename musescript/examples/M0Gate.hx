package musescript.examples;

import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.BacktestResult;
import musescript.harness.OhlcvCsv;
import musescript.builtins.TradeBuiltins;

/**
 * M0 gate — the MuseScript app-integration feasibility proof (MUSE_APP_INTEGRATION_PLAN.md §4).
 * ONE MA-cross strategy, run on the REAL SPY tape (data/real/spy.csv, 8419 daily bars 1993-2026)
 * across every JS-host runtime the compiler emits — interpreter, compiled JS, compiled WASM on_bar —
 * and asserts the backtest result is IDENTICAL across all three (trades exact, finalEquity/sharpe
 * within a tight float epsilon). If this fails, the "one strategy, one ABI, many runtimes" premise
 * the whole integration plan rests on is broken. The Python-host leg (interp + wasmtime WASM) is
 * the 4th runtime and runs from the build-m0-py target (M0GatePy.hx) separately — this file is the
 * JS-host tri-runtime leg, and it writes its results to build/m0_js_host.json so M0GatePy.hx can
 * do the full 4-way comparison without re-deriving the JS-host numbers.
 */
class M0Gate {
	static function runOn(prog, fn:Dynamic, bars):BacktestResult {
		TradeBuiltins.resetCrossState();
		var h = new HarnessContext();
		h.params.register("fast", 10);
		h.params.register("slow", 30);
		Reflect.setField(h, "feed", new BarFeed(bars));
		return cast fn(h);
	}

	static function runInterp(prog, bars):BacktestResult {
		TradeBuiltins.resetCrossState();
		var h = new HarnessContext();
		h.params.register("fast", 10);
		h.params.register("slow", 30);
		return new MuseInterp(h).runBacktest(prog, new BarFeed(bars));
	}

	static function close(a:Float, b:Float, eps:Float):Bool {
		var d = a - b;
		if (d < 0) d = -d;
		return d <= eps;
	}

	static function main() {
		var source = '
		{
			@strategy("m0_ma_cross")
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

		var tapePath = "data/real/spy.csv";
		if (!OhlcvCsv.exists(tapePath)) {
			Sys.println("M0 GATE: FAIL — real tape not found at " + tapePath);
			Sys.exit(1);
		}
		var bars = OhlcvCsv.load(tapePath);
		var prog = new MuseParser().parse(source, "m0_gate.ms");

		var jsEx = MuseCompiler.compileEx(prog, { target: "js", strict: true });
		var wasmEx = MuseCompiler.compileEx(prog, { target: "wasm", strict: true });

		var ri = runInterp(prog, bars);
		var rj = runOn(prog, jsEx.fn, bars);
		var rw = runOn(prog, wasmEx.fn, bars);

		Sys.println("=== MuseScript M0 gate — tri-runtime on REAL SPY tape ===");
		Sys.println("tape: " + tapePath + "  bars=" + bars.length);
		Sys.println('interp   trades=${ri.trades}  finalEquity=${ri.finalEquity}  sharpe=${ri.sharpe}');
		Sys.println('js       trades=${rj.trades}  finalEquity=${rj.finalEquity}  sharpe=${rj.sharpe}  backend=${jsEx.backend}');
		Sys.println('wasm     trades=${rw.trades}  finalEquity=${rw.finalEquity}  sharpe=${rw.sharpe}  backend=${wasmEx.backend}');

		// Trades must match EXACTLY (integer decisions); equity/sharpe within a tight float epsilon.
		var eps = 1e-6;
		var tradesOk = (ri.trades == rj.trades) && (rj.trades == rw.trades);
		var eqOk = close(ri.finalEquity, rj.finalEquity, eps) && close(rj.finalEquity, rw.finalEquity, eps);
		var shOk = close(ri.sharpe, rj.sharpe, eps) && close(rj.sharpe, rw.sharpe, eps);

		var maxEqDelta = Math.max(Math.abs(ri.finalEquity - rj.finalEquity), Math.abs(rj.finalEquity - rw.finalEquity));
		Sys.println('max finalEquity delta across runtimes: ${maxEqDelta}');

		// Persist for M0GatePy.hx (Python-host leg) to cross-check against.
		var out = {
			interp: { trades: ri.trades, finalEquity: ri.finalEquity, sharpe: ri.sharpe },
			js: { trades: rj.trades, finalEquity: rj.finalEquity, sharpe: rj.sharpe, backend: jsEx.backend },
			wasm: { trades: rw.trades, finalEquity: rw.finalEquity, sharpe: rw.sharpe, backend: wasmEx.backend },
		};
		sys.io.File.saveContent("build/m0_js_host.json", haxe.Json.stringify(out, null, "  "));
		Sys.println("wrote build/m0_js_host.json");

		if (tradesOk && eqOk && shOk) {
			Sys.println("M0 GATE: PASS — interp/js/wasm identical on real tape (trades exact, equity/sharpe delta <= " + eps + ")");
			Sys.exit(0);
		} else {
			Sys.println("M0 GATE: FAIL — runtimes diverged (tradesOk=" + tradesOk + " eqOk=" + eqOk + " shOk=" + shOk + ")");
			Sys.exit(1);
		}
	}
}
