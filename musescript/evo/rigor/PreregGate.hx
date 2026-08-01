package musescript.evo.rigor;

/**
 * Hard pre-registration gate for CorpusEvoRun `--prereg`.
 * Seals a threshold at run start; after champion OOS, `evaluate` must clear it
 * or the run aborts (non-zero exit / clear NO-GO) — not WARNING-only.
 */
class PreregGate {
	public var registration:PreRegistration;
	public var sealedMetricName:String;

	public function new(hypothesis:String, nullName:String, threshold:Float, horizon:Int, ?metricName:String) {
		this.registration = new PreRegistration(hypothesis, nullName, threshold, horizon);
		this.sealedMetricName = metricName != null ? metricName : "champion_oos_sharpe";
	}

	/** Seal from CLI-shaped knobs (threshold default 0.0). */
	public static function seal(
		?threshold:Float = 0.0,
		?horizon:Int = 5,
		?hypothesis:String = "champion OOS clears sealed threshold"
	):PreregGate {
		return new PreregGate(hypothesis, "buy_hold", threshold, horizon, "champion_oos_sharpe");
	}

	public function describe():String {
		return registration.describe() + ' metric=$sealedMetricName';
	}

	/**
	 * Evaluate champion metric against the sealed threshold.
	 * `go=false` ⇒ caller must abort (Sys.exit ≠ 0 / print ABORT).
	 */
	public function evaluate(metric:Float):{
		go:Bool, threshold:Float, metric:Float, hypothesis:String, abort:Bool, label:String
	} {
		var v = registration.evaluate(metric);
		return {
			go: v.go,
			threshold: v.threshold,
			metric: v.metric,
			hypothesis: v.hypothesis,
			abort: !v.go,
			label: v.go ? "prereg PASS" : "prereg ABORT"
		};
	}

	public static function formatLine(v:{
		go:Bool, threshold:Float, metric:Float, hypothesis:String, abort:Bool, label:String
	}):String {
		return '[${v.label}] metric=${fmt(v.metric)} threshold=${fmt(v.threshold)}'
			+ ' => ${v.go ? "GO" : "NO-GO"} (${v.hypothesis})';
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 10000) / 10000);
	}
}
