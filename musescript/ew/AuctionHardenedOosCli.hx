package musescript.ew;

import musescript.harness.Bar;
import musescript.harness.Metrics;
import musescript.harness.OhlcvCsv;
import musescript.harness.TapeLinter;
import musescript.evo.CorpusSeed;
import musescript.evo.Fitness;
import musescript.evo.ProjectionProvider;
import musescript.evo.StrategyGenome;
import musescript.evo.rigor.OosVerdict;
import musescript.evo.rigor.PurgeEmbargo;
import musescript.ew.auction.AuctionForecastHost;
import musescript.ew.auction.VolumeProfile;
import musescript.evo.ProjectionScore;

/**
 * Hardened host + tape OOS path — Bucket H lint + A1/A3/A4/A5 OOS gates + B4 seed-median.
 *
 * Reproduces the "thin-trade pulse" failure mode as an explicit NO-GO, then scores
 * host seeds on a purged OOS split with min-trades / DSR / CI / trials / elite-median.
 *
 * ```
 * haxe build-auction-hardened-oos.hxml
 * node build/js/auction-hardened-oos.js --tape data/real/tsla.csv --host-kind auction --min-trades 20 --n-trials 50
 * node build/js/auction-hardened-oos.js --tape data/real/tsla.csv --host-kind lattice --n-trials 50
 * node build/js/auction-hardened-oos.js --tape data/real/tsla.csv --host-kind regime --n-trials 50
 * ```
 */
