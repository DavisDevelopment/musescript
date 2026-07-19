package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Renko Trailing Stop — ported from wickra-core's `RenkoTrailingStop`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/renko_trailing_stop.rs).
 *
 * A trailing stop that follows a Renko-style brick anchor: the stop only moves
 * when price has advanced (or fallen) by at least one full `block_size`, and then
 * jumps the same fixed distance. The first input seeds a long anchor at the close.
 */
class RenkoTrailingStop implements MuseIndicator<Float, Float> {
	var blockSize:Float;
	var anchor:Null<Float>;
	var long:Bool;

	public function new(blockSize:Float) {
		if (!Math.isFinite(blockSize) || blockSize <= 0.0) 
			throw "RenkoTrailingStop: block_size must be > 0 and finite";
		this.blockSize = blockSize;
		this.anchor = null;
		this.long = true;
	}

	public function update(close:Float):Null<Float> {
		if (!Math.isFinite(close)) return null;

		var newAnchor:Float;
		if (anchor == null) {
			newAnchor = close;
		} else if (long) {
			var stop = anchor - blockSize;
			if (close < stop) {
				// Close through long stop -> flip to short
				long = false;
				newAnchor = close;
			} else {
				var blocks = Math.floor((close - anchor) / blockSize);
				if (blocks >= 1.0) {
					newAnchor = anchor + blocks * blockSize;
				} else {
					newAnchor = anchor;
				}
			}
		} else {
			var stop = anchor + blockSize;
			if (close > stop) {
				// Close through short stop -> flip to long
				long = true;
				newAnchor = close;
			} else {
				var blocks = Math.floor((anchor - close) / blockSize);
				if (blocks >= 1.0) {
					newAnchor = anchor - blocks * blockSize;
				} else {
					newAnchor = anchor;
				}
			}
		}

		anchor = newAnchor;
		var stop = if (long) anchor - blockSize else anchor + blockSize;
		return stop;
	}

	public function reset():Void {
		anchor = null;
		long = true;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return anchor != null;
	public function name():String return "RenkoTrailingStop";

	public static function spec():IndicatorSpec {
		return {
			name: "renko_trailing_stop", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.floatArg(args, 1, 1.0);
				return IndicatorCache.evalSeries(h, "renko_trailing_stop:" + series + ":" + p, series, Math.NaN,
					() -> new RenkoTrailingStop(p), (i, v) -> (cast i : RenkoTrailingStop).update(v));
			}
		};
	}
}
