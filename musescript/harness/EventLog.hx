package musescript.harness;

import musescript.runtime.MuseIter;
import musescript.runtime.IterResult;

/**
 * Recorded events for deterministic backtest replay.
 */
class EventLog implements MuseIter {
	public var events:Array<Dynamic>;
	var i:Int;
	public function new(?events:Array<Dynamic>) {
		this.events = events != null ? events : [];
		this.i = 0;
	}
	public function push(e:Dynamic):Void events.push(e);
	public function reset():Void i = 0;
	public function next():IterResult<Dynamic> {
		if (i >= events.length) return Done;
		return Value(events[i++]);
	}
	public function asIter():MuseIter return this;
}
