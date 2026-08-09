package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/** Spread Bollinger Bands output: middle/upper/lower bands plus %b. */
typedef SpreadBollingerBandsOutput = {
	/** Middle band: the rolling mean of the spread. */
	var middle:Float;
	/** Upper band: middle + numStd · σ. */
	var upper:Float;
	/** Lower band: middle − numStd · σ. */
	var lower:Float;
	/** %b: (s − lower) / (upper − lower); 0.5 when the band has zero width. */
	var percentB:Float;
}

/**
 * Bollinger bands on the spread a − b of two series — ported from wickra-core's
 * `SpreadBollingerBands`
 * (vendor/wickra/crates/wickra-core/src/indicators/spread_bollinger_bands.rs).
 *
 * Each update takes one (a, b) price pair, forms the spread s_t = a_t − b_t,
 * and over the trailing window of `period` spreads builds a classic Bollinger
 * envelope (mean ± numStd · stddev) plus the %b location statistic. A flat
 * spread yields a zero-width band and %b is reported as the neutral 0.5.
 */
class SpreadBollingerBands implements MuseIndicator<SpreadBbPair, SpreadBollingerBandsOutput> {
	var period:Int;
	var numStd:Float;
	var window:RingBuffer<Float>;
	var sum:Float;
	var sumSq:Float;

	public function new(period:Int, numStd:Float) {
		if (period < 2) throw "SpreadBollingerBands: period must be >= 2";
		if (!Math.isFinite(numStd) || numStd <= 0.0) throw "SpreadBollingerBands: num_std must be > 0";
		this.period = period;
		this.numStd = numStd;
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
	}

	public function update(input:SpreadBbPair):Null<SpreadBollingerBandsOutput> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		var spread = a - b;
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(spread);
		if (wasFull) {
			sum -= old;
			sumSq -= old * old;
		}
		sum += spread;
		sumSq += spread * spread;
		if (window.length < period) return null;
		var n:Float = period;
		var middle = sum / n;
		var variance = Math.max(sumSq / n - middle * middle, 0.0);
		var sigma = Math.sqrt(variance);
		var halfWidth = numStd * sigma;
		var upper = middle + halfWidth;
		var lower = middle - halfWidth;
		var percentB = halfWidth == 0.0 ? 0.5 : (spread - lower) / (upper - lower);
		return {middle: middle, upper: upper, lower: lower, percentB: percentB};
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sum = 0.0;
		sumSq = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SpreadBollingerBands";

	public static function spec():IndicatorSpec {
		return {
			name: "spread_bollinger_bands", args: [TSeries, TSeries, TWindow, TScalar], ret: TObject([
				{name: "middle", ty: TScalar}, {name: "upper", ty: TScalar},
				{name: "lower", ty: TScalar}, {name: "percentB", ty: TScalar}
			]), minArgs: 2,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var ns = IndicatorCache.floatArg(args, 3, 2.0);
				var key = "spread_bollinger_bands:" + seriesA + ":" + seriesB + ":" + p + ":" + ns;
				return IndicatorCache.evalPair(h, key,
					seriesA, seriesB,
					{middle: Math.NaN, upper: Math.NaN, lower: Math.NaN, percentB: Math.NaN},
					() -> new SpreadBollingerBands(p, ns),
					(i, a, b) -> (cast i : SpreadBollingerBands).update({a: a, b: b}));
			}
		};
	}
}

@:structInit
class SpreadBbPair {
	public var a:Float;
	public var b:Float;
}
