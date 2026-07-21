package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Trade Volume Index — ported from wickra-core's `TradeVolumeIndex`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/trade_volume_index.rs).
 *
 *   change = close - prev_close
 *   if  change >  min_tick:  direction = +1
 *   if  change < -min_tick:  direction = -1
 *   else:                    direction unchanged   (price is "churning")
 *   TVI_t = TVI_{t-1} + direction * volume
 *
 * The minimum tick value is a dead-band: only moves larger than `minTick`
 * flip the accumulation direction. The first candle seeds the reference
 * close and emits nothing.
 */
class TradeVolumeIndex implements MuseIndicator<Bar, Float> {
	public var minTick(default, null):Float;
	var prevClose:Null<Float>;
	var direction:Float;
	var tvi:Float;
	var last:Null<Float>;

	public function new(minTick:Float) {
		if (!Math.isFinite(minTick) || minTick < 0.0)
			throw "TradeVolumeIndex: min_tick must be finite and non-negative";
		this.minTick = minTick;
		prevClose = null;
		direction = 0.0;
		tvi = 0.0;
		last = null;
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return last;

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = bar.close;
			return null;
		}
		var change = bar.close - prevClose;
		if (change > minTick) {
			direction = 1.0;
		} else if (change < -minTick) {
			direction = -1.0;
		}
		// Otherwise the direction is held from the previous bar (or 0 before the
		// first decisive move), so a churning price keeps its last lean.
		tvi += direction * bar.volume;
		prevClose = bar.close;
		last = tvi;
		return tvi;
	}

	public function reset():Void {
		prevClose = null;
		direction = 0.0;
		tvi = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "TradeVolumeIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "trade_volume_index", args: [TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var mt = IndicatorCache.floatArg(args, 0, 0.5);
				return IndicatorCache.evalBar(h, "trade_volume_index:" + mt, Math.NaN,
					() -> new TradeVolumeIndex(mt), (i, b) -> (cast i : TradeVolumeIndex).update(b));
			}
		};
	}
}
