package musescript.indicators.geom;

import musescript.harness.Bar;
import musescript.indicators.lib.WilliamsFractals;

/**
 * Adapts Williams Fractals confirmations into the SwingGraph / PivotPoint world.
 * Fractals confirm two bars late; each up/down emit becomes a Confirmed pivot
 * tagged at the centre bar of the five-bar window (barsSeen - 3).
 *
 * Does not replace SwingGraph percent-threshold detection — parallel feed for
 * fractal-anchored facades.
 */
class FractalSwingAdapter {
	var wf:WilliamsFractals;
	var ring:PivotRing;
	var barsSeen:Int;
	var lastConfirmed:Bool;

	public function new(capacity:Int = 16) {
		wf = new WilliamsFractals();
		ring = new PivotRing(capacity);
		reset();
	}

	public function pivotCount():Int return ring.length;
	public inline function pivotAt(i:Int):PivotPoint return ring.at(i);
	public function didConfirm():Bool return lastConfirmed;
	public function getBarsSeen():Int return barsSeen;

	public function update(bar:Bar):Bool {
		barsSeen++;
		lastConfirmed = false;
		var o = wf.update(bar);
		if (o == null) return false;
		// Centre of five-bar window is two bars back from the confirming bar.
		var centreBar = barsSeen - 3;
		if (o.up != null) {
			ring.push(new PivotPoint(o.up, 1.0, centreBar, Confirmed));
			lastConfirmed = true;
		}
		if (o.down != null) {
			ring.push(new PivotPoint(o.down, -1.0, centreBar, Confirmed));
			lastConfirmed = true;
		}
		return lastConfirmed;
	}

	public function reset():Void {
		wf.reset();
		ring.clear();
		barsSeen = 0;
		lastConfirmed = false;
	}

	public function getPivots():Array<PivotPoint> return ring.toArray();
}
