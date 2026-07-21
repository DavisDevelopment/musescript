package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD D-Wave — ported from wickra-core's `TdDWave`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_dwave.rs).
 *
 * A streaming swing-wave counter labelling the market's swing sequence with
 * an Elliott-style 1–5 impulse / A–C correction count. Alternating swing
 * pivots are detected with a symmetric fractal of half-width `strength`;
 * each newly-confirmed alternating leg advances the counter through the
 * eight-leg cycle (1..8, where 6/7/8 = corrective A/B/C). Same-direction
 * pivots only extend the current leg's extreme.
 */
class TdDwave implements MuseIndicator<Bar, Float> {
	var strength:Int;
	var window:Array<Bar>;
	var lastIsHigh:Null<Bool>;
	var lastExtreme:Float;
	var wave:Int;
	var lastValue:Null<Float>;

	public function new(strength:Int) {
		if (strength <= 0) throw "TdDwave: strength must be > 0";
		this.strength = strength;
		reset();
	}

	/** Configured fractal strength. */
	public function getStrength():Int return strength;

	/** Current wave number if available. */
	public function value():Null<Float> return lastValue;

	function advance(isHigh:Bool, price:Float):Void {
		if (lastIsHigh != null && lastIsHigh == isHigh) {
			// Same-direction extreme: extend the current leg if more extreme.
			var extends_ = isHigh ? price > lastExtreme : price < lastExtreme;
			if (extends_) lastExtreme = price;
		} else {
			// A new alternating leg: advance the wave counter (1..8 cycle).
			wave = wave % 8 + 1;
			lastIsHigh = isHigh;
			lastExtreme = price;
			lastValue = wave;
		}
	}

	public function update(bar:Bar):Null<Float> {
		var span = 2 * strength + 1;
		if (window.length == span) window.shift();
		window.push(bar);
		if (window.length == span) {
			var center = window[strength];
			var isHigh = true, isLow = true;
			for (i in 0...window.length) {
				if (i == strength) continue;
				if (!(window[i].high < center.high)) isHigh = false;
				if (!(window[i].low > center.low)) isLow = false;
			}
			if (isHigh && !isLow) advance(true, center.high);
			else if (isLow && !isHigh) advance(false, center.low);
		}
		return lastValue;
	}

	public function reset():Void {
		window = [];
		lastIsHigh = null;
		lastExtreme = 0.0;
		wave = 0;
		lastValue = null;
	}

	public function warmupPeriod():Int return 2 * strength + 1;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDDWave";

	public static function spec():IndicatorSpec {
		return {
			name: "td_dwave", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var s = IndicatorCache.intArg(args, 0, 2);
				return IndicatorCache.evalBar(h, "td_dwave:" + s, Math.NaN,
					() -> new TdDwave(s), (i, b) -> (cast i : TdDwave).update(b));
			}
		};
	}
}
