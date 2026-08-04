package musescript.harness;

import musescript.builtins.StatsBuiltins;

/**
 * Post-run diagnostics / “kiss the curve” chart pack.
 *
 * Pure Metrics + ChartSink composition — **not** for WASM per-bar hot paths.
 * Call after a backtest (or via `muse.diag.pack` / `MuseRuntime.diagPack`).
 *
 * Pack contents:
 * 1. Equity + running-max overlay (“kiss the peak”)
 * 2. Underwater / drawdown fraction + zero hline
 * 3. ACF of returns (lags 1…maxLag) via `stat_autocorr`
 * 4. Optional lag-1 rolling ACF strip
 */
class DiagPack {
	public static inline var DEFAULT_MAX_LAG = 20;
	public static inline var COLOR_PEAK = "#f39c12";
	public static inline var COLOR_DD = "#c0392b";
	public static inline var COLOR_ACF = "#2980b9";
	public static inline var COLOR_ROLL = "#8e44ad";

	/** Running maximum of equity (kiss-the-peak reference). */
	public static function runningMax(equity:Array<Float>):Array<Float> {
		if (equity == null || equity.length == 0) return [];
		var out:Array<Float> = [];
		var peak = Math.NEGATIVE_INFINITY;
		for (e in equity) {
			if (e > peak) peak = e;
			out.push(peak);
		}
		return out;
	}

	/**
	 * Underwater fraction `(peak − equity) / peak` (0 at the peak).
	 * Matches `Metrics.maxDrawdown`’s per-bar definition; peak ≤ 0 → 0.
	 */
	public static function drawdownSeries(equity:Array<Float>):Array<Float> {
		if (equity == null || equity.length == 0) return [];
		var out:Array<Float> = [];
		var peak = Math.NEGATIVE_INFINITY;
		for (e in equity) {
			if (e > peak) peak = e;
			out.push(peak > 0 ? (peak - e) / peak : 0.0);
		}
		return out;
	}

	/** Pearson ACF at lags 1…maxLag (`StatsBuiltins.autocorr`). */
	public static function acf(returns:Array<Float>, maxLag:Int = DEFAULT_MAX_LAG):Array<Float> {
		var ml = maxLag < 1 ? DEFAULT_MAX_LAG : maxLag;
		var out:Array<Float> = [];
		if (returns == null) return out;
		for (lag in 1...(ml + 1))
			out.push(StatsBuiltins.autocorr(returns, lag));
		return out;
	}

	/**
	 * Rolling lag-`lag` ACF over a trailing window of returns.
	 * Length matches `returns`; entries before the window is full are NaN.
	 */
	public static function rollingAcf(returns:Array<Float>, window:Int, lag:Int = 1):Array<Float> {
		if (returns == null) return [];
		var n = returns.length;
		var out:Array<Float> = [for (_ in 0...n) Math.NaN];
		if (window < 2 || lag < 1 || n == 0) return out;
		for (i in (window - 1)...n) {
			var slice:Array<Float> = [];
			for (j in (i - window + 1)...(i + 1)) slice.push(returns[j]);
			out[i] = StatsBuiltins.autocorr(slice, lag);
		}
		return out;
	}

	/** Bars where equity sits on the running peak (relative eps). */
	public static function peakTouchCount(equity:Array<Float>, peak:Array<Float>):Int {
		if (equity == null || peak == null) return 0;
		var n = equity.length < peak.length ? equity.length : peak.length;
		var c = 0;
		for (i in 0...n) {
			var p = peak[i];
			var e = equity[i];
			if (!(p > 0)) {
				if (e == p) c++;
				continue;
			}
			if (Math.abs(e - p) / p <= 1e-12) c++;
		}
		return c;
	}

	/** Mean length of consecutive underwater (dd > 0) episodes; 0 if never underwater. */
	public static function meanUnderwaterBars(dd:Array<Float>):Float {
		if (dd == null || dd.length == 0) return 0.0;
		var sum = 0;
		var episodes = 0;
		var run = 0;
		for (v in dd) {
			if (v > 0) {
				run++;
			} else if (run > 0) {
				sum += run;
				episodes++;
				run = 0;
			}
		}
		if (run > 0) {
			sum += run;
			episodes++;
		}
		return episodes == 0 ? 0.0 : (sum * 1.0) / episodes;
	}

