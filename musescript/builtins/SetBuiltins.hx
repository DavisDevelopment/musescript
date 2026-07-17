package musescript.builtins;

/**
 * Opaque set builtins keyed by `Std.string(v)` identity.
 *
 * Runtime rep is `Map<String,Bool>`. Membership is string-identity only —
 * consistent with DictBuiltins' key coercion (same float-hashing caveat).
 */
class SetBuiltins {
	public static function install(vars:Map<String, Dynamic>):Void {
		vars.set("set_new", setNew);
		vars.set("set_add", setAdd);
		vars.set("set_has", setHas);
		vars.set("set_remove", setRemove);
		vars.set("set_size", setSize);
		vars.set("set_union", setUnion);
		vars.set("set_intersect", setIntersect);
		vars.set("set_difference", setDifference);
		vars.set("set_to_vector", setToVector);
		vars.set("set_jaccard", setJaccard);
	}

	public static function setNew():Map<String, Bool> {
		return new Map();
	}

	public static function setAdd(s:Map<String, Bool>, v:Dynamic):Map<String, Bool> {
		var m = ensure(s);
		m.set(keyOf(v), true);
		return m;
	}

	public static function setHas(s:Map<String, Bool>, v:Dynamic):Bool {
		return ensure(s).exists(keyOf(v));
	}

	public static function setRemove(s:Map<String, Bool>, v:Dynamic):Bool {
		return ensure(s).remove(keyOf(v));
	}

	public static function setSize(s:Map<String, Bool>):Int {
		var n = 0;
		for (_ in ensure(s).keys()) n++;
		return n;
	}

	public static function setUnion(a:Map<String, Bool>, b:Map<String, Bool>):Map<String, Bool> {
		var out = copyOf(a);
		for (k in ensure(b).keys()) out.set(k, true);
		return out;
	}

	public static function setIntersect(a:Map<String, Bool>, b:Map<String, Bool>):Map<String, Bool> {
		var out = new Map<String, Bool>();
		var bb = ensure(b);
		for (k in ensure(a).keys())
			if (bb.exists(k)) out.set(k, true);
		return out;
	}

	public static function setDifference(a:Map<String, Bool>, b:Map<String, Bool>):Map<String, Bool> {
		var out = new Map<String, Bool>();
		var bb = ensure(b);
		for (k in ensure(a).keys())
			if (!bb.exists(k)) out.set(k, true);
		return out;
	}

	/**
	 * Materialize set members as a numeric Vector when keys parse as floats;
	 * non-numeric keys become NaN (string-identity limitation).
	 */
	public static function setToVector(s:Map<String, Bool>):Array<Float> {
		var out:Array<Float> = [];
		for (k in ensure(s).keys()) {
			var n = Std.parseFloat(k);
			out.push(Math.isNaN(n) ? Math.NaN : n);
		}
		return out;
	}

	/**
	 * Jaccard similarity `|A ∩ B| / |A ∪ B|`. Both empty → 1.0.
	 */
	public static function setJaccard(a:Map<String, Bool>, b:Map<String, Bool>):Float {
		var aa = ensure(a);
		var bb = ensure(b);
		var inter = 0;
		var union = 0;
		var seen = new Map<String, Bool>();
		for (k in aa.keys()) {
			seen.set(k, true);
			union++;
			if (bb.exists(k)) inter++;
		}
		for (k in bb.keys()) {
			if (!seen.exists(k)) union++;
		}
		if (union == 0) return 1.0;
		return inter / union;
	}

	static function ensure(s:Map<String, Bool>):Map<String, Bool> {
		return s != null ? s : new Map();
	}

	static function copyOf(s:Map<String, Bool>):Map<String, Bool> {
		var out = new Map<String, Bool>();
		for (k in ensure(s).keys()) out.set(k, true);
		return out;
	}

	static inline function keyOf(v:Dynamic):String {
		return Std.string(v);
	}
}
