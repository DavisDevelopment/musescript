package musescript.ew;

import musescript.harness.Bar;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.ew.EwProject.EwProjectBand;
import musescript.ew.EwBenchmark;
import musescript.ew.EwBenchmark.AnchorScore;

/**
 * EW forecast-capture benchmark runner (FIDELITY_AND_BENCHMARK_PLAN.md Phase 0, slice 2).
 *
 * Feeds a real OHLCV tape CAUSALLY into a LatticeForecastHost, snapshots the per-interpretation
 * projection fan at an anchor grid, and scores each fan against the realized future with `EwBenchmark`.
 * Prints the five-question table with actual numbers.
 *
 * PIT discipline: at anchor t the host has seen bars ≤ t only (`onBar` fed sequentially); the fan is
 * frozen there and scored against bars > t. Future data touches nothing but the realized-path scorer.
 *
 * ```
 * haxe build-ew-benchmark.hxml
 * node build/js/ew-benchmark.js --tape corpus/tapes/spy_oos_2022_2026.csv --horizon 20 --anchor-step 5
 * ```
 */
class EwBenchmarkCli {
	static function main() {
		var tapePath = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var horizon = argInt("--horizon", 20);
		var step = argInt("--anchor-step", 5);
		var warmup = argInt("--warmup", HostWarmup.EW_LATTICE_BENCHMARK);
		var swing = argFloat("--swing", 0.03);
		var k = argInt("--k", 5);
		var atrN = argInt("--atr", 14);

		var bars = loadBars(tapePath);
		try BenchmarkHarness.requireTapeLength(bars, warmup, horizon, 5) catch (e:Dynamic) {
			Sys.println(Std.string(e));
			Sys.exit(1);
		}

		var graph = new SwingGraph(swing, 64);
		var host = LatticeForecastHost.withGraph(graph, EwPhiParams.current(), k);

		var scores:Array<AnchorScore> = [];
		var crpsNorm:Array<Float> = [];
		var emptyFans = 0;

		var t = 0;
		while (t < bars.length) {
			host.onBar(bars[t], t);
			var isAnchor = BenchmarkHarness.isLegalAnchor(t, warmup, step, 1, bars.length);
			if (isAnchor) {
				var fan = host.ensembleAt(t);
				if (fan.length == 0) emptyFans++;
				var hEnd = t + 1 + horizon;
				if (hEnd > bars.length) hEnd = bars.length;
				var futures = bars.slice(t + 1, hEnd);
				var atr = atrAt(bars, t, atrN);
				scores.push(EwBenchmark.scoreAnchor(fan, futures, atr));

				var mids = [for (b in fan) (b.priceLo + b.priceHi) * 0.5];
				var yBar = t + horizon < bars.length ? t + horizon : bars.length - 1;
				var c = EwBenchmark.crpsEnsemble(mids, bars[yBar].close);
				if (!Math.isNaN(c) && atr > 0) crpsNorm.push(c / atr);
			}
			t++;
		}

		var g = EwBenchmark.aggregate(scores);
		var crpsMed = EwBenchmark.percentile(crpsNorm, 0.5);

		Sys.println("=== EW forecast-capture benchmark ===");
		Sys.println('tape=$tapePath bars=${bars.length} swing=$swing k=$k horizon=$horizon step=$step atr=$atrN');
		Sys.println('anchors=${g.anchors} scoreable=${g.scored} emptyFans=$emptyFans meanRivals=${fmt(g.meanBands, 2)}');
		Sys.println("");
		Sys.println("Q1/Q3  did ANY projection path capture the realized move?");
		Sys.println('        hitRate = ${pct(g.hitRate)}  (of scoreable anchors)');
		Sys.println("Q2     within what margin did the nearest path come? (ATR-normalized; 0 = captured)");
		Sys.println('        margin  p50 = ${fmt(g.marginP50, 3)} ATR   p90 = ${fmt(g.marginP90, 3)} ATR');
		Sys.println('        nearest-band point error p50 = ${fmt(g.pointErrP50, 3)} ATR');
		Sys.println('        ensemble CRPS (ATR-norm) p50 = ${fmt(crpsMed, 3)}');
		Sys.println("");
		Sys.println("Q4 (fitting lift) / Q5 (cost-charged profit): next slices — rerun this grid under a");
		Sys.println("   finetuned phi pack and diff, then trade the fans through BacktestEngine with costs.");

		// A null baseline for honest framing: a naive ±1-ATR band around last close, same anchors.
		var nullScores:Array<AnchorScore> = [];
		t = 0;
		var lastClose = Math.NaN;
		while (t < bars.length) {
			var isAnchor = BenchmarkHarness.isLegalAnchor(t, warmup, step, 1, bars.length);
			if (isAnchor) {
				var atr = atrAt(bars, t, atrN);
				var c = bars[t].close;
				var target = t + horizon < bars.length ? t + horizon : bars.length - 1;
				var nullBand:EwProjectBand = {
					priceLo: c - atr, priceHi: c + atr,
					barLo: target, barHi: target,
					status: musescript.indicators.geom.PivotStatus.Projected,
					kind: "null"
				};
				var hEnd = t + 1 + horizon;
				if (hEnd > bars.length) hEnd = bars.length;
				nullScores.push(EwBenchmark.scoreAnchor([nullBand], bars.slice(t + 1, hEnd), atr));
			}
			t++;
		}
		var ng = EwBenchmark.aggregate(nullScores);
		Sys.println("");
		Sys.println('NULL baseline (±1 ATR band at last close): hitRate = ${pct(ng.hitRate)}  margin p50 = ${fmt(ng.marginP50, 3)} ATR');

		Sys.println("EW_BENCHMARK_OK");
	}

	/** Causal ATR over the `n` bars ending at t (true range mean). NaN if insufficient history. */
	static function atrAt(bars:Array<Bar>, t:Int, n:Int):Float {
		if (t < 1) return Math.NaN;
		var start = t - n + 1;
		if (start < 1) start = 1;
		var sum = 0.0;
		var cnt = 0;
		for (i in start...t + 1) {
			var h = bars[i].high;
			var l = bars[i].low;
			var pc = bars[i - 1].close;
			var tr = h - l;
			var a = Math.abs(h - pc);
			var b = Math.abs(l - pc);
			if (a > tr) tr = a;
			if (b > tr) tr = b;
			sum += tr;
			cnt++;
		}
		return cnt > 0 ? sum / cnt : Math.NaN;
	}

	static function loadBars(path:String):Array<Bar>
		return BenchmarkHarness.loadBars(path, ["corpus/tapes/spy_oos_2022_2026.csv"]);

	static function pct(x:Float):String
		return Math.isNaN(x) ? "n/a" : fmt(x * 100, 1) + "%";

	static function fmt(x:Float, n:Int):String {
		if (Math.isNaN(x)) return "n/a";
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

	static function argInt(name:String, def:Int):Int {
		var v = argStr(name, null);
		return v == null ? def : Std.parseInt(v);
	}

	static function argFloat(name:String, def:Float):Float {
		var v = argStr(name, null);
		return v == null ? def : Std.parseFloat(v);
	}
}
