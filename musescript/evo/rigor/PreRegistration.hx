package musescript.evo.rigor;

/**
 * Pre-registration harness: record (hypothesis, null, threshold, horizon) BEFORE
 * a run, then evaluate against it — no post-hoc threshold shopping.
 */
class PreRegistration {
	public var hypothesis:String;
	public var nullName:String;
	public var threshold:Float;
	public var horizon:Int;
	public var recordedAt:Float;
	var sealed:Bool = false;

	public function new(hypothesis:String, nullName:String, threshold:Float, horizon:Int) {
		this.hypothesis = hypothesis;
		this.nullName = nullName;
		this.threshold = threshold;
		this.horizon = horizon;
		this.recordedAt = haxe.Timer.stamp();
		this.sealed = true;
	}

	/** Verdict against the sealed threshold. Never mutates the registration. */
	public function evaluate(metric:Float):{go:Bool, threshold:Float, metric:Float, hypothesis:String} {
		return {
			go: Math.isFinite(metric) && metric > threshold,
			threshold: threshold,
			metric: metric,
			hypothesis: hypothesis
		};
	}

	public function describe():String {
		return 'prereg: "$hypothesis" vs null=$nullName threshold=$threshold horizon=$horizon';
	}
}
