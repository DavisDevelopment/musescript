package musescript.builtins;

/**
 * Opaque string-keyed dict builtins.
 *
 * Runtime rep is `Map<String,Dynamic>`; keys are coerced with `Std.string`
 * (same convention as `harness.series` / `harness.params`). Float-key hashing
 * precision is intentionally avoided.
 */
class DictBuiltins {
	public static function install(vars:Map<String, Dynamic>):Void {
		vars.set("dict_new", dictNew);
		vars.set("dict_set", dictSet);
		vars.set("dict_get", dictGet);
		vars.set("dict_has", dictHas);
		vars.set("dict_delete", dictDelete);
		vars.set("dict_keys", dictKeys);
		vars.set("dict_values", dictValues);
		vars.set("dict_size", dictSize);
	}

	public static function dictNew():Map<String, Dynamic> {
		return new Map();
	}

	public static function dictSet(d:Map<String, Dynamic>, k:Dynamic, v:Dynamic):Map<String, Dynamic> {
		var m = ensure(d);
		m.set(keyOf(k), v);
		return m;
	}

	public static function dictGet(d:Map<String, Dynamic>, k:Dynamic, ?def:Dynamic):Dynamic {
		var m = ensure(d);
		var key = keyOf(k);
		return m.exists(key) ? m.get(key) : def;
	}

	public static function dictHas(d:Map<String, Dynamic>, k:Dynamic):Bool {
		return ensure(d).exists(keyOf(k));
	}

	public static function dictDelete(d:Map<String, Dynamic>, k:Dynamic):Bool {
		return ensure(d).remove(keyOf(k));
	}

	public static function dictKeys(d:Map<String, Dynamic>):Array<String> {
		return [for (k in ensure(d).keys()) k];
	}

	/** Values as a Dynamic array; checker deliberately leaves this untyped. */
	public static function dictValues(d:Map<String, Dynamic>):Array<Dynamic> {
		return [for (v in ensure(d)) v];
	}

	public static function dictSize(d:Map<String, Dynamic>):Int {
		var n = 0;
		for (_ in ensure(d).keys()) n++;
		return n;
	}

	static function ensure(d:Map<String, Dynamic>):Map<String, Dynamic> {
		return d != null ? d : new Map();
	}

	static inline function keyOf(k:Dynamic):String {
		return Std.string(k);
	}
}
