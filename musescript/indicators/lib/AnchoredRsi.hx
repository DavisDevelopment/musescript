package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Anchored RSI — ported from wickra-core's `AnchoredRsi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/anchored_rsi.rs).
 *
 * A cumulative Relative Strength Index whose averaging begins at a user-chosen
 * anchor bar rather than over a fixed Wilder period. The anchor is set at runtime;
 * calling `setAnchor()` re-anchors at the next bar, clearing running sums.
 *
 * RSI_t = 100 - 100 / (1 + Σ gains / Σ losses)
 *
 * The first bar of a fresh anchor window only seeds the previous close; the first
 * value follows on the second bar (warmup period 2).
 */
class AnchoredRsi implements MuseIndicator<Float, Float> {
	var prevClose:Null<Float>;
	var sumGain:Float;
	var sumLoss:Float;
	var lastValue:Null<Float>;
	var pendingAnchor:Bool;

	public function new() {
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return lastValue;
		}

		if (pendingAnchor) {
			prevClose = null;
			sumGain = 0.0;
			sumLoss = 0.0;
			lastValue = null;
			pendingAnchor = false;
		}

		if (prevClose == null) {
			prevClose = input;
			return null;
		}

		var diff = input - prevClose;
		prevClose = input;

		if (diff > 0.0) {
			sumGain += diff;
		} else if (diff < 0.0) {
			sumLoss -= diff;
		}

		var value = rsiFromSums(sumGain, sumLoss);
		lastValue = value;
		return value;
	}

	function rsiFromSums(sumGain:Float, sumLoss:Float):Float {
		if (sumLoss == 0.0) {
			if (sumGain == 0.0) {
				return 50.0; // No movement; standard convention
			} else {
				return 100.0;
			}
		} else {
			var rs = sumGain / sumLoss;
			return 100.0 - 100.0 / (1.0 + rs);
		}
	}

	public function reset():Void {
		prevClose = null;
		sumGain = 0.0;
		sumLoss = 0.0;
		lastValue = null;
		pendingAnchor = false;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return lastValue != null;
	public function name():String return "AnchoredRsi";

	public function setAnchor():Void {
		pendingAnchor = true;
	}

	public static function spec():IndicatorSpec {
		return {
			name: "anchored_rsi", args: [TSeries], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "anchored_rsi:" + series, series, Math.NaN,
					() -> new AnchoredRsi(), (i, v) -> (cast i : AnchoredRsi).update(v));
			}
		};
	}
}
