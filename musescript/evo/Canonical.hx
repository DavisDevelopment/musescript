package musescript.evo;

import haxe.crypto.Sha1;

class Canonical {
	public static function structuralKey(g:StrategyGenome):String {
		return Sha1.encode(haxe.Serializer.run(genomeKey(g))).substr(0, 16);
	}

	public static function genomeKey(g:StrategyGenome):Dynamic {
		return [
			keyBool(g.entryLong), keyBool(g.entryShort),
			keyBool(g.exitLong), keyBool(g.exitShort),
			keyScalar(g.size),
			[for (p in g.params) [p.name, p.defaultValue, p.min, p.max, p.step, p.tune]],
			g.name
		];
	}

	static function keySeries(n:SeriesNode):Dynamic {
		return switch (n) {
			case SPrice(f): ["P", f];
			case SInd(name, field, window, src):
				["I", name, src != null ? keySeries(src) : ["P", field], window];
		};
	}

	static function keyScalar(n:ScalarNode):Dynamic {
		return switch (n) {
			case KConst(v): ["K", Math.round(v * 1e9) / 1e9];
			case KParam(i): ["R", i];
			case KFeature(name): ["F", name];
			case KSeries(s): keySeries(s);
			case KLookback(s, k): ["L", keySeries(s), k];
			case KArith(op, a, b):
				var ka = keyScalar(a);
				var kb = keyScalar(b);
				["A", op, ka, kb];
		};
	}

	static function keyBool(n:BoolNode):Dynamic {
		return switch (n) {
			case BCross(dir, a, b): ["X", dir, keySeries(a), keySeries(b)];
			case BCmp(op, a, b): ["C", op, keyScalar(a), keyScalar(b)];
			case BTrend(dir, s, w): ["T", dir, keySeries(s), w];
			case BAnd(a, b): ["&", keyBool(a), keyBool(b)];
			case BOr(a, b): ["|", keyBool(a), keyBool(b)];
			case BNot(a): ["!", keyBool(a)];
		};
	}

	public static function nodeCount(g:StrategyGenome):Int {
		return countBool(g.entryLong) + countBool(g.entryShort)
			+ countBool(g.exitLong) + countBool(g.exitShort) + countScalar(g.size);
	}

	static function countSeries(n:SeriesNode):Int {
		return switch (n) {
			case SPrice(_): 1;
			case SInd(_, _, _, src): 1 + (src != null ? countSeries(src) : 0);
		};
	}

	static function countScalar(n:ScalarNode):Int {
		return switch (n) {
			case KConst(_) | KParam(_): 1;
			case KFeature(_): 1;
			case KSeries(s): countSeries(s);
			case KLookback(s, _): 1 + countSeries(s);
			case KArith(_, a, b): 1 + countScalar(a) + countScalar(b);
		};
	}

	static function countBool(n:BoolNode):Int {
		return switch (n) {
			case BCross(_, a, b): 1 + countSeries(a) + countSeries(b);
			case BCmp(_, a, b): 1 + countScalar(a) + countScalar(b);
			case BTrend(_, s, _): 1 + countSeries(s);
			case BAnd(a, b) | BOr(a, b): 1 + countBool(a) + countBool(b);
			case BNot(a): 1 + countBool(a);
		};
	}
}
