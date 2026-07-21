package musescript.evo;

import musescript.indicators.IndicatorRegistry;
import musescript.types.MuseType;

/**
 * The wide, registry-derived counterpart to `Palette.INDS`'s closed 12-name
 * list. `Palette` stays exactly as-is (it's the documented mirror of
 * musegene/palette.py -- changing it would desync the Python side and
 * invalidate any already-persisted genome using it), so this is purely
 * ADDITIVE: an opt-in wider vocabulary a `Variation` can be pointed at
 * instead, covering every ported `ta` indicator that structurally fits
 * `SeriesNode.SInd`'s `(field_series, window) -> Scalar` shape.
 *
 * Nothing in the render/fitness/canonical path needed to change for this --
 * `Expand.series()` already renders `SInd(name, ...)` as a plain
 * `'$name("$field", $window)'` call for ANY name, with no hardcoded list.
 * The vocabulary was only ever closed at the GROWTH step (Variation.hx
 * picking from `Palette.INDS`), which is the one place this plugs in.
 */
class RegistryPalette {
	static var cached:Array<String>;

	/**
	 * Every registered indicator whose signature is exactly `[TSeries, TWindow] -> TScalar`
	 * (optionally with more TRAILING args, since SInd only ever supplies 2 -- an indicator
	 * that REQUIRES a 3rd arg wouldn't get a valid call from SInd alone and is excluded).
	 * Multi-output (TObject) returns, pair-series inputs, and indicator-of-indicator-only
	 * shapes aren't representable by SInd's (field, window) constructor and are excluded too
	 * -- covering those needs a richer node shape than SInd, not a bigger name list.
	 */
	public static function compatibleNames():Array<String> {
		if (cached != null) return cached;
		var seen = new Map<String, Bool>();
		var out:Array<String> = [];
		// Palette.INDS's legacy 12 (sma/ema/rsi/...) are core MuseScript builtins that predate
		// the Wickra port project -- they're dispatched via TradeBuiltins/BuiltinSigs directly,
		// never through IndicatorRegistry, so the registry scan below can't see them. The wide
		// pool is a SUPERSET of the legacy one, not a replacement, so they're seeded in first.
		for (n in Palette.INDS) {
			if (seen.exists(n)) continue;
			seen.set(n, true);
			out.push(n);
		}
		for (name => spec in IndicatorRegistry.all()) {
			if (seen.exists(name)) continue;
			if (spec.args.length < 2) continue;
			if (!Type.enumEq(spec.args[0], TSeries)) continue;
			if (!Type.enumEq(spec.args[1], TWindow)) continue;
			if (!Type.enumEq(spec.ret, TScalar)) continue;
			if (spec.minArgs > 2) continue; // a 3rd+ arg would be REQUIRED; SInd never supplies one
			seen.set(name, true);
			out.push(name);
		}
		out.sort(Reflect.compare);
		cached = out;
		return out;
	}
}
