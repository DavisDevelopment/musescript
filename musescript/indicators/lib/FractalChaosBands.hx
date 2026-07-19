package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fractal Chaos Bands output: the most recently confirmed fractal high/low. */
typedef FractalChaosBandsOutput = {
	var upper:Float;
	var lower:Float;
}

/**
 * Fractal Chaos Bands (Bill Williams): bands held at the most recently
 * *confirmed* 5-bar fractal high/low, updating only when a new fractal
 * forms and holding flat otherwise.
 *
 * A bar at position `i` is a fractal high if its high is the strictest
 * maximum among the 5 bars `[i-2, i+2]`; a fractal low is the mirror case
 * with lows. Since a fractal at `i` needs the 2 bars *after* it to confirm,
 * the band only updates 2 bars after the fractal actually occurred
 * (non-repainting).
 */
class FractalChaosBands implements MuseIndicator<Bar, FractalChaosBandsOutput> {
	var window:Array<Bar>;
	var upper:Null<Float>;
	var lower:Null<Float>;

	public function new() {
		window = [];
		upper = null;
		lower = null;
	}

	public function update(bar:Bar):Null<FractalChaosBandsOutput> {
		window.push(bar);
		if (window.length > 5) window.shift();

		if (window.length == 5) {
			var mid = window[2];
			var isFractalHigh = true;
			var isFractalLow = true;
			for (i in [0, 1, 3, 4]) {
				if (window[i].high >= mid.high) isFractalHigh = false;
				if (window[i].low <= mid.low) isFractalLow = false;
			}
			if (isFractalHigh) upper = mid.high;
			if (isFractalLow) lower = mid.low;
		}

		if (upper == null || lower == null) return null;
		return { upper: upper, lower: lower };
	}

	public function reset():Void {
		window = [];
		upper = null;
		lower = null;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return upper != null && lower != null;
	public function name():String return "FractalChaosBands";

	public static function spec():IndicatorSpec {
		return {
			name: "fractal_chaos_bands", args: [], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "fractal_chaos_bands", { upper: Math.NaN, lower: Math.NaN },
				() -> new FractalChaosBands(), (i, b) -> (cast i : FractalChaosBands).update(b))
		};
	}
}
