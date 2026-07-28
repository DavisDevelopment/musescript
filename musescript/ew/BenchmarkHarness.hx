package musescript.ew;

import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.harness.TapeLinter;

/**
 * Bucket I3 — shared benchmark harness so loadBars / warmup / anchor-grid fixes land once.
 * Runners stay thin: host construction + metric print only.
 */
class BenchmarkHarness {
	/** Load OHLCV CSV or throw. Shared by Ew / Regime / Auction / Profit CLIs. */
	public static function loadBars(path:String, ?fallbacks:Array<String>, ?lint:Bool = true):Array<Bar> {
		var candidates = [path];
		if (fallbacks != null) for (f in fallbacks) candidates.push(f);
		for (p in candidates) {
			if (!OhlcvCsv.exists(p)) continue;
			var bars = OhlcvCsv.load(p);
			if (lint) requireCleanTape(bars, p);
			return bars;
		}
		throw 'no tape found (tried $path)';
	}

	/** Abort on TapeLinter errors (warnings OK). Shared with CorpusEvoRun load path. */
	public static function requireCleanTape(bars:Array<Bar>, ?label:String):Void {
		var issues = TapeLinter.lint(bars, {allowZeroVolume: true});
		if (TapeLinter.errorCount(issues) > 0) {
			Sys.println(TapeLinter.formatReport(issues, 20));
			throw 'tape failed TapeLinter' + (label != null ? ' ($label)' : '');
		}
	}

	/** Refuse tapes too short for warmup + horizon + cushion. */
	public static function requireTapeLength(bars:Array<Bar>, warmup:Int, horizon:Int, cushion:Int = 5):Void {
		var need = warmup + horizon + cushion;
		if (bars.length < need)
			throw 'tape too short (${bars.length} bars) for warmup=$warmup + horizon=$horizon (+$cushion)';
	}

	/** Shared anchor predicate (delegates to HostWarmup). */
	public static inline function isLegalAnchor(
		t:Int, warmup:Int, step:Int, horizon:Int, nBars:Int
	):Bool {
		return HostWarmup.isLegalAnchor(t, warmup, step, horizon, nBars);
	}

	/**
	 * Collect legal anchor indices. Used by unit tests and optional thin runners.
	 */
	public static function anchorGrid(
		nBars:Int, warmup:Int, step:Int, horizon:Int
	):Array<Int> {
		var out:Array<Int> = [];
		var t = 0;
		while (t < nBars) {
			if (isLegalAnchor(t, warmup, step, horizon, nBars)) out.push(t);
			t++;
		}
		return out;
	}

	/** Documented null baselines per runner metric (Bucket I1). */
	public static function nullBaselineDoc(kind:String):String {
		return switch (kind) {
			case "ew", "lattice":
				"capture → ±1 ATR band around last close (cheap width-matched null)";
			case "regime":
				"vol → trailing realized-vol persistence (strong autocorrelation null)";
			case "auction":
				"direction → unconditional drift / mean return";
			case "shuffled":
				"label-shuffle / random cloud (must collapse skill ≈ 0)";
			default:
				"unspecified null";
		};
	}

	/**
	 * Bucket I1 — empirical nulls (synthetic tapes; no CSV required).
	 * Spearman rank-IC of two equal-length series (NaN if n < 10 or zero variance).
	 */
	public static function rankIc(xs:Array<Float>, ys:Array<Float>):Float {
		return musescript.evo.ProjectionScore.rankIC(xs, ys);
	}

	/**
	 * Regime persistence null on vol *change*: predict Δvol_{t→t+H} with 0 (persistence).
	 * Rank-IC of zeros vs realized Δ is undefined/0 — use correlation of trailing vol with Δvol,
	 * which must collapse near 0 on i.i.d. Gaussian returns.
	 */
	public static function persistenceDeltaVolIc(
		rets:Array<Float>, lookback:Int, horizon:Int
	):Float {
		var trail:Array<Float> = [];
		var delta:Array<Float> = [];
		var t = lookback;
		while (t + horizon < rets.length) {
			var v0 = realizedVol(rets, t - lookback, t);
			var v1 = realizedVol(rets, t + horizon - lookback, t + horizon);
			if (Math.isFinite(v0) && Math.isFinite(v1)) {
				trail.push(v0);
				delta.push(v1 - v0);
			}
			t++;
		}
		return rankIc(trail, delta);
	}

	/** Auction drift null: class-conditional mean minus unconditional mean on random labels → ≈0. */
	public static function auctionClassEdge(
		fwdRet:Array<Float>, labels:Array<Int>, want:Int
	):Float {
		if (fwdRet.length != labels.length || fwdRet.length == 0) return Math.NaN;
		var drift = 0.0;
		for (r in fwdRet) drift += r;
		drift /= fwdRet.length;
		var sum = 0.0;
		var n = 0;
		for (i in 0...fwdRet.length) if (labels[i] == want) {
			sum += fwdRet[i];
			n++;
		}
		if (n == 0) return Math.NaN;
		return (sum / n) - drift;
	}

	/** EW ATR-null hit rate on a tape: ±atrMult·ATR band around close[t] vs path to t+H. */
	public static function atrNullHitRate(
		bars:Array<Bar>, warmup:Int, step:Int, horizon:Int, atrN:Int = 14, atrMult:Float = 1.0
	):Float {
		var hits = 0;
		var scored = 0;
		var t = 0;
		while (t < bars.length) {
			if (isLegalAnchor(t, warmup, step, horizon, bars.length)) {
				var atr = atrAt(bars, t, atrN);
				if (!(atr > 0)) { t++; continue; }
				var c = bars[t].close;
				var lo = c - atrMult * atr;
				var hi = c + atrMult * atr;
				var hit = false;
				var end = t + horizon;
				if (end >= bars.length) end = bars.length - 1;
				for (i in (t + 1)...(end + 1)) {
					var b = bars[i];
					if (b.high >= lo && b.low <= hi) { hit = true; break; }
				}
				scored++;
				if (hit) hits++;
			}
			t++;
		}
		return scored > 0 ? hits / (scored + 0.0) : Math.NaN;
	}

	static function realizedVol(rets:Array<Float>, from:Int, toExclusive:Int):Float {
		var n = 0;
		var sum = 0.0;
		var i = from < 0 ? 0 : from;
		while (i < toExclusive && i < rets.length) {
			sum += rets[i] * rets[i];
			n++;
			i++;
		}
		if (n < 2) return Math.NaN;
		return Math.sqrt(sum / n);
	}

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
}
