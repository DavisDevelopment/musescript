package musescript.harness;

/**
 * Bucket H — tape / data-integrity linter for OHLCV bars (PIPELINE_HARDENING_TODO.md).
 *
 * H1 Tape sanity: OHLC relations, non-negative volume, finite prices, non-empty.
 * H2 Look-ahead in data: strictly increasing timestamps, contiguous `index`, no duplicate times.
 * H3 is audited separately via `ProjectionScore.realizedTarget` / realized-vol helpers (see tests).
 */
class TapeLinter {
	public static inline var SEV_ERROR = "error";
	public static inline var SEV_WARN = "warn";

	/** One finding. `bar` is -1 for tape-level issues. */
	public static function issue(severity:String, code:String, message:String, bar:Int = -1):{
		severity:String, code:String, message:String, bar:Int
	} {
		return { severity: severity, code: code, message: message, bar: bar };
	}

	/**
	 * Full audit. Returns all issues (errors + warnings). Empty ⇒ clean enough to trade.
	 * `strictTime` (default true): require strictly increasing `time` when times are not just indices.
	 */
	public static function lint(
		bars:Array<Bar>,
		?opts:{?strictTime:Bool, ?allowZeroVolume:Bool, ?maxGapMult:Float}
	):Array<{severity:String, code:String, message:String, bar:Int}> {
		var out:Array<{severity:String, code:String, message:String, bar:Int}> = [];
		var strictTime = opts == null || opts.strictTime != false;
		var allowZeroVol = opts != null && opts.allowZeroVolume == true;
		var maxGapMult = opts != null && opts.maxGapMult != null ? opts.maxGapMult : 5.0;

		if (bars == null || bars.length == 0) {
			out.push(issue(SEV_ERROR, "empty", "tape has no bars"));
			return out;
		}

		var gaps:Array<Float> = [];
		for (i in 0...bars.length) {
			var b = bars[i];
			if (b == null) {
				out.push(issue(SEV_ERROR, "null_bar", "null bar slot", i));
				continue;
			}
			if (b.index != i)
				out.push(issue(SEV_WARN, "index_mismatch", 'bar.index=${b.index} != position $i', i));

			if (!finite(b.open) || !finite(b.high) || !finite(b.low) || !finite(b.close)) {
				out.push(issue(SEV_ERROR, "non_finite_ohlc", "non-finite OHLC", i));
				continue;
			}
			if (!(b.high >= b.low))
				out.push(issue(SEV_ERROR, "high_lt_low", 'high=${b.high} < low=${b.low}', i));
			if (!(b.high + 1e-12 >= b.open) || !(b.high + 1e-12 >= b.close))
				out.push(issue(SEV_ERROR, "high_below_body", "high below open/close", i));
			if (!(b.low - 1e-12 <= b.open) || !(b.low - 1e-12 <= b.close))
				out.push(issue(SEV_ERROR, "low_above_body", "low above open/close", i));
			if (!(b.open > 0) || !(b.high > 0) || !(b.low > 0) || !(b.close > 0))
				out.push(issue(SEV_ERROR, "non_positive_price", "price ≤ 0", i));
			if (!finite(b.volume) || b.volume < 0)
				out.push(issue(SEV_ERROR, "bad_volume", 'volume=${b.volume}', i));
			else if (!allowZeroVol && b.volume == 0)
				out.push(issue(SEV_WARN, "zero_volume", "zero volume", i));

			if (i > 0) {
				var prev = bars[i - 1];
				if (prev != null && finite(prev.time) && finite(b.time)) {
					if (b.time < prev.time)
						out.push(issue(SEV_ERROR, "time_regression",
							'time ${b.time} < prev ${prev.time} (look-ahead / shuffle risk)', i));
					else if (b.time == prev.time)
						out.push(issue(SEV_ERROR, "duplicate_time", 'duplicate time ${b.time}', i));
					else
						gaps.push(b.time - prev.time);
				}
			}
		}

		if (strictTime && gaps.length > 8) {
			var med = median(gaps);
			if (med > 0) {
				for (i in 1...bars.length) {
					var g = bars[i].time - bars[i - 1].time;
					if (g > med * maxGapMult)
						out.push(issue(SEV_WARN, "large_gap",
							'gap $g > ${maxGapMult}× median $med', i));
				}
			}
		}

		return out;
	}

	/** True iff no ERROR-severity findings (warnings OK). */
	public static function isClean(bars:Array<Bar>, ?opts:{?strictTime:Bool, ?allowZeroVolume:Bool, ?maxGapMult:Float}):Bool {
		for (iss in lint(bars, opts))
			if (iss.severity == SEV_ERROR) return false;
		return bars != null && bars.length > 0;
	}

	public static function errorCount(issues:Array<{severity:String, code:String, message:String, bar:Int}>):Int {
		var n = 0;
		for (iss in issues) if (iss.severity == SEV_ERROR) n++;
		return n;
	}

	public static function formatReport(
		issues:Array<{severity:String, code:String, message:String, bar:Int}>, maxLines:Int = 40
	):String {
		if (issues.length == 0) return "TAPE_LINT_OK (0 issues)";
		var buf = new StringBuf();
		buf.add('TAPE_LINT issues=${issues.length} errors=${errorCount(issues)}\n');
		var shown = 0;
		for (iss in issues) {
			if (shown >= maxLines) {
				buf.add('... (${issues.length - shown} more)\n');
				break;
			}
			buf.add('${iss.severity} [${iss.code}]');
			if (iss.bar >= 0) buf.add(' bar=${iss.bar}');
			buf.add(': ${iss.message}\n');
			shown++;
		}
		return buf.toString();
	}

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);

	static function median(xs:Array<Float>):Float {
		if (xs.length == 0) return Math.NaN;
		var a = xs.copy();
		a.sort(Reflect.compare);
		var m = Std.int(a.length / 2);
		return a.length % 2 == 1 ? a[m] : 0.5 * (a[m - 1] + a[m]);
	}
}
