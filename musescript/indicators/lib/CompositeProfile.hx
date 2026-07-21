package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** CompositeProfile output: POC, VAH, VAL. */
typedef CompositeProfileOutput = {
	var poc:Float;
	var vah:Float;
	var val:Float;
}

/**
 * Composite Profile — ported from wickra-core's `CompositeProfile`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/composite_profile.rs).
 *
 * A multi-session volume profile reduced to its point of control and value area,
 * built over a long composite window.
 */
class CompositeProfile implements MuseIndicator<Bar, CompositeProfileOutput> {
	var period:Int;
	var bins:Int;
	var valueAreaPct:Float;
	var window:Array<Bar>;
	var last:Null<CompositeProfileOutput>;

	public function new(period:Int, bins:Int, valueAreaPct:Float) {
		if (period <= 0 || bins <= 0) throw "CompositeProfile: period and bins must be > 0";
		if (!Math.isFinite(valueAreaPct) || valueAreaPct <= 0.0 || valueAreaPct > 1.0) {
			throw "CompositeProfile: valueAreaPct must be in (0, 1]";
		}
		this.period = period;
		this.bins = bins;
		this.valueAreaPct = valueAreaPct;
		this.window = [];
		this.last = null;
	}

	public function update(bar:Bar):Null<CompositeProfileOutput> {
		if (window.length == period) {
			window.shift();
		}
		window.push(bar);
		if (window.length < period) return null;

		var out = compute();
		this.last = out;
		return out;
	}

	private function compute():CompositeProfileOutput {
		var low = Math.POSITIVE_INFINITY;
		var high = Math.NEGATIVE_INFINITY;

		for (b in window) {
			low = Math.min(low, b.low);
			high = Math.max(high, b.high);
		}

		var span = high - low;
		if (span <= 0.0) {
			return {poc: low, vah: low, val: low};
		}

		var width = span / bins;
		var hist = [for (i in 0...bins) 0.0];

		// Build histogram
		for (b in window) {
			if (b.volume == 0.0) continue;

			var loIdx = Std.int(Math.min((b.low - low) / width, bins - 1));
			var hiIdx = Std.int(Math.min((b.high - low) / width, bins - 1));

			var share = b.volume / (hiIdx - loIdx + 1);
			for (bin in loIdx...(hiIdx + 1)) {
				hist[bin] += share;
			}
		}

		// Find POC
		var total = 0.0;
		for (h in hist) total += h;

		var pocIdx = 0;
		var pocVol = Math.NEGATIVE_INFINITY;
		for (i in 0...hist.length) {
			if (hist[i] > pocVol) {
				pocVol = hist[i];
				pocIdx = i;
			}
		}

		// Expand from POC to find value area
		var target = total * valueAreaPct;
		var acc = hist[pocIdx];
		var top = pocIdx;
		var bottom = pocIdx;

		while (acc < target && (top < bins - 1 || bottom > 0)) {
			var above = (top < bins - 1) ? hist[top + 1] : Math.NEGATIVE_INFINITY;
			var below = (bottom > 0) ? hist[bottom - 1] : Math.NEGATIVE_INFINITY;

			if (above >= below) {
				top++;
				acc += hist[top];
			} else {
				bottom--;
				acc += hist[bottom];
			}
		}

		var centre = function(idx:Int):Float {
			return low + (idx + 0.5) * width;
		};

		return {
			poc: centre(pocIdx),
			vah: centre(top),
			val: centre(bottom)
		};
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "CompositeProfile";

	public static function spec():IndicatorSpec {
		return {
			name: "composite_profile", args: [TWindow, TWindow, TScalar], ret: TObject([
				{name: "poc", ty: TScalar}, {name: "vah", ty: TScalar}, {name: "val", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 100);
				var b = IndicatorCache.intArg(args, 1, 50);
				var v = IndicatorCache.floatArg(args, 2, 0.7);
				var nanFill:CompositeProfileOutput = {poc: Math.NaN, vah: Math.NaN, val: Math.NaN};
				return IndicatorCache.evalBar(h, "composite_profile:" + p + ":" + b + ":" + v, nanFill,
					() -> new CompositeProfile(p, b, v), (i, bar) -> (cast i : CompositeProfile).update(bar));
			}
		};
	}
}
