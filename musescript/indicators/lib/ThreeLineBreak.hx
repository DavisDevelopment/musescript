package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Three Line Break — ported from wickra-core's `ThreeLineBreak`
 * (vendor/wickra/crates/wickra-core/src/indicators/three_line_break.rs).
 *
 * The trend direction of a line-break ("kakushi") chart, where a reversal
 * requires the close to break the extreme of the last `lines` lines:
 *
 *   continue the trend when close exceeds the prior line's end
 *   reverse the trend when close breaks beyond the extreme of the last `lines` lines
 *   output = current line direction: +1 (up), −1 (down)
 *
 * The first bar seeds the reference price; the direction is emitted once the
 * first line is drawn (data-dependent; `warmupPeriod` returns the minimum 2).
 */
class ThreeLineBreak implements MuseIndicator<Bar, Float> {
	var linesCount:Int;
	var lineValues:Array<Float>;
	var dir:Int;
	var last:Null<Float>;

	public function new(lines:Int) {
		if (lines <= 0) throw "ThreeLineBreak: lines must be > 0";
		this.linesCount = lines;
		lineValues = [];
		dir = 0;
		last = null;
	}

	/** Configured number of lines required to reverse. */
	public function lines():Int return linesCount;

	/** Current direction if available. */
	public function value():Null<Float> return last;

	function pushLine(close:Float, newDir:Int):Void {
		dir = newDir;
		lineValues.push(close);
		if (lineValues.length > linesCount) lineValues.shift();
	}

	public function update(candle:Bar):Null<Float> {
		var close = candle.close;
		if (lineValues.length == 0) {
			// Seed the reference price; no line yet.
			lineValues.push(close);
			return null;
		}
		var prior = lineValues[lineValues.length - 1];
		if (dir >= 0) {
			if (close > prior) {
				pushLine(close, 1);
			} else {
				var low = Math.POSITIVE_INFINITY;
				for (v in lineValues) low = Math.min(low, v);
				if (close < low) pushLine(close, -1);
			}
		} else if (close < prior) {
			pushLine(close, -1);
		} else {
			var high = Math.NEGATIVE_INFINITY;
			for (v in lineValues) high = Math.max(high, v);
			if (close > high) pushLine(close, 1);
		}
		if (dir == 0) return null;
		var v:Float = dir;
		last = v;
		return v;
	}

	public function reset():Void {
		lineValues = [];
		dir = 0;
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "ThreeLineBreak";

	public static function spec():IndicatorSpec {
		return {
			name: "three_line_break", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var l = IndicatorCache.intArg(args, 0, 3);
				return IndicatorCache.evalBar(h, "three_line_break:" + l, Math.NaN,
					() -> new ThreeLineBreak(l), (i, b) -> (cast i : ThreeLineBreak).update(b));
			}
		};
	}
}
