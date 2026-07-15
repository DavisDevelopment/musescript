package musescript.evo;

/** Deterministic MuseGene → MuseScript expansion. */
class Expand {
	public static function expand(g:StrategyGenome):String {
		var lines = ["{", '  @strategy("${g.name}")'];
		for (p in g.params)
			lines.push('  @param("${p.name}", ${num(p.defaultValue)})');
		var size = scalar(g.size, g.params);
		lines.push("  @on(bar) {");
		lines.push('    if (${bool(g.entryLong, g.params)}) long($size);');
		lines.push('    if (${bool(g.entryShort, g.params)}) short($size);');
		lines.push('    if ((${bool(g.exitLong, g.params)}) || (${bool(g.exitShort, g.params)})) flat();');
		lines.push("  }");
		lines.push("}");
		return lines.join("\n");
	}

	static function num(x:Float):String {
		if (x == Std.int(x)) return Std.string(Std.int(x));
		return Std.string(x);
	}

	public static function series(n:SeriesNode):String {
		return switch (n) {
			case SPrice(f): '"' + f + '"';
			case SInd(name, field, window, src):
				if (src != null) '${name}(${series(src)}, $window)';
				else '${name}("$field", $window)';
		};
	}

	public static function scalar(n:ScalarNode, params:Array<EvoParam>):String {
		return switch (n) {
			case KConst(v): num(v);
			case KParam(i): params[i].name;
			case KSeries(s):
				switch (s) {
					case SPrice(f): f;
					case SInd(name, field, window, src):
						src != null ? '${name}(${series(src)}, $window)' : '${name}("$field", $window)';
				}
			case KLookback(s, k):
				switch (s) {
					case SPrice(f): '$f[$k]';
					default: '(${series(s)})[$k]';
				}
			case KFeature(name):
				name;
			case KArith(op, a, b):
				var as = scalar(a, params);
				var bs = scalar(b, params);
				if (op == "min" || op == "max") return '$op($as, $bs)';
				'($as $op $bs)';
		};
	}

	public static function bool(n:BoolNode, params:Array<EvoParam>):String {
		return switch (n) {
			case BCross(dir, a, b):
				var fn = dir == "over" ? "crossover" : "crossunder";
				'$fn(${series(a)}, ${series(b)})';
			case BCmp(op, a, b):
				'(${scalar(a, params)} $op ${scalar(b, params)})';
			case BTrend(dir, s, w):
				var fn = dir == "up" ? "rising" : "falling";
				'$fn(${series(s)}, $w)';
			case BAnd(a, b): '(${bool(a, params)} && ${bool(b, params)})';
			case BOr(a, b): '(${bool(a, params)} || ${bool(b, params)})';
			case BNot(a): '(!${bool(a, params)})';
		};
	}
}
