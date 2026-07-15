package musescript.examples;

import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.OhlcvCsv;
import musescript.builtins.TradeBuiltins;
import musescript.compile.StrategyWasmEmitter;
import musescript.compile.MathCompiler;

/**
 * Export GraalWasm stress-test artifacts to build/graal/:
 *   polySum.wat            — math-only kernel (same kernel as 07-runtime-stress)
 *   on_bar.wat             — M0 MA-cross strategy on_bar (same strategy as the M0 gate)
 *   on_bar.strings.json    — the emitter's string table (str_id → name) for the host ABI
 *   expected.json          — interpreter ground truth on the real SPY tape for parity checks
 *
 * The Java harness (graal/) consumes these; it never re-derives them. One emitter, many hosts —
 * the same contract the JS/Python/numba runtimes already follow.
 */
class GraalExport {
	static function main() {
		var outDir = "build/graal";
		sys.FileSystem.createDirectory(outDir);

		// ---- 1) math kernel (identical source to RuntimeStress / 07) ----
		var mathSource = '
		{
			function polySum(n) {
				var acc = 0.0;
				var i = 0;
				while (i < n) {
					var x = i * 0.0000001;
					acc = acc + (((x * x) * x) - ((2.0 * x) * x) + x);
					i = i + 1;
				}
				return acc;
			}
		}
		';
		var mathProg = new MuseParser().parse(mathSource, "stress.ms");
		var wat = MathCompiler.emit(mathProg, "polySum", { target: "wasm" });
		if (wat == null) {
			Sys.println("GraalExport: FAIL — polySum did not emit WAT");
			Sys.exit(1);
		}
		sys.io.File.saveContent(outDir + "/polySum.wat", wat);
		Sys.println("wrote " + outDir + "/polySum.wat (" + wat.length + " chars)");

		// ---- 2) strategy on_bar (identical source to M0Gate) ----
		var stratSource = '
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
		var prog = new MuseParser().parse(stratSource, "m0_gate.ms");
		var emitted = new StrategyWasmEmitter().emitOnBar(prog);
		if (emitted == null) {
			Sys.println("GraalExport: FAIL — strategy did not emit WAT");
			Sys.exit(1);
		}
		sys.io.File.saveContent(outDir + "/on_bar.wat", emitted.wat);
		sys.io.File.saveContent(outDir + "/on_bar.strings.json", haxe.Json.stringify(emitted.strings));
		Sys.println("wrote " + outDir + "/on_bar.wat (" + emitted.wat.length + " chars), strings=" + emitted.strings);

		// ---- 3) interpreter ground truth on the real tape ----
		var tapePath = "data/real/spy.csv";
		if (!OhlcvCsv.exists(tapePath)) {
			Sys.println("GraalExport: FAIL — real tape not found at " + tapePath);
			Sys.exit(1);
		}
		var bars = OhlcvCsv.load(tapePath);
		TradeBuiltins.resetCrossState();
		var h = new HarnessContext();
		h.params.register("fast", 10);
		h.params.register("slow", 30);
		var r = new MuseInterp(h).runBacktest(prog, new BarFeed(bars));
		var expected = {
			tape: tapePath,
			bars: bars.length,
			params: { fast: 10, slow: 30 },
			trades: r.trades,
			finalEquity: r.finalEquity,
			sharpe: r.sharpe
		};
		sys.io.File.saveContent(outDir + "/expected.json", haxe.Json.stringify(expected));
		Sys.println("wrote " + outDir + "/expected.json  trades=" + r.trades
			+ " finalEquity=" + r.finalEquity + " sharpe=" + r.sharpe);
		Sys.println("GraalExport: OK");
	}
}
