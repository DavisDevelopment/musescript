package musescript.indicators.geom;

import musescript.harness.Bar;
import musescript.indicators.lib.ZigZag;

/**
 * Adapts ZigZag confirmations into PivotRing / PivotPoint Confirmed swings.
 * Emits only on ZigZag reversal bars (pulse), matching ZigZag's own contract.
 */
class ZigZagSwingAdapter {
	var zz:ZigZag;
	var ring:PivotRing;
	var barsSeen:Int;
	var lastConfirmed:Bool;

	public function new(threshold:Float = 0.05, capacity:Int = 16) {
		zz = new ZigZag(threshold);
		ring = new PivotRing(capacity);
		reset();
	}

	public function pivotCount():Int return ring.length;
	public inline function pivotAt(i:Int):PivotPoint return ring.at(i);
	public function didConfirm():Bool return lastConfirmed;
	public function getBarsSeen():Int return barsSeen;

	public function update(bar:Bar):Bool {
		var out = zz.update(bar);
		barsSeen++;
		lastConfirmed = false;
		if (out == null) return false;
		// ZigZag does not expose the extreme bar index; approximate as previous bar.
		var extremeBar = barsSeen - 2;
		if (extremeBar < 0) extremeBar = 0;
		ring.push(new PivotPoint(out.swing, out.direction, extremeBar, Confirmed));
		lastConfirmed = true;
		return true;
	}

	public function reset():Void {
		zz.reset();
		ring.clear();
		barsSeen = 0;
		lastConfirmed = false;
	}

	public function getPivots():Array<PivotPoint> return ring.toArray();
}
