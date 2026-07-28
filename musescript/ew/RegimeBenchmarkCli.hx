package musescript.ew;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.evo.ProjectionScore;

/**
 * Regime-target benchmark — scores the RegimeForecastHost on the target a trivial null CAN'T win:
 * forecasting FORWARD realized volatility (what "what regime are we in" is supposed to buy you), not
 * the price-band capture that a ±1-ATR null trivially owns.
 *
 * The honest baseline here is PERSISTENCE: trailing realized vol. Volatility is strongly
 * autocorrelated, so beating "tomorrow's vol ≈ today's vol" is the real bar — the vol-forecasting
 * analogue of the capture null. If the regime host's predicted spread doesn't rank-correlate with
 * realized forward vol BETTER than (or with genuinely different information than) persistence, regime
 * adds nothing. Leakage-free: cloud frozen at t (data ≤ t), realized vol from bars > t.
 *
 * ```
 * haxe build-regime-benchmark.hxml
 * node build/js/regime-benchmark.js --tape data/real/nvda.csv --horizon 15 --anchor-step 10
 * ```
 */
class RegimeBenchmarkCli {
	static function main() {
		var tapePath = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var horizon = argInt("--horizon", 15);
		var step = argInt("--anchor-step", 10);
		var warmup = argInt("--warmup", 180);
		var k = argInt("--k", 2);
		var window = argInt("--window", 140);
		var steps = argInt("--steps", 700);
		var burnIn = argInt("--burn", 250);
		var nPaths = argInt("--paths", 80);

		var bars = loadBars(tapePath);
		if (bars.length < warmup + horizon + 20) {
			Sys.println('tape too short (${bars.length})');
			Sys.exit(1);
		}

		var host = new RegimeForecastHost(7, k, horizon, window, steps, burnIn, nPaths, 0.97);

		var predVol:Array<Float> = [];   // host predicted vol proxy (band spread / price)
		var trailVol:Array<Float> = [];  // persistence null (trailing realized vol)
		var realVol:Array<Float> = [];   // realized FORWARD vol (the target)
		var labels:Array<Float> = [];    // host regime label (1=calm … k=volatile)

		var t = 0;
		while (t < bars.length) {
			host.onBar(bars[t], t);
			var anchor = t >= warmup && (t - warmup) % step == 0 && t + horizon < bars.length;
			if (anchor) {
				var c = host.cloudAt(t);
				if (c.samples > 0 && Math.isFinite(c.spread) && bars[t].close > 0) {
					var rv = realizedVol(bars, t + 1, horizon);
					var tv = realizedVol(bars, t - horizon + 1, horizon);
					if (finite(rv) && finite(tv)) {
						predVol.push(c.spread / bars[t].close);
						trailVol.push(tv);
						realVol.push(rv);
						labels.push(c.labelCode);
					}
				}
			}
			t++;
		}

		var icHost = ProjectionScore.rankIC(predVol, realVol);
		var icNull = ProjectionScore.rankIC(trailVol, realVol);

		// ---- TRANSITION target: forecast the CHANGE in vol, which persistence can't (it predicts 0) ----
		var n = realVol.length;
		var predChange:Array<Float> = [];
		var realChange:Array<Float> = [];
		var labelChange:Array<Float> = [];
		for (i in 0...n) {
			predChange.push(predVol[i] - trailVol[i]);      // host's anticipated deviation from trailing
			realChange.push(realVol[i] - trailVol[i]);      // realized deviation from trailing
			labelChange.push(labels[i]);                    // regime label as an ordinal change signal
		}
		var icChange = ProjectionScore.rankIC(predChange, realChange);   // THE transition number
		var icLabelChange = ProjectionScore.rankIC(labelChange, realChange);

		// Event lift: when the regime FLIPS calm→volatile between anchors, is a vol EXPANSION
		// (realVol > 1.25×trailVol) more likely than the base rate? Persistence can't call this at all.
		var expBase = 0;
		for (i in 0...n) if (realVol[i] > 1.25 * trailVol[i]) expBase++;
		var baseRate = n > 0 ? expBase / n : Math.NaN;
		var flips = 0;
		var flipExp = 0;
		for (i in 1...n) {
			var flippedUp = labels[i] > labels[i - 1]; // moved to a more-volatile regime
			if (flippedUp) {
				flips++;
				if (realVol[i] > 1.25 * trailVol[i]) flipExp++;
			}
		}
		var flipRate = flips > 0 ? flipExp / flips : Math.NaN;
		var lift = (finite(baseRate) && baseRate > 0 && finite(flipRate)) ? flipRate / baseRate : Math.NaN;

		// regime discrimination: mean realized forward vol grouped by predicted regime label
		var sumByK = [for (_ in 0...k + 1) 0.0];
		var cntByK = [for (_ in 0...k + 1) 0];
		for (i in 0...labels.length) {
			var lc = Std.int(labels[i]);
			if (lc >= 1 && lc <= k) { sumByK[lc] += realVol[i]; cntByK[lc]++; }
		}

		Sys.println("=== Regime-target benchmark (forecast FORWARD realized vol) ===");
		Sys.println('tape=$tapePath bars=${bars.length} K=$k horizon=$horizon step=$step window=$window steps=$steps');
		Sys.println('scored anchors=${realVol.length}');
		Sys.println("");
		Sys.println('rank-IC  regime host (predicted spread → realized vol) = ${fmt(icHost, 4)}');
		Sys.println('rank-IC  PERSISTENCE null (trailing vol → realized vol) = ${fmt(icNull, 4)}');
		Sys.println('         Δ (host − null) = ${fmt(icHost - icNull, 4)}');
		Sys.println("");
		Sys.println("regime discrimination — mean realized forward vol by predicted regime:");
		for (kk in 1...k + 1) {
			var mean = cntByK[kk] > 0 ? sumByK[kk] / cntByK[kk] : Math.NaN;
			var tag = kk == 1 ? "calmest" : (kk == k ? "most volatile" : "mid");
			Sys.println('   regime $kk ($tag): mean fwd vol = ${fmt(mean, 5)}  (n=${cntByK[kk]})');
		}
		Sys.println("");
		Sys.println("--- TRANSITION target (vol CHANGE — persistence scores 0 here by construction) ---");
		Sys.println('rank-IC  host predicted-change → realized-change = ${fmt(icChange, 4)}');
		Sys.println('rank-IC  regime label → realized vol-change      = ${fmt(icLabelChange, 4)}');
		Sys.println('expansion base rate = ${pct(baseRate)}   |   after regime flips up = ${pct(flipRate)} (n=$flips)   lift = ${fmt(lift, 2)}×');
		Sys.println("");

		var monotone = cntByK[k] > 0 && cntByK[1] > 0 && (sumByK[k] / cntByK[k]) > (sumByK[1] / cntByK[1]);
		var levelSkill = monotone && icHost > 0.05;
		var levelBeatsNull = icHost > icNull + 0.02;
		var transitionSkill = (icChange > 0.05 || (finite(lift) && lift > 1.15));

		if (transitionSkill)
			Sys.println("VERDICT: regime PREDICTS vol transitions persistence can't — a real, non-redundant edge. PURSUE.");
		else if (levelBeatsNull && levelSkill)
			Sys.println("VERDICT: regime beats persistence on vol LEVEL — worth pursuing.");
		else if (levelSkill)
			Sys.println("VERDICT: regime discriminates vol (real) but is REDUNDANT with persistence, and shows no transition edge.");
		else
			Sys.println("VERDICT: NO-GO — regime adds nothing over persistence.");
		Sys.println("REGIME_BENCHMARK_OK");
	}

