package musescript.indicators;

import musescript.harness.Bar;

/**
 * Money Flow Index — ported from wickra-core's `Mfi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/mfi.rs).
 *
 * A volume-weighted RSI: `MFI = 100 - 100 / (1 + positive_flow / negative_flow)`,
 * where money flow is `typical_price * volume`, classified positive when TP
 * rises and negative when it falls. The seed bar only establishes the first
 * previous typical price (no flow direction yet), so the first value lands
 * at `period + 1` bars, matching TA-Lib/pandas-ta. A fully flat window
 * (zero flow both sides) returns the neutral 50.
 */
class Mfi implements MuseIndicator<Bar, Float> {
	var period:Int;
	var hasPrevTp:Bool;
	var prevTp:Float;
	var posWindow:Array<Float>;
	var negWindow:Array<Float>;
	var posSum:Float;
	var negSum:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Mfi: period must be > 0";
		this.period = period;
		hasPrevTp = false;
		prevTp = 0.0;
		posWindow = [];
		negWindow = [];
		posSum = 0.0;
		negSum = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var tp = (bar.high + bar.low + bar.close) / 3.0;
		if (!hasPrevTp) {
			prevTp = tp;
			hasPrevTp = true;
			return null;
		}
		var mf = tp * bar.volume;
		var posFlow = 0.0, negFlow = 0.0;
		if (tp > prevTp) posFlow = mf;
		else if (tp < prevTp) negFlow = mf;

		if (posWindow.length == period) {
			posSum -= posWindow.shift();
			negSum -= negWindow.shift();
		}
		posWindow.push(posFlow);
		negWindow.push(negFlow);
		posSum += posFlow;
		negSum += negFlow;
		prevTp = tp;

		if (posWindow.length < period) return null;
		if (posSum == 0 && negSum == 0) return 50.0;
		if (negSum == 0) return 100.0;
		var mr = posSum / negSum;
		return 100.0 - 100.0 / (1.0 + mr);
	}

	public function reset():Void {
		hasPrevTp = false;
		prevTp = 0.0;
		posWindow = [];
		negWindow = [];
		posSum = 0.0;
		negSum = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return posWindow.length == period;
	public function name():String return "MFI";
}
