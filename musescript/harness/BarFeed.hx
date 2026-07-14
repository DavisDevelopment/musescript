package musescript.harness;

import musescript.runtime.MuseIter;
import musescript.runtime.IterResult;

/**
 * OHLCV feed as MuseIter<Bar>.
 */
class BarFeed implements MuseIter {
	var bars:Array<Bar>;
	var i:Int;

	public function new(bars:Array<Bar>) {
		this.bars = bars != null ? bars : [];
		this.i = 0;
	}

	public function next():IterResult<Dynamic> {
		if (i >= bars.length) return Done;
		return Value(bars[i++]);
	}

	public function reset():Void i = 0;

	public function length():Int return bars.length;

	public function all():Array<Bar> return bars;

	public static function synthetic(n:Int = 200, ?seed:Int = 1):BarFeed {
		var bars:Array<Bar> = [];
		var price = 100.0;
		var rng = seed;
		for (i in 0...n) {
			rng = (rng * 1103515245 + 12345) & 0x7fffffff;
			var noise = ((rng % 1000) / 1000.0 - 0.5) * 2.0;
			var o = price;
			var c = price * (1 + noise * 0.01);
			var h = Math.max(o, c) * 1.002;
			var l = Math.min(o, c) * 0.998;
			var v = 1000.0 + (rng % 500);
			bars.push({ open: o, high: h, low: l, close: c, volume: v, time: i * 60.0, index: i });
			price = c;
		}
		return new BarFeed(bars);
	}
}