class AuctionHardenedOosCli {
	static function main() {
		var tapePath = argStr("--tape", "data/real/tsla.csv");
		var hostKind = argStr("--host-kind", "auction");
		var minTrades = argInt("--min-trades", 20);
		var nTrials = argInt("--n-trials", 50);
		var oosFrac = argFloat("--oos-frac", 0.25);
		var embargo = argInt("--embargo", 20);
		var costBps = argFloat("--cost-bps", 5.0);
		var horizon = argInt("--horizon", 10);
		var warmup = argInt("--warmup", HostWarmup.AUCTION_BENCHMARK);
		if (hostKind == "regime") warmup = HostWarmup.REGIME_BENCHMARK;
		else if (hostKind == "lattice" || hostKind == "mcmc") warmup = HostWarmup.EW_LATTICE_BENCHMARK;

		Sys.println('=== Hardened OOS host=$hostKind (min-trades / DSR / CI / trials / seed-median) ===');
		Sys.println('tape=$tapePath minTrades=$minTrades nTrials=$nTrials oosFrac=$oosFrac embargo=$embargo costBps=$costBps');

		if (!OhlcvCsv.exists(tapePath)) {
			Sys.println('BLOCKER: tape not found at $tapePath');
			Sys.exit(2);
		}
		var bars = OhlcvCsv.load(tapePath);
		Sys.println('loaded bars=${bars.length}');

		// ── H: lint ──────────────────────────────────────────────────────────
		var lint = TapeLinter.lint(bars, {allowZeroVolume: true});
		Sys.println(TapeLinter.formatReport(lint, 15));
		if (!TapeLinter.isClean(bars, {allowZeroVolume: true})) {
			Sys.println("VERDICT: NO-GO — tape failed integrity lint (fix data before trusting OOS)");
			Sys.exit(1);
		}

		var split = PurgeEmbargo.split(bars.length, oosFrac, embargo);
		var isBars = bars.slice(0, split.isEnd);
		var oosBars = bars.slice(split.oosStart, bars.length);
		Sys.println('split: IS=${isBars.length} embargo=${split.embargo} OOS=${oosBars.length} (oosStart=${split.oosStart})');
		if (oosBars.length < warmup + horizon + 20) {
			Sys.println('BLOCKER: OOS too short (${oosBars.length}) for warmup=$warmup horizon=$horizon');
			Sys.exit(2);
		}

		// ── Thin-trade pulse control (the prior false-positive pattern) ──────
		Sys.println("");
		Sys.println("--- CONTROL: synthetic 1-trade lucky pulse ---");
		var luckyRets = [for (_ in 0...40) 0.02]; // absurdly good
		var pulse = OosVerdict.evaluate(luckyRets, 1, 0.0, {
			minTrades: minTrades, nTrials: nTrials, nBoot: 100, psrGate: 0.95
		});
		Sys.println(OosVerdict.formatLine(pulse, "thin_pulse"));
		AssertNoGo(pulse, "thin 1-trade pulse must be NO-GO under hardened gate");

		// ── Forecast-host directional benchmark on full tape (context) ───────
		if (hostKind == "auction") {
			Sys.println("");
			Sys.println("--- AuctionForecastHost directional context (full tape, PIT) ---");
			printAuctionDirectional(bars, warmup, horizon);
		}

		// ── Host seeds on OOS with hardened verdict ──────────────────────────
		Sys.println("");
		Sys.println('--- $hostKind host seeds → OOS Fitness + OosVerdict ---');
		Fitness.defaultMinTrades = minTrades;
		Fitness.equityCurveNeeded = true; // OOS DSR/CI need equity curves
		var seeds = CorpusSeed.seedFromEwHostProjection(hostKind);
		Sys.println('seeds=${seeds.length}');

		var provider = ProjectionProvider.forEvoHost(false);
		var anyGo = false;
		var checked = 0;
		var seedMetrics:Array<Float> = [];
		for (g in seeds) {
			var name = g.name != null ? g.name : "?";
			// Bind host columns for evaluate path
			try provider.decorateBars(oosBars, g) catch (_:Dynamic) {}
			var fr = Fitness.evaluate(g, oosBars, "js", false, costBps);
			checked++;
			if (!fr.ok) {
				Sys.println('  $name  EVAL_FAIL');
				continue;
			}
			var rets = fr.equity != null ? Metrics.returnsFromEquity(fr.equity) : [];
			var bh = Fitness.evaluate(buyHold(), oosBars, "js", false, costBps);
			var bhSr = bh.ok ? bh.sharpe : 0.0;
			var v = OosVerdict.evaluate(rets, fr.trades, bhSr, {
				minTrades: minTrades, nTrials: nTrials, nBoot: 150, psrGate: 0.95
			});
			Sys.println(OosVerdict.formatLine(v,
				'$name trades=${fr.trades} sharpe=${fmt(fr.sharpe, 3)} bh=${fmt(bhSr, 3)}'));
			// Only count min-trade-eligible Sharpes in the median (thin pulses must not inflate GO).
			if (fr.trades >= minTrades && Math.isFinite(fr.sharpe)) seedMetrics.push(fr.sharpe);
			if (v.go) anyGo = true;
		}

		Sys.println("");
		var seedV = musescript.evo.rigor.SeedRobustness.verdict(seedMetrics, 0.0);
		Sys.println('[rigor seed-median] n=${seedV.n} median=${fmt(seedV.median, 4)} max=${fmt(seedV.max, 4)}'
			+ ' => ${seedV.go ? "GO" : "NO-GO"} (median across host seeds; not multi-CLI-seed)');
		var univ = musescript.evo.rigor.UniverseRobustness.verdict(
			[{name: tapePath, metric: seedV.median}], 0.0);
		Sys.println('[rigor universe] singleName=${univ.singleName} => ${univ.go ? "GO" : "NO-GO"}'
			+ (univ.singleName ? ' (one tape — not universe-robust)' : ''));

		Sys.println('checked=$checked anyBEATS=${anyGo}');
		if (anyGo && seedV.go)
			Sys.println("VERDICT: BEATS — at least one seed cleared hardened OOS and seed-median > 0.");
		else if (anyGo)
			Sys.println("VERDICT: NO-GO — a seed BEATS but seed-median does not clear 0 (cherry-pick risk).");
		else
			Sys.println("VERDICT: NO-GO — no host seed cleared min-trades/DSR/CI/BH gates on this OOS split.");
		Sys.println("AUCTION_HARDENED_OOS_OK");
	}

	static function AssertNoGo(v:{go:Bool, label:String, reason:String}, msg:String):Void {
		if (v.go) {
			Sys.println('CONTROL FAILED: $msg (got ${v.label}: ${v.reason})');
			Sys.exit(1);
		}
	}

