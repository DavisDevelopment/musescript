package musescript.ew;

import musescript.harness.Bar;
import musescript.indicators.ew.EwProject.EwProjectBand;

/** One anchor's capture score: did any projected band catch the realized path, how near the best came. */
typedef AnchorScore = {
	/** Number of scoreable bands in the fan at this anchor. */
	var bands:Int;
	/** True iff ≥1 band's price/time zone was entered by realized price action after t. */
	var anyHit:Bool;
	/** Min over bands of ATR-normalized distance from realized path to band zone (0 on hit). NaN = unscoreable. */
	var bestMargin:Float;
	/** Index (in the fan) of the band captured earliest, or -1 if none hit. */
	var hitBandIdx:Int;
	/** ATR-normalized error of the nearest band mid vs realized close at that band's target bar (NaN = N/A). */
	var pointErr:Float;
}

/** Aggregate over an anchor grid — the on-screen "actual numbers". */
typedef GridScore = {
	var anchors:Int;
	var scored:Int;
	/** Fraction of scored anchors with anyHit == true (Q1/Q3: "how often does ANY path capture it"). */
	var hitRate:Float;
	/** Median / 90th-pct of bestMargin over scored anchors (Q2: "within what margin"). */
	var marginP50:Float;
	var marginP90:Float;
	/** Median nearest-band point error (secondary Q2 view). */
	var pointErrP50:Float;
	/** Mean fan size — how many rival interpretations we actually carried. */
	var meanBands:Float;
}

/**
 * Leakage-free capture benchmark for EW projection fans (FIDELITY_AND_BENCHMARK_PLAN.md Phase 0).
 *
 * PURE + backend-agnostic: every function takes an ALREADY-FROZEN fan (bands built from data ≤ t by
 * a host) plus the REALIZED future bars (strictly after t) and reports capture / margin. The PIT
 * guarantee lives at the call site (the harness feeds a host bars ≤ t, snapshots the fan, then hands
 * this module bars > t); nothing here can see the future except the realized target it scores against.
 *
 * Answers, per the five questions:
 *   Q1 anyHit         — did ANY band's price×time zone get entered by realized action?
 *   Q2 bestMargin     — if not, how near (ATR-normalized) did the closest band come?
 *   Q3 hitRate        — Q1 aggregated over an anchor grid.
 *   Q4 (lift)         — run the grid under two param packs, diff the GridScores (caller's job).
 *   Q5 (profit)       — a separate cost-charged backtest consumes the same fans (next slice).
 *
 * A band is a future price band [priceLo,priceHi] expected around bar window [barLo,barHi]. "Capture"
 * is intrabar and time-bounded: realized price is deemed to have reached the zone if some future
 * bar's [low,high] intersects [priceLo,priceHi] at or before the target bar (ceil(barHi)). Using the
 * bar range (not close) is the honest test of "did price get there"; the time bound stops a band from
 * being retroactively credited by an unrelated move long after its projected window.
 */
class EwBenchmark {
	/** Distance between two closed intervals; 0 if they overlap, else the positive gap. */
	static inline function intervalGap(aLo:Float, aHi:Float, bLo:Float, bHi:Float):Float {
		if (aHi >= bLo && aLo <= bHi) return 0.0;
		return aLo > bHi ? aLo - bHi : bLo - aHi;
	}

	/** First future bar index (into `futures`) whose bar reaches the band zone within its time window;
	 * -1 if never. `futures` are bars strictly after the anchor; a band is only scoreable if its target
	 * bar (ceil(barHi)) is at/after the first future bar. */
	public static function bandHitIndex(band:EwProjectBand, futures:Array<Bar>):Int {
		if (futures.length == 0) return -1;
		var targetBar = Math.ceil(band.barHi);
		if (targetBar < futures[0].index) return -1; // target already past — unscoreable, not a miss
		for (k in 0...futures.length) {
			var b = futures[k];
			if (b.index > targetBar) break; // beyond the projected window → not captured in time
			if (intervalGap(b.low, b.high, band.priceLo, band.priceHi) <= 0.0) return k;
		}
		return -1;
	}

	/** Min ATR-normalized distance from realized bar ranges (within the band's window) to the band
	 * price zone; 0 on capture. NaN if the band is unscoreable (target already past / no window bars). */
	public static function bandMargin(band:EwProjectBand, futures:Array<Bar>, atr:Float):Float {
		if (futures.length == 0 || !(atr > 0)) return Math.NaN;
		var targetBar = Math.ceil(band.barHi);
		if (targetBar < futures[0].index) return Math.NaN;
		var best = Math.POSITIVE_INFINITY;
		var seen = false;
		for (k in 0...futures.length) {
			var b = futures[k];
			if (b.index > targetBar) break;
			seen = true;
			var g = intervalGap(b.low, b.high, band.priceLo, band.priceHi);
			if (g < best) best = g;
			if (best <= 0.0) return 0.0;
		}
		return seen ? best / atr : Math.NaN;
	}

