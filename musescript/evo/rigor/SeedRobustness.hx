package musescript.evo.rigor;

/**
 * Seed-robustness aggregator: a GO requires the **median** (not max) of the
 * verdict metric across seeds to clear the bar — blocks single-seed cherry-picks.
 */
class SeedRobustness {
	public static function summarize(metrics:Array<Float>):{
		n:Int, median:Float, mean:Float, min:Float, max:Float, std:Float
	} {
		var xs = [for (m in metrics) if (Math.isFinite(m)) m];
		if (xs.length == 0)
			return {n: 0, median: Math.NaN, mean: Math.NaN, min: Math.NaN, max: Math.NaN, std: Math.NaN};
		xs.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var sum = 0.0;
		for (x in xs) sum += x;
		var mean = sum / xs.length;
		var var_ = 0.0;
		for (x in xs) { var d = x - mean; var_ += d * d; }
		var_ /= xs.length;
		var mid = Std.int(xs.length / 2);
		var med = (xs.length % 2 == 0) ? 0.5 * (xs[mid - 1] + xs[mid]) : xs[mid];
		return {
			n: xs.length,
			median: med,
			mean: mean,
			min: xs[0],
			max: xs[xs.length - 1],
			std: Math.sqrt(var_)
		};
	}

	/** GO iff median clears `threshold`. Also reports the max (cherry-pick contrast). */
	public static function verdict(metrics:Array<Float>, threshold:Float):{
		go:Bool, median:Float, max:Float, threshold:Float, n:Int
	} {
		var s = summarize(metrics);
		return {
			go: s.n > 0 && Math.isFinite(s.median) && s.median > threshold,
			median: s.median,
			max: s.max,
			threshold: threshold,
			n: s.n
		};
	}
}
