package musescript.ew;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.ProjectionProvider;
import musescript.evo.CorpusSeed;
import musescript.evo.StrategyGenome;

/**
 * EW profit benchmark (FIDELITY_AND_BENCHMARK_PLAN.md Phase 0, Q5).
 *
 * "How much can we realistically profit from whatever predictive edge the fans grant?" — the honest
 * bottom line. Runs the canonical EW-consuming strategies (CorpusSeed host seeds: p50-vs-close,
 * tight-spread, low-entropy, price-vs-invalidate) through the SAME Fitness/BacktestEngine + turnover
 * cost model the evolution uses (default 20 bps), on a real held tape, and compares to buy-and-hold.
 *
 * No hand-rolled PnL: reusing `Fitness.evaluate` keeps the cost accounting identical to production and
 * sidesteps the turnover-undercharge class of bug. `Fitness.projectionProvider` (auto-bind) rebuilds a
 * fresh streaming host per genome over the real bars, so decoration is PIT-causal.
 *
 * Honest by design: if no EW strategy beats buy-and-hold net of costs, this prints that plainly.
 *
 * ```
 * haxe build-ew-profit.hxml
 * node build/js/ew-profit.js --tape corpus/tapes/spy_oos_2022_2026.csv --host lattice --cost-bps 20
 * ```
 */
class EwProfitCli {
	static function main() {
		var tapePath = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var costBps = argFloat("--cost-bps", 20);
		var startCapital = argFloat("--start-capital", 100000);
		var hostKind = argStr("--host", "lattice");

		var bars = loadBars(tapePath);
		var provider = ProjectionProvider.forEvoHost(false); // auto-bind host per genome, no logs
		var prev = Fitness.projectionProvider;
		Fitness.projectionProvider = provider;

		// Buy-and-hold null (same cost model).
		var bh = Fitness.evaluate(buyHold(), bars, "js", false, costBps, startCapital);

		// EW-consuming strategies.
		var seeds = CorpusSeed.seedFromEwHostProjection(hostKind);
		var rows:Array<{name:String, r:FitnessResult}> = [];
		for (g in seeds) {
			provider.invalidate();
			rows.push({ name: g.name, r: Fitness.evaluate(g, bars, "js", false, costBps, startCapital) });
		}
		Fitness.projectionProvider = prev;

		var bhRet = netReturn(bh, startCapital);

		Sys.println("=== EW profit benchmark (net of costs) ===");
		Sys.println('tape=$tapePath bars=${bars.length} host=$hostKind costBps=$costBps startCapital=$startCapital');
		Sys.println("");
		Sys.println(pad("strategy", 34) + pad("sharpe", 9) + pad("netRet%", 10) + pad("trades", 8) + "flags");
		Sys.println(row("BUY_AND_HOLD (null)", bh, startCapital));
		Sys.println(sep());

		var beatBoth = 0;
		var bestName = "-";
		var bestSharpe = Fitness.NEG_INF;
		for (rr in rows) {
			Sys.println(row(rr.name, rr.r, startCapital));
			if (rr.r.ok && rr.r.sharpe > bestSharpe) {
				bestSharpe = rr.r.sharpe;
				bestName = rr.name;
			}
			if (rr.r.ok && rr.r.sharpe > (bh.ok ? bh.sharpe : 0) && netReturn(rr.r, startCapital) > bhRet)
				beatBoth++;
		}

		Sys.println("");
		Sys.println('best EW by Sharpe: $bestName (${fmt(bestSharpe, 3)})   vs buy&hold Sharpe ${fmt(bh.ok ? bh.sharpe : Math.NaN, 3)}');
		if (beatBoth == 0)
			Sys.println("VERDICT: NO-GO — no EW strategy beat buy-and-hold on BOTH Sharpe and net return after costs.");
		else
			Sys.println('VERDICT: $beatBoth EW strateg${beatBoth == 1 ? "y" : "ies"} beat buy-and-hold on both Sharpe and net return — worth a closer, pre-registered look.');
		Sys.println("EW_PROFIT_OK");
	}

	static function netReturn(r:FitnessResult, startCapital:Float):Float {
		if (!r.ok || !(startCapital > 0)) return Math.NaN;
		return (r.finalEquity / startCapital - 1.0) * 100.0;
	}

	static function row(name:String, r:FitnessResult, startCapital:Float):String {
		var flags = [];
		if (!r.ok) flags.push("FAILED");
		if (r.bankrupt) flags.push("BANKRUPT");
		var s = r.ok ? fmt(r.sharpe, 3) : "n/a";
		var nr = r.ok ? fmt(netReturn(r, startCapital), 2) : "n/a";
		var tr = r.ok ? Std.string(r.trades) : "-";
		return pad(name, 34) + pad(s, 9) + pad(nr, 10) + pad(tr, 8) + flags.join(",");
	}

	static function buyHold():StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)), // always true
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)), // always false
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)), // never exits
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "buy_and_hold", lineage: [], seedOrigin: null
		};
	}

	static function loadBars(path:String):Array<Bar> {
		var candidates = [path, "corpus/tapes/spy_oos_2022_2026.csv"];
		for (p in candidates)
			if (sys.FileSystem.exists(p)) return OhlcvCsv.parse(sys.io.File.getContent(p));
		throw 'no tape found (tried $path)';
	}

	static function sep():String return "-------------------------------------------------------------------------";

	static function pad(s:String, w:Int):String {
		var out = s;
		while (out.length < w) out += " ";
		return out;
	}

	static function fmt(x:Float, n:Int):String {
		if (Math.isNaN(x) || !Math.isFinite(x)) return "n/a";
		var m = Math.pow(10, n);
		return Std.string(Math.ffloor(x * m + 0.5) / m);
	}

	static function argStr(name:String, def:Null<String>):Null<String> {
		var args = Sys.args();
		var i = 0;
		while (i < args.length - 1) {
			if (args[i] == name) return args[i + 1];
			i++;
		}
		return def;
	}

	static function argFloat(name:String, def:Float):Float {
		var v = argStr(name, null);
		return v == null ? def : Std.parseFloat(v);
	}
}