	/** Nearest-band point error: |band mid − realized close at the band's target bar| / atr, minimized
	 * over the fan. The target bar is clamped to the available future range. NaN if nothing scoreable. */
	static function nearestPointErr(fan:Array<EwProjectBand>, futures:Array<Bar>, atr:Float):Float {
		if (futures.length == 0 || !(atr > 0)) return Math.NaN;
		var best = Math.POSITIVE_INFINITY;
		for (band in fan) {
			var targetBar = Math.ceil(band.barHi);
			if (targetBar < futures[0].index) continue;
			// close of the future bar nearest the (clamped) target bar
			var idx = futures.length - 1;
			for (k in 0...futures.length) {
				if (futures[k].index >= targetBar) { idx = k; break; }
			}
			var mid = (band.priceLo + band.priceHi) * 0.5;
			var e = Math.abs(mid - futures[idx].close) / atr;
			if (e < best) best = e;
		}
		return best == Math.POSITIVE_INFINITY ? Math.NaN : best;
	}

	/** Score one anchor: best-of-fan capture + margin + point error. `atr` normalizes price distances. */
	public static function scoreAnchor(fan:Array<EwProjectBand>, futures:Array<Bar>, atr:Float):AnchorScore {
		var scoreableBands = 0;
		var anyHit = false;
		var hitBandIdx = -1;
		var earliestHitBar = 0x7fffffff;
		var bestMargin = Math.POSITIVE_INFINITY;
		for (i in 0...fan.length) {
			var m = bandMargin(fan[i], futures, atr);
			if (Math.isNaN(m)) continue; // unscoreable band (target past) — doesn't count for or against
			scoreableBands++;
			if (m < bestMargin) bestMargin = m;
			var hk = bandHitIndex(fan[i], futures);
			if (hk >= 0) {
				anyHit = true;
				if (futures[hk].index < earliestHitBar) {
					earliestHitBar = futures[hk].index;
					hitBandIdx = i;
				}
			}
		}
		return {
			bands: scoreableBands,
			anyHit: anyHit,
			bestMargin: scoreableBands == 0 ? Math.NaN : (anyHit ? 0.0 : bestMargin),
			hitBandIdx: hitBandIdx,
			pointErr: nearestPointErr(fan, futures, atr)
		};
	}

	/** Aggregate anchor scores into the reportable grid numbers. Unscoreable anchors (bands == 0) are
	 * excluded from rates and percentiles but counted in `anchors`. */
	public static function aggregate(scores:Array<AnchorScore>):GridScore {
		var scored = 0;
		var hits = 0;
		var margins:Array<Float> = [];
		var pointErrs:Array<Float> = [];
		var bandSum = 0.0;
		for (s in scores) {
			if (s.bands <= 0) continue;
			scored++;
			bandSum += s.bands;
			if (s.anyHit) hits++;
			if (finite(s.bestMargin)) margins.push(s.bestMargin);
			if (finite(s.pointErr)) pointErrs.push(s.pointErr);
		}
		return {
			anchors: scores.length,
			scored: scored,
			hitRate: scored > 0 ? hits / scored : Math.NaN,
			marginP50: percentile(margins, 0.5),
			marginP90: percentile(margins, 0.9),
			pointErrP50: percentile(pointErrs, 0.5),
			meanBands: scored > 0 ? bandSum / scored : Math.NaN
		};
	}

	/**
	 * Empirical CRPS of an ensemble of point forecasts vs a realized value `y`:
	 *   CRPS ≈ mean_i |m_i − y| − 0.5 · mean_{i,j} |m_i − m_j|.
	 * Degenerates to MAE when the fan is a single point (samples == 1), which is why it's meaningful
	 * even now (lattice fan) and sharpens once a real MCMC posterior fills the ensemble (Phase 2).
	 */
	public static function crpsEnsemble(mids:Array<Float>, y:Float):Float {
		var n = 0;
		var term1 = 0.0;
		for (m in mids) if (finite(m)) { term1 += Math.abs(m - y); n++; }
		if (n == 0) return Math.NaN;
		term1 /= n;
		var term2 = 0.0;
		var pairs = 0;
		for (i in 0...mids.length) {
			if (!finite(mids[i])) continue;
			for (j in 0...mids.length) {
				if (!finite(mids[j])) continue;
				term2 += Math.abs(mids[i] - mids[j]);
				pairs++;
			}
		}
		if (pairs > 0) term2 = 0.5 * (term2 / pairs);
		return term1 - term2;
	}

	// ---------- helpers ----------

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);

	/** Linear-interpolated percentile over a copy of `xs` (0..1). NaN when empty. */
	public static function percentile(xs:Array<Float>, q:Float):Float {
		if (xs.length == 0) return Math.NaN;
		var a = xs.copy();
		a.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
		if (a.length == 1) return a[0];
		var pos = q * (a.length - 1);
		var lo = Std.int(pos);
		var hi = lo + 1 < a.length ? lo + 1 : lo;
		var frac = pos - lo;
		return a[lo] + (a[hi] - a[lo]) * frac;
	}
}
