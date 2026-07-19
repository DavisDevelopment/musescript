package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Anchored VWAP — ported from wickra-core's `AnchoredVwap`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/anchored_vwap.rs).
 *
 * A cumulative Volume-Weighted Average Price whose accumulation begins at a
 * user-chosen anchor bar rather than the session open.
 *
 * AVWAP_t = Σ_{i ≥ anchor} (typical_price_i · volume_i) / Σ_{i ≥ anchor} volume_i
 *
 * Calling `setAnchor()` re-anchors at the next bar, clearing running sums.
 * The indicator emits `null` until the first anchored bar with volume > 0 is ingested.
 */
class AnchoredVwap implements MuseIndicator<Bar, Float> {
	var sumPv:Float;
	var sumV:Float;
	var hasEmitted:Bool;
	var pendingAnchor:Bool;

	public function new() {
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		if (pendingAnchor) {
			sumPv = 0.0;
			sumV = 0.0;
			hasEmitted = false;
			pendingAnchor = false;
		}

		var tp = (bar.high + bar.low + bar.close) / 3.0;
		sumPv += tp * bar.volume;
		sumV += bar.volume;

		if (sumV == 0.0) {
			return null;
		}
		hasEmitted = true;
		return sumPv / sumV;
	}

	public function reset():Void {
		sumPv = 0.0;
		sumV = 0.0;
		hasEmitted = false;
		pendingAnchor = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "AnchoredVwap";

	public function setAnchor():Void {
		pendingAnchor = true;
	}

	public static function spec():IndicatorSpec {
		return {
			name: "anchored_vwap", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "anchored_vwap", Math.NaN,
				() -> new AnchoredVwap(), (i, b) -> (cast i : AnchoredVwap).update(b))
		};
	}
}
