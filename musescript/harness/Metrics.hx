package musescript.harness;

class Metrics {
	public static function sharpe(returns:Array<Float>, ?rf:Float = 0):Float {
		if (returns.length < 2) return 0;
		var mean = 0.0;
		for (r in returns) mean += r;
		mean /= returns.length;
		var var_ = 0.0;
		for (r in returns) {
			var d = r - mean;
			var_ += d * d;
		}
		var_ /= returns.length - 1;
		var std = Math.sqrt(var_);
		if (std == 0) return 0;
		return ((mean - rf) / std) * Math.sqrt(252);
	}

	public static function maxDrawdown(equity:Array<Float>):Float {
		var peak = Math.NEGATIVE_INFINITY;
		var maxDd = 0.0;
		for (e in equity) {
			if (e > peak) peak = e;
			var dd = peak > 0 ? (peak - e) / peak : 0;
			if (dd > maxDd) maxDd = dd;
		}
		return maxDd;
	}

	public static function returnsFromEquity(equity:Array<Float>):Array<Float> {
		var out = [];
		for (i in 1...equity.length) {
			var prev = equity[i - 1];
			out.push(prev != 0 ? (equity[i] - prev) / prev : 0);
		}
		return out;
	}

	public static function winRate(wins:Int, trades:Int):Float {
		return trades == 0 ? 0 : wins / trades;
	}
}
