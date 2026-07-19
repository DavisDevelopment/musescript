package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Andrews Pitchfork output: median, upper, lower lines. */
typedef AndrewsPitchforkOutput = {
	var median:Float;
	var upper:Float;
	var lower:Float;
}

/** A confirmed swing pivot: its bar index and price. */
private typedef Pivot = {
	var index:Float;
	var price:Float;
	var isHigh:Bool;
}

/**
 * Andrews Pitchfork — ported from wickra-core's `AndrewsPitchfork`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/andrews_pitchfork.rs).
 *
 * Detects alternating swing pivots using a symmetric fractal of half-width `strength`,
 * then projects the "fork" of three parallel lines from the three most recent
 * alternating swings:
 *
 * M  = midpoint of P1 and P2 (the two anchor pivots)
 * median(t) = P0 + slope·(t − t0)     where slope = (M − P0) / (M_t − t0)
 * upper/lower = median(t) offset by the vertical gap to the higher/lower anchor
 *
 * Readiness is data-dependent: the first output appears once three alternating
 * pivots have been confirmed.
 */
class AndrewsPitchfork implements MuseIndicator<Bar, AndrewsPitchforkOutput> {
	var strength:Int;
	var window:Array<Bar>;
	var pivots:Array<Pivot>;
	var count:Int;
	var last:Null<AndrewsPitchforkOutput>;

	public function new(strength:Int) {
		if (strength == 0) throw "AndrewsPitchfork: strength must be > 0";
		this.strength = strength;
		window = [];
		pivots = [];
		count = 0;
		last = null;
	}

	public function update(bar:Bar):Null<AndrewsPitchforkOutput> {
		count += 1;
		var span = 2 * strength + 1;

		if (window.length == span) {
			window.shift();
		}
		window.push(bar);

		// Check for pivot at the center position.
		if (window.length == span) {
			var centerIdx = strength;
			var center = window[centerIdx];

			var isHigh = true;
			var isLow = true;

			for (i in 0...window.length) {
				if (i != centerIdx) {
					if (window[i].high >= center.high) isHigh = false;
					if (window[i].low <= center.low) isLow = false;
				}
			}

			var centerBarIndex = (count - 1 - strength);

			if (isHigh && !isLow) {
				recordPivot({
					index: centerBarIndex,
					price: center.high,
					isHigh: true
				});
			} else if (isLow && !isHigh) {
				recordPivot({
					index: centerBarIndex,
					price: center.low,
					isHigh: false
				});
			}
		}

		var tc = (count - 1);
		if (pivots.length >= 3) {
			var out = project(tc);
			if (out != null) {
				last = out;
				return out;
			}
		}
		return null;
	}

	function recordPivot(pivot:Pivot):Void {
		if (pivots.length > 0) {
			var lastPivot = pivots[pivots.length - 1];
			if (lastPivot.isHigh == pivot.isHigh) {
				// Same kind: keep the more extreme one.
				var more_extreme = if (pivot.isHigh) {
					pivot.price > lastPivot.price;
				} else {
					pivot.price < lastPivot.price;
				};
				if (more_extreme) {
					pivots[pivots.length - 1] = pivot;
				}
				return;
			}
		}
		pivots.push(pivot);
		if (pivots.length > 3) {
			pivots.shift();
		}
	}

	function project(tc:Float):Null<AndrewsPitchforkOutput> {
		if (pivots.length < 3) return null;

		var p0 = pivots[0];
		var p1 = pivots[1];
		var p2 = pivots[2];

		var midT = (p1.index + p2.index) / 2.0;
		var midP = (p1.price + p2.price) / 2.0;
		var slope = (midP - p0.price) / (midT - p0.index);
		var median = p0.price + slope * (tc - p0.index);

		var off1 = p1.price - (p0.price + slope * (p1.index - p0.index));
		var off2 = p2.price - (p0.price + slope * (p2.index - p0.index));

		return {
			median: median,
			upper: median + Math.max(off1, off2),
			lower: median + Math.min(off1, off2)
		};
	}

	public function reset():Void {
		window = [];
		pivots = [];
		count = 0;
		last = null;
	}

	public function warmupPeriod():Int return 2 * strength + 1;
	public function isReady():Bool return last != null;
	public function name():String return "AndrewsPitchfork";

	public static function spec():IndicatorSpec {
		return {
			name: "andrews_pitchfork", args: [TWindow], ret: TObject([
				{name: "median", ty: TScalar}, {name: "upper", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var strength = IndicatorCache.intArg(args, 0, 2);
				return IndicatorCache.evalBar(h, "andrews_pitchfork:" + strength,
					{ median: Math.NaN, upper: Math.NaN, lower: Math.NaN },
					() -> new AndrewsPitchfork(strength), (i, b) -> (cast i : AndrewsPitchfork).update(b));
			}
		};
	}
}
