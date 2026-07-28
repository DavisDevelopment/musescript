package musescript.ew;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.evo.ProjectionScore;
import musescript.ew.auction.AuctionForecastHost;
import musescript.ew.auction.VolumeProfile;

/**
 * Auction / volume-profile breakout benchmark — the "new information" test. The auction host uses
 * VOLUME-at-price (which EW and regime both ignore) to classify balance vs discovery (breakout). The
 * honest question: does a discovery breakout predict forward RETURN DIRECTION beyond plain drift (the
 * null for directional calls)? Leakage-free: value area frozen at t (data ≤ t), return from bars > t.
 *
 * ```
 * haxe build-auction-benchmark.hxml
 * node build/js/auction-benchmark.js --tape data/real/nvda.csv --horizon 10 --anchor-step 5
 * ```
 */
class AuctionBenchmarkCli {
	static function main() {
		var tapePath = argStr("--tape", "corpus/tapes/spy_oos_2022_2026.csv");
		var horizon = argInt("--horizon", 10);
		var step = argInt("--anchor-step", 5);
		var warmup = argInt("--warmup", 120);
		var win = argInt("--window", VolumeProfile.DEFAULT_WINDOW);

		var bars = loadBars(tapePath);
		if (bars.length < warmup + horizon + 20) { Sys.println('tape too short'); Sys.exit(1); }

		var host = new AuctionForecastHost(win, VolumeProfile.DEFAULT_BINS, VolumeProfile.DEFAULT_VALUE_AREA_PCT, horizon);

		var probUp:Array<Float> = [];
		var fwdRet:Array<Float> = [];
		var cls:Array<Int> = []; //  1 discovery-up, -1 discovery-down, 0 balance
		var t = 0;
		while (t < bars.length) {
			host.onBar(bars[t], t);
			var anchor = t >= warmup && (t - warmup) % step == 0 && t + horizon < bars.length;
			if (anchor) {
				var c = host.cloudAt(t);
				var close = bars[t].close;
				if (c.samples > 0 && close > 0 && Math.isFinite(c.priceHi) && Math.isFinite(c.priceLo)) {
					var fr = bars[t + horizon].close / close - 1.0;
					if (finite(fr)) {
						probUp.push(c.probUp);
						fwdRet.push(fr);
						cls.push(close > c.priceHi ? 1 : (close < c.priceLo ? -1 : 0));
					}
				}
			}
			t++;
		}

		var n = fwdRet.length;
		var ic = ProjectionScore.rankIC(probUp, fwdRet);

		// mean forward return by class + the drift null (unconditional mean)
		var drift = mean(fwdRet);
		var up = filterMean(fwdRet, cls, 1);
		var dn = filterMean(fwdRet, cls, -1);
		var bal = filterMean(fwdRet, cls, 0);
		var nUp = count(cls, 1), nDn = count(cls, -1), nBal = count(cls, 0);

		// directional hit-rate of the discovery signal vs base rate of up moves
		var baseUp = 0; for (r in fwdRet) if (r > 0) baseUp++;
		var baseRate = n > 0 ? baseUp / n : Math.NaN;
		var discUpHit = condRate(fwdRet, cls, 1, true);   // P(fwd>0 | discovery up)
		var discDnHit = condRate(fwdRet, cls, -1, false);  // P(fwd<0 | discovery down)

		Sys.println("=== Auction / volume-profile breakout benchmark (new-information test) ===");
		Sys.println('tape=$tapePath bars=${bars.length} horizon=$horizon step=$step window=$win');
		Sys.println('scored anchors=$n  (discovery-up=$nUp  discovery-down=$nDn  balance=$nBal)');
		Sys.println("");
		Sys.println('rank-IC  P(breakout up) → forward return = ${fmt(ic, 4)}');
		Sys.println("");
		Sys.println("mean forward return by classification (vs drift null):");
		Sys.println('   drift (unconditional) = ${bps(drift)} bps   (n=$n)');
		Sys.println('   discovery UP          = ${bps(up)} bps   (n=$nUp)');
		Sys.println('   discovery DOWN        = ${bps(dn)} bps   (n=$nDn)');
		Sys.println('   balance               = ${bps(bal)} bps   (n=$nBal)');
		Sys.println("");
		Sys.println('directional: base up-rate = ${pct(baseRate)}  |  P(up|disc-up) = ${pct(discUpHit)}  |  P(down|disc-down) = ${pct(discDnHit)}');
		Sys.println("");
		// edge = discovery direction separates forward return beyond drift, both sides
		var upEdge = finite(up) && finite(drift) && up > drift;
		var dnEdge = finite(dn) && finite(drift) && dn < drift;
		var icEdge = Math.abs(ic) > 0.05;
		if (upEdge && dnEdge && (nUp > 15 && nDn > 15))
			Sys.println("VERDICT: volume-breakout separates forward direction beyond drift (both sides) — a real, NEW-INFORMATION edge. PURSUE.");
		else if (icEdge)
			Sys.println("VERDICT: some monotone breakout→return signal (rank-IC) but weak/one-sided — probe further.");
		else
			Sys.println("VERDICT: NO-GO — volume-breakout does not predict forward direction beyond drift.");
		Sys.println("AUCTION_BENCHMARK_OK");
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

	static function count(c:Array<Int>, want:Int):Int {
		var n = 0; for (x in c) if (x == want) n++; return n;
	}

	static function condRate(v:Array<Float>, c:Array<Int>, want:Int, positive:Bool):Float {
		var ok = 0; var n = 0;
		for (i in 0...v.length) if (c[i] == want) { n++; if (positive ? v[i] > 0 : v[i] < 0) ok++; }
		return n > 0 ? ok / n : Math.NaN;
	}

	static inline function finite(x:Float):Bool return !Math.isNaN(x) && Math.isFinite(x);
	static function pct(x:Float):String return finite(x) ? fmt(x * 100, 1) + "%" : "n/a";
	static function bps(x:Float):String return finite(x) ? fmt(x * 10000, 1) : "n/a";

	static function loadBars(path:String):Array<Bar> {
		if (sys.FileSystem.exists(path)) return OhlcvCsv.parse(sys.io.File.getContent(path));
		throw 'no tape at $path';
	}

	static function fmt(x:Float, n:Int):String {
		if (!finite(x)) return "n/a";
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
}