	/** Emit the full pack into `chart`; returns summary + series used. */
	public static function emit(chart:ChartSink, equity:Array<Float>, ?opts:DiagPackOpts):DiagPackResult {
		var o = opts != null ? opts : {};
		var prefix = o.prefix != null && o.prefix.length > 0 ? o.prefix : "diag";
		var maxLag = o.maxLag != null && o.maxLag > 0 ? o.maxLag : DEFAULT_MAX_LAG;
		var rollWin = o.rollingWindow != null && o.rollingWindow > 0 ? o.rollingWindow : 0;
		var doKiss = o.kiss != false;
		var doUw = o.underwater != false;
		var doAcf = o.acf != false;
		var colorPeak = o.colorPeak != null ? o.colorPeak : COLOR_PEAK;
		var colorDd = o.colorDd != null ? o.colorDd : COLOR_DD;
		var colorAcf = o.colorAcf != null ? o.colorAcf : COLOR_ACF;
		var colorRoll = o.colorRoll != null ? o.colorRoll : COLOR_ROLL;
		var colorEq = o.colorEquity;

		var before = chart != null ? chart.commands.length : 0;
		var eq = equity != null ? equity : [];
		var peak = runningMax(eq);
		var dd = drawdownSeries(eq);
		var rets = Metrics.returnsFromEquity(eq);
		var acfVals = acf(rets, maxLag);
		var roll = rollWin > 0 ? rollingAcf(rets, rollWin, 1) : [];

		if (chart != null) {
			if (doKiss) {
				for (i in 0...eq.length) {
					chart.plot(eq[i], prefix + ".equity", colorEq, i);
					chart.plot(peak[i], prefix + ".peak", colorPeak, i);
				}
			}
			if (doUw) {
				for (i in 0...dd.length)
					chart.plot(dd[i], prefix + ".dd", colorDd, i);
				chart.hline(0.0, prefix + ".dd.zero");
			}
			if (doAcf) {
				for (i in 0...acfVals.length) {
					var lag = i + 1;
					chart.plot(acfVals[i], prefix + ".acf", colorAcf, lag);
				}
				chart.hline(0.0, prefix + ".acf.zero");
			}
			if (rollWin > 0) {
				for (i in 0...roll.length) {
					var v = roll[i];
					if (Math.isNaN(v)) continue;
					chart.plot(v, prefix + ".acf.roll1", colorRoll, i + 1);
				}
			}
		}

		var lag1 = acfVals.length > 0 ? acfVals[0] : Math.NaN;
		var after = chart != null ? chart.commands.length : before;
		return {
			acf: acfVals,
			lag1: lag1,
			maxDrawdown: Metrics.maxDrawdown(eq),
			peakTouches: peakTouchCount(eq, peak),
			meanUnderwaterBars: meanUnderwaterBars(dd),
			rollingAcf: roll,
			commandsAdded: after - before,
			returns: rets,
			peak: peak,
			drawdown: dd
		};
	}

	/** Equity + peak only. */
	public static function emitKiss(chart:ChartSink, equity:Array<Float>, ?opts:DiagPackOpts):DiagPackResult {
		return emit(chart, equity, mergeOpts(opts, { kiss: true, underwater: false, acf: false, rollingWindow: 0 }));
	}

	/** Underwater panel only. */
	public static function emitUnderwater(chart:ChartSink, equity:Array<Float>, ?opts:DiagPackOpts):DiagPackResult {
		return emit(chart, equity, mergeOpts(opts, { kiss: false, underwater: true, acf: false, rollingWindow: 0 }));
	}

	/** ACF panel (+ optional rolling) from an equity curve. */
	public static function emitAcf(chart:ChartSink, equity:Array<Float>, ?opts:DiagPackOpts):DiagPackResult {
		return emit(chart, equity, mergeOpts(opts, { kiss: false, underwater: false, acf: true }));
	}

	static function mergeOpts(base:Null<DiagPackOpts>, overlay:DiagPackOpts):DiagPackOpts {
		var o:DiagPackOpts = base != null ? {
			maxLag: base.maxLag,
			rollingWindow: base.rollingWindow,
			prefix: base.prefix,
			kiss: base.kiss,
			underwater: base.underwater,
			acf: base.acf,
			colorEquity: base.colorEquity,
			colorPeak: base.colorPeak,
			colorDd: base.colorDd,
			colorAcf: base.colorAcf,
			colorRoll: base.colorRoll
		} : {};
		if (overlay.maxLag != null) o.maxLag = overlay.maxLag;
		if (overlay.rollingWindow != null) o.rollingWindow = overlay.rollingWindow;
		if (overlay.prefix != null) o.prefix = overlay.prefix;
		if (overlay.kiss != null) o.kiss = overlay.kiss;
		if (overlay.underwater != null) o.underwater = overlay.underwater;
		if (overlay.acf != null) o.acf = overlay.acf;
		if (overlay.colorEquity != null) o.colorEquity = overlay.colorEquity;
		if (overlay.colorPeak != null) o.colorPeak = overlay.colorPeak;
		if (overlay.colorDd != null) o.colorDd = overlay.colorDd;
		if (overlay.colorAcf != null) o.colorAcf = overlay.colorAcf;
		if (overlay.colorRoll != null) o.colorRoll = overlay.colorRoll;
		return o;
	}

	/** Plain JS/JSON-friendly summary (no large series unless asked). */
	public static function toSummary(r:DiagPackResult, ?includeSeries:Bool):Dynamic {
		var s:Dynamic = {
			lag1: fin(r.lag1),
			maxDrawdown: fin(r.maxDrawdown),
			peakTouches: r.peakTouches,
			meanUnderwaterBars: fin(r.meanUnderwaterBars),
			commandsAdded: r.commandsAdded,
			acf: [for (x in r.acf) fin(x)]
		};
		if (includeSeries == true) {
			Reflect.setField(s, "returns", r.returns);
			Reflect.setField(s, "peak", r.peak);
			Reflect.setField(s, "drawdown", r.drawdown);
			Reflect.setField(s, "rollingAcf", r.rollingAcf);
		}
		return s;
	}

	static function fin(x:Float):Null<Float> {
		return Math.isFinite(x) ? x : null;
	}
}