	static function realizedVol(bars:Array<Bar>, start:Int, h:Int):Float {
		if (start < 1 || start + h > bars.length) return Math.NaN;
		var rets:Array<Float> = [];
		for (i in start...start + h) {
			var pc = bars[i - 1].close;
			var c = bars[i].close;
			if (pc > 0 && c > 0) rets.push(Math.log(c / pc));
		}
		if (rets.length < 2) return Math.NaN;
		var m = 0.0;
		for (r in rets) m += r;
		m /= rets.length;
		var v = 0.0;
		for (r in rets) v += (r - m) * (r - m);
		return Math.sqrt(v / (rets.length - 1));
	}

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);

	static function pct(x:Float):String
		return finite(x) ? fmt(x * 100, 1) + "%" : "n/a";

	static function loadBars(path:String):Array<Bar> {
		if (sys.FileSystem.exists(path)) return OhlcvCsv.parse(sys.io.File.getContent(path));
		throw 'no tape at $path';
	}

	static function fmt(x:Float, n:Int):String {
		if (Math.isNaN(x) || !Math.isFinite(x)) return "n/a";
		var m = Math.pow(10, n);
		return Std.string(Math.ffloor(x * m + 0.5) / m);
	}

	static function argStr(name:String, def:Null<String>):Null<String> {
		var a = Sys.args();
		var i = 0;
		while (i < a.length - 1) { if (a[i] == name) return a[i + 1]; i++; }
		return def;
	}

	static function argInt(name:String, def:Int):Int {
		var v = argStr(name, null);
		return v == null ? def : Std.parseInt(v);
	}
}
