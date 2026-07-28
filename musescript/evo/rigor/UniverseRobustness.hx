package musescript.evo.rigor;

/**
 * Universe-robustness: a GO must hold across an instrument universe, not a
 * cherry-picked single name. Flags single-name "edges."
 */
class UniverseRobustness {
	/**
	 * `perName[i] = {name, metric}` — metric already computed per instrument.
	 * GO requires at least `minPass` names clearing `threshold`, AND pass-rate
	 * ≥ `minPassRate`. Single-name universes always flagged.
	 */
	public static function verdict(
		perName:Array<{name:String, metric:Float}>,
		threshold:Float,
		?minPass:Int = 2,
		?minPassRate:Float = 0.5
	):{
		go:Bool, singleName:Bool, passed:Int, total:Int, threshold:Float, names:Array<String>
	} {
		var passed = 0;
		var names:Array<String> = [];
		for (p in perName) {
			if (Math.isFinite(p.metric) && p.metric > threshold) {
				passed++;
				names.push(p.name);
			}
		}
		var total = perName.length;
		var singleName = total < 2;
		var rate = total > 0 ? passed / total : 0.0;
		var go = !singleName && passed >= minPass && rate >= minPassRate;
		return {
			go: go,
			singleName: singleName,
			passed: passed,
			total: total,
			threshold: threshold,
			names: names
		};
	}
}