	static function buyHold():StrategyGenome {
		return {
			entryLong: musescript.evo.BoolNode.BCmp(">", musescript.evo.ScalarNode.KConst(1.0), musescript.evo.ScalarNode.KConst(0.0)),
			entryShort: musescript.evo.BoolNode.BCmp(">", musescript.evo.ScalarNode.KConst(0.0), musescript.evo.ScalarNode.KConst(1.0)),
			exitLong: musescript.evo.BoolNode.BCmp(">", musescript.evo.ScalarNode.KConst(0.0), musescript.evo.ScalarNode.KConst(1.0)),
			exitShort: musescript.evo.BoolNode.BCmp(">", musescript.evo.ScalarNode.KConst(0.0), musescript.evo.ScalarNode.KConst(1.0)),
			size: musescript.evo.ScalarNode.KConst(1.0),
			params: [], name: "buy_and_hold", lineage: [], seedOrigin: null
		};
	}

	static function printAuctionDirectional(bars:Array<Bar>, warmup:Int, horizon:Int):Void {
		var host = new AuctionForecastHost(
			VolumeProfile.DEFAULT_WINDOW, VolumeProfile.DEFAULT_BINS,
			VolumeProfile.DEFAULT_VALUE_AREA_PCT, horizon
		);
		var probUp:Array<Float> = [];
		var fwdRet:Array<Float> = [];
		var cls:Array<Int> = [];
		var t = 0;
		while (t < bars.length) {
			host.onBar(bars[t], t);
			if (BenchmarkHarness.isLegalAnchor(t, warmup, 5, horizon, bars.length)) {
				var c = host.cloudAt(t);
				var close = bars[t].close;
				if (c.samples > 0 && close > 0 && t + horizon < bars.length) {
					var fr = bars[t + horizon].close / close - 1.0;
					if (Math.isFinite(fr)) {
						probUp.push(c.probUp);
						fwdRet.push(fr);
						cls.push(close > c.priceHi ? 1 : (close < c.priceLo ? -1 : 0));
					}
				}
			}
			t++;
		}
		var ic = ProjectionScore.rankIC(probUp, fwdRet);
		var drift = mean(fwdRet);
		var up = filterMean(fwdRet, cls, 1);
		var dn = filterMean(fwdRet, cls, -1);
		Sys.println('anchors=${fwdRet.length} rankIC(probUp→fwd)=${fmt(ic, 4)}');
		Sys.println('drift=${bps(drift)}  discUp=${bps(up)}  discDn=${bps(dn)}');
		var upEdge = Math.isFinite(up) && up > drift;
		var dnEdge = Math.isFinite(dn) && dn < drift;
		if (upEdge && dnEdge)
			Sys.println("forecast context: both-sided discovery edge vs drift (not an OOS trade GO)");
		else
			Sys.println("forecast context: NO both-sided discovery edge vs drift");
	}

	static function mean(a:Array<Float>):Float {
		if (a.length == 0) return Math.NaN;
		var s = 0.0; for (x in a) s += x; return s / a.length;
	}

	static function filterMean(v:Array<Float>, c:Array<Int>, want:Int):Float {
		var s = 0.0; var n = 0;
		for (i in 0...v.length) if (c[i] == want) { s += v[i]; n++; }
		return n > 0 ? s / n : Math.NaN;
	}

	static function bps(x:Float):String
		return Math.isFinite(x) ? fmt(x * 10000, 1) : "n/a";

	static function fmt(x:Float, n:Int):String {
		if (!Math.isFinite(x)) return "n/a";
		var m = Math.pow(10, n);
		return Std.string(Math.ffloor(x * m + 0.5) / m);
	}

	static function argStr(name:String, def:Null<String>):Null<String> {
		var a = Sys.args(); var i = 0;
		while (i < a.length - 1) { if (a[i] == name) return a[i + 1]; i++; }
		return def;
	}

	static function argInt(name:String, def:Int):Int {
		var v = argStr(name, null);
		return v == null ? def : Std.parseInt(v);
	}

	static function argFloat(name:String, def:Float):Float {
		var v = argStr(name, null);
		return v == null ? def : Std.parseFloat(v);
	}
}
