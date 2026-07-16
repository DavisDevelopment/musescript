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
 * M0 gate — Python-host leg (build-m0-py.hxml). Same MA-cross strategy, same real SPY tape as
 * M0Gate.hx (the JS-host tri-runtime leg), run under the Python host: MuseInterp (host-neutral,
 * cross-checked against the JS host's interp result) and the "wasm" compile target, which on a
 * Python host resolves to StrategyWasmBackend.compilePython (wasmtime), NOT the JS-host WASM path.
 * Reads build/m0_js_host.json (written by M0Gate.hx — run that first) and asserts all 5 numbers
 * (interp_js, js, wasm_js, interp_py, wasm_py) agree within a tight float epsilon. This is the
 * "4th runtime" the general M0 gate result documented as outstanding.
 */
class M0GatePy {
	static function runOn(fn:Dynamic, bars):BacktestResult {
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
		var jsHostPath = "build/m0_js_host.json";
		if (!OhlcvCsv.exists(tapePath)) {
			Sys.println("M0 GATE (py): FAIL — real tape not found at " + tapePath);
			Sys.exit(1);
		}
		if (!sys.FileSystem.exists(jsHostPath)) {
			Sys.println("M0 GATE (py): FAIL — " + jsHostPath + " missing. Run build-m0.hxml (JS-host leg) first.");
			Sys.exit(1);
		}

		var bars = OhlcvCsv.load(tapePath);
		var prog = new MuseParser().parse(source, "m0_gate_py.ms");

		var jsHost:Dynamic = haxe.Json.parse(sys.io.File.getContent(jsHostPath));

		var ri = runInterp(prog, bars);

		var wasmReady = musescript.compile.StrategyWasmBackend.hostReady();
		if (!wasmReady) {
			Sys.println("M0 GATE (py): FAIL — wasmtime not ready on this Python host (check .venv, wat2wasm_cli.py)");
			Sys.exit(1);
		}
		var wasmEx = MuseCompiler.compileEx(prog, { target: "wasm", strict: true });
		var rw = runOn(wasmEx.fn, bars);

		Sys.println("=== MuseScript M0 gate — Python-host leg (interp + wasmtime) on REAL SPY tape ===");
		Sys.println("tape: " + tapePath + "  bars=" + bars.length);
		Sys.println('interp(py)  trades=${ri.trades}  finalEquity=${ri.finalEquity}  sharpe=${ri.sharpe}');
		Sys.println('wasm(py)    trades=${rw.trades}  finalEquity=${rw.finalEquity}  sharpe=${rw.sharpe}  backend=${wasmEx.backend}');
		Sys.println('interp(js, from json)  trades=${jsHost.interp.trades}  finalEquity=${jsHost.interp.finalEquity}  sharpe=${jsHost.interp.sharpe}');
		Sys.println('wasm(js, from json)    trades=${jsHost.wasm.trades}  finalEquity=${jsHost.wasm.finalEquity}  sharpe=${jsHost.wasm.sharpe}  backend=${jsHost.wasm.backend}');

		var eps = 1e-6;
		var allTrades = [ri.trades, rw.trades, (jsHost.interp.trades : Int), (jsHost.wasm.trades : Int), (jsHost.js.trades : Int)];
		var tOk = true;
		for (t in allTrades) if (t != allTrades[0]) tOk = false;

		var eqOk = close(ri.finalEquity, rw.finalEquity, eps)
			&& close(ri.finalEquity, (jsHost.interp.finalEquity : Float), eps)
			&& close(rw.finalEquity, (jsHost.wasm.finalEquity : Float), eps)
			&& close((jsHost.interp.finalEquity : Float), (jsHost.js.finalEquity : Float), eps);

		var shOk = close(ri.sharpe, rw.sharpe, eps)
			&& close(ri.sharpe, (jsHost.interp.sharpe : Float), eps)
			&& close(rw.sharpe, (jsHost.wasm.sharpe : Float), eps);

		if (tOk && eqOk && shOk) {
			Sys.println("M0 GATE (py): PASS — interp(py)/wasm(py)/interp(js)/wasm(js)/js(js) all identical on real tape");
			Sys.exit(0);
		} else {
			Sys.println("M0 GATE (py): FAIL — tradesOk=" + tOk + " eqOk=" + eqOk + " shOk=" + shOk);
			Sys.exit(1);
		}
	}
}
