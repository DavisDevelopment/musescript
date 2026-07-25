package musescript.scratch;

import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.evo.CorpusSeed;
import musescript.evo.Expand;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;

/**
 * Throwaway diagnostic: reproduce the nma-verify mismatch for one corpus genome on the real
 * smoke tape, per-bar. Run on node for print-debug iteration speed.
 */
class NmaParityProbe {
	static function main() {
		var src = sys.io.File.getContent("examples/strategy-tournament/agents/agent-06/round-07/_probe_don5.ms");
		var allowed = new Map<String, Bool>();
		for (name in ["sma", "ema", "rsi", "atr", "wma", "rma", "stdev", "highest", "lowest", "mom", "roc", "change"])
			allowed.set(name, true);
		var t = CorpusSeed.translateSource(src, allowed);
		if (t.genome == null) {
			Sys.println('translate failed: ${t.error}');
			return;
		}
		var g = t.genome;
		Sys.println('name=${g.name}');
		Sys.println('entryLong=${g.entryLong}');
		Sys.println('entryShort=${g.entryShort}');
		Sys.println('exitLong=${g.exitLong}');
		Sys.println('exitShort=${g.exitShort}');
		Sys.println('size=${g.size} params=${g.params}');
		Sys.println('--- Expand ---');
		Sys.println(Expand.expand(g));

		var bars:Array<Bar> = OhlcvCsv.parse(sys.io.File.getContent("build/graal/smoke_spy_320.csv"));
		// IS slice: 219 bars (matches the CorpusEvoRun fitness window).
		var isBars = bars.slice(0, 219);
		Sys.println('bars=${bars.length} isSlice=${isBars.length}');

		Fitness.preferNma = false;
		var compiled = Fitness.evaluate(g, isBars, "js", false, 20);
		Sys.println('compiled[${compiled.backend}]: ok=${compiled.ok} trades=${compiled.trades} eq=${compiled.finalEquity}');
		var interp = Fitness.evaluate(g, isBars, "interp", false, 20);
		Sys.println('interp[${interp.backend}]: ok=${interp.ok} trades=${interp.trades} eq=${interp.finalEquity}');

		Fitness.preferNma = true;
		var nma = Fitness.evaluate(g, isBars, "js", false, 20);
		Fitness.preferNma = false;
		Sys.println('nma[${nma.backend}]: ok=${nma.ok} trades=${nma.trades} eq=${nma.finalEquity}');

		var fa:Array<Dynamic> = nma.fills != null ? nma.fills : [];
		var fb:Array<Dynamic> = compiled.fills != null ? compiled.fills : [];
		Sys.println('nmaFills[0..3]=${fa.slice(0, 4)}');
		Sys.println('compiledFills[0..3]=${fb.slice(0, 4)}');

		// Columnar exit vs compiled: dump close/ema/exitBool for bars 0..7 so the first
		// diverging exit cell is visible (ProbeDon5: NMA flat@1 vs compiled flat@2).
		try {
			var prep = musescript.evo.nma.NmaFitness.prepare(g, isBars);
			if (prep != null) {
				var xL = musescript.evo.nma.NmaEval.evalBool(prep.nma.exitLong, prep.ctx);
				var eL = musescript.evo.nma.NmaEval.evalBool(prep.nma.entryLong, prep.ctx);
				Sys.println('--- NMA signal columns bars 0..7 ---');
				for (i in 0...8) {
					var c = isBars[i].close;
					Sys.println('  bar$i close=$c entry=${eL.at(i)} exit=${xL.at(i)}');
				}
			} else Sys.println('NMA prepare returned null (unsupported genome)');
		} catch (e:Dynamic) {
			Sys.println('NMA column dump failed: $e');
		}

		// Inject per-bar exit diagnostics into Expand source and re-run.
		var expSrc = Expand.expand(g);
		var injected = StringTools.replace(expSrc,
			"onBar {",
			"onBar {\n    log(close)\n    log(ema(\"close\", 13))\n    log(close - ema(\"close\", 13))\n    log(close < ema(\"close\", 13))\n    log(position())");
		Sys.println('--- Expand+diag ---');
		var prog2 = new musescript.parse.MuseParser().parse(injected, "<diag>");
		var ex2 = musescript.compile.MuseCompiler.compileEx(prog2, { target: "js", strict: false });
		var h2 = new musescript.harness.HarnessContext();
		h2.orders.book.slippageBps = 20;
		h2.feed = new musescript.harness.BarFeed(isBars);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var res2:Dynamic = ex2.fn(h2);
		Sys.println('diag backend=${ex2.backend} trades=${Reflect.field(res2, "trades")}');
		var logs2:Array<Dynamic> = h2.logs;
		for (i in 0...8) {
			var c = logs2[i * 5];
			var e = logs2[i * 5 + 1];
			var diff = logs2[i * 5 + 2];
			var exitB = logs2[i * 5 + 3];
			var pos = logs2[i * 5 + 4];
			Sys.println('  bar$i close=${Std.string(c)} ema=${Std.string(e)} diff=${Std.string(diff)} exitCond=${Std.string(exitB)} pos=${Std.string(pos)}');
		}
		var fills2:Array<Dynamic> = h2.orders.fills;
		Sys.println('diagFills[0..4]=${fills2.slice(0, 4)}');

		// Direct TradeBuiltins double-call: does the 2nd ema() in one bar match the 1st?
		var h3 = new musescript.harness.HarnessContext();
		var closes = [for (b in isBars) b.close];
		h3.series.set("close", []);
		h3.series.set("high", []);
		h3.series.set("low", []);
		h3.series.set("open", []);
		h3.series.set("volume", []);
		Sys.println('--- TradeBuiltins ema double-call bars 0..3 ---');
		for (i in 0...4) {
			h3.series.get("close").push(isBars[i].close);
			h3.series.get("high").push(isBars[i].high);
			h3.series.get("low").push(isBars[i].low);
			h3.series.get("open").push(isBars[i].open);
			h3.series.get("volume").push(isBars[i].volume);
			h3.currentBar = isBars[i];
			musescript.builtins.TradeBuiltins.beginBar();
			h3.indCols.beginBar();
			var e1 = musescript.builtins.TradeBuiltins.ema(h3, "close", 13);
			var e2 = musescript.builtins.TradeBuiltins.ema(h3, "close", 13);
			Sys.println('  bar$i close=${isBars[i].close} ema1=$e1 ema2=$e2 match=${e1 == e2} c_lt_e1=${isBars[i].close < e1}');
		}

		// Per-bar value probe through the full compile pipeline (whatever backend this target
		// resolves to). Logs close and ema so the first diverging VALUE is visible directly.
		var source = 'strategy P {\n  onBar {\n    log(close)\n    log(ema("close", 13))\n    when ((high >= highest("high", 5))) && position() <= 0: { long(1) }\n    when ((0 > 1)) && position() >= 0: { short(1) }\n    when ((close < ema("close", 13))) || ((close < ema("close", 13))): { flat() }\n  }\n}';
		var prog = new musescript.parse.MuseParser().parse(source, "<probe>");
		var ex = musescript.compile.MuseCompiler.compileEx(prog, { target: "js", strict: false });
		var h = new musescript.harness.HarnessContext();
		h.orders.book.slippageBps = 20;
		h.feed = new musescript.harness.BarFeed(isBars);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var res:Dynamic = ex.fn(h);
		Sys.println('probe backend=${ex.backend} trades=${Reflect.field(res, "trades")}');
		var logs:Array<Dynamic> = h.logs;
		for (i in 0...8) {
			var close = logs[i * 2];
			var ema = logs[i * 2 + 1];
			Sys.println('  bar$i close=${Std.string(close)} ema13=${Std.string(ema)}');
		}
	}
}
