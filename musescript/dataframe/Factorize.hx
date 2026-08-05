package musescript.dataframe;

/**
 * Categorical encoding — F64 / Str → codes + uniques (pandas `factorize` shape).
 *
 * `dropNa=true` (default): F64 NaN → code `-1`, excluded from uniques.
 * `dropNa=false`: NaN is a normal unique (groupable; matches GroupBy key policy).
 * Empty string is a normal Str category (not NA).
 */
class Factorize {
	public static inline var NA_CODE:Int = -1;

	public static function f64(values:Array<Float>, ?dropNa:Bool = true):FactorizeResult {
		if (values == null || values.length == 0)
			return new FactorizeResult([], FactorUniques.F64(IndexF64.empty()));
		var codes:Array<Int> = [];
		var uniq:Array<Float> = [];
		var first = new Map<String, Int>();
		for (v in values) {
			if (dropNa && Math.isNaN(v)) {
				codes.push(NA_CODE);
				continue;
			}
			var tag = keyF64(v);
			var ci = first.get(tag);
			if (ci == null) {
				ci = uniq.length;
				first.set(tag, ci);
				uniq.push(v);
			}
			codes.push(ci);
		}
		return new FactorizeResult(codes, FactorUniques.F64(IndexF64.fromArray(uniq)));
	}

	public static function f64Index(idx:IndexF64, ?dropNa:Bool = true):FactorizeResult {
		if (idx == null) return f64([], dropNa);
		return f64(idx.toArray(), dropNa);
	}

	public static function f64Nd(a:musescript.ndarray.NdArrayF64, ?dropNa:Bool = true):FactorizeResult {
		if (a == null) return f64([], dropNa);
		return f64(a.toArray(), dropNa);
	}

	public static function str(values:Array<String>, ?dropNa:Bool = true):FactorizeResult {
		if (values == null || values.length == 0)
			return new FactorizeResult([], FactorUniques.Str(IndexStr.empty()));
		var codes:Array<Int> = [];
		var uniq:Array<String> = [];
		var first = new Map<String, Int>();
		for (raw in values) {
			var s = raw != null ? raw : "";
			var ci = first.get(s);
			if (ci == null) {
				ci = uniq.length;
				first.set(s, ci);
				uniq.push(s);
			}
			codes.push(ci);
		}
		return new FactorizeResult(codes, FactorUniques.Str(IndexStr.fromArray(uniq)));
	}

	public static function strIndex(idx:IndexStr, ?dropNa:Bool = true):FactorizeResult {
		if (idx == null) return str([], dropNa);
		return str(idx.labels(), dropNa);
	}

	/** Factorize one MultiLevel (dense labels → codes + uniques). */
	public static function level(lv:MultiLevel, ?dropNa:Bool = true):FactorizeResult {
		return switch (lv) {
			case F64(i): f64Index(i, dropNa);
			case Str(i): strIndex(i, dropNa);
		};
	}

	static function keyF64(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		return Std.string(v);
	}
}
