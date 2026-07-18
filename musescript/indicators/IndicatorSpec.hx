package musescript.indicators;

import musescript.harness.HarnessContext;
import musescript.types.MuseType;

/**
 * Everything the engine needs to know about one ported indicator, provided by
 * a `static function spec():IndicatorSpec` on the indicator's own class — the
 * single source of truth that `WickraBuiltins.install`, `BuiltinSigs`, AND
 * `JsBackend` dispatch all derive from (ROADMAP.md epic 9).
 *
 * The point is zero shared-file edits per indicator: adding one is `drop a
 * file in musescript/indicators/lib/ + implement MuseIndicator + return a
 * spec()`. `IndicatorRegistryMacro` collects every `lib/` file's `spec()` at
 * compile time, so nothing hand-maintained lists indicators — which is what
 * makes porting all 514 across parallel workers conflict-free (no two ports
 * ever touch the same file).
 */
typedef IndicatorSpec = {
	/** MuseScript builtin name (e.g. "obv", "williams_r"). */
	var name:String;
	/** Typed argument signature (BuiltinSigs entry). */
	var args:Array<MuseType>;
	/** Return type (TScalar, or TObject([...]) for multi-output indicators). */
	var ret:MuseType;
	/** Minimum required args (trailing optionals allowed above this). */
	var minArgs:Int;
	/**
	 * Per-bar evaluation: pull this indicator's input from the harness's
	 * current bar / resolved series, feed the cached streaming instance, and
	 * return the latest value (NaN or a NaN-filled struct during warmup).
	 * Implemented with the IndicatorCache helpers so the streaming state is
	 * cached per callsite — the same "one live object per callsite, fed once
	 * per new bar" discipline the legacy IndicatorColumns uses.
	 */
	var eval:HarnessContext->Array<Dynamic>->Dynamic;
}
