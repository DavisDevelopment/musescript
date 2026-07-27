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

	/**
	 * Populate once from the compile-time collector, FAILING LOUDLY on a duplicate `name`.
	 *
	 * This used to be a bare `specs.set(s.name, s)`, i.e. a silent last-wins overwrite: two
	 * indicators claiming the same builtin name would leave exactly one of them reachable,
	 * with no error anywhere, and which one survived depended on the collector's directory
	 * sort order. That is a genuinely likely failure here rather than a hypothetical — the
	 * registry is DIRECTORY-SCANNED (adding an indicator is "drop a file in lib/", by design)
	 * and these ports land in large parallel batches, so two authors picking the same
	 * `name:` never collides in git and would only show up as an indicator that mysteriously
	 * isn't there. `WickraBuiltins.install` / `BuiltinSigs` / `JsBackend` dispatch all read
	 * from this map, so a silent drop propagates everywhere at once.
	 *
	 * All 452 current indicators are collision-free; this keeps it that way by construction
	 * instead of by discipline.
	 */
	static function ensure():Void {
		if (specs != null) return;
		specs = new Map();
		for (s in (IndicatorRegistryMacro.collect() : Array<IndicatorSpec>)) {
			if (specs.exists(s.name))
				throw 'IndicatorRegistry: duplicate indicator name "${s.name}" — two classes in '
					+ 'musescript/indicators/lib/ both register it, so one would be silently '
					+ 'unreachable. Rename one of them.';
			specs.set(s.name, s);
		}
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
