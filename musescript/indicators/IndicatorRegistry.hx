package musescript.indicators;

/**
 * Runtime registry of every ported indicator's `IndicatorSpec`, populated once
 * from the compile-time collector (`IndicatorRegistryMacro.collect`). This is
 * the single source `WickraBuiltins.install`, `BuiltinSigs`, and `JsBackend`
 * dispatch all read from — so those three files never gain a per-indicator
 * edit, and the completeness test (`testRuntimeBuiltinsHaveTypedSignatures`)
 * passes by construction.
 */
class IndicatorRegistry {
	static var specs:Map<String, IndicatorSpec>;

	static function ensure():Void {
		if (specs != null) return;
		specs = new Map();
		for (s in (IndicatorRegistryMacro.collect() : Array<IndicatorSpec>))
			specs.set(s.name, s);
	}

	public static function get(name:String):Null<IndicatorSpec> {
		ensure();
		return specs.get(name);
	}

	public static function has(name:String):Bool {
		ensure();
		return specs.exists(name);
	}

	public static function all():Map<String, IndicatorSpec> {
		ensure();
		return specs;
	}
}
