package musescript.indicators.geom;

/**
 * Fixed-capacity chronological pivot store — O(1) push / eviction, no
 * `Array.shift` on the hot path. Indexed access is absolute-from-oldest
 * (`at(0)` = oldest retained, `at(length-1)` = newest confirmed).
 *
 * Backed by a plain `Vector` of references (pivots are objects; prices stay
 * unboxed Float fields on each PivotPoint).
 */
class PivotRing {
	var data:haxe.ds.Vector<PivotPoint>;
	var head:Int = 0;
	var len:Int = 0;
	var cap:Int;

	public function new(capacity:Int) {
		if (capacity <= 0) throw "PivotRing: capacity must be > 0";
		cap = capacity;
		data = new haxe.ds.Vector<PivotPoint>(capacity);
	}

	public var length(get, never):Int;
	inline function get_length():Int return len;

	public var capacity(get, never):Int;
	inline function get_capacity():Int return cap;

	/** Append; once full, overwrite oldest. Returns evicted pivot or null. */
	public function push(p:PivotPoint):Null<PivotPoint> {
		if (len < cap) {
			data[len] = p;
			len++;
			return null;
		}
		var evicted = data[head];
		data[head] = p;
		head = (head + 1) % cap;
		return evicted;
	}

	/** Chronological index: 0 = oldest retained. */
	public inline function at(i:Int):PivotPoint {
		return data[(head + i) % cap];
	}

	/** Newest confirmed pivot (null if empty). */
	public function newest():Null<PivotPoint> {
		if (len == 0) return null;
		return at(len - 1);
	}

	public function clear():Void {
		head = 0;
		len = 0;
		for (i in 0...cap) data[i] = null;
	}

	/** Materialize chronological Array — pay once at an interop boundary. */
	public function toArray():Array<PivotPoint> {
		var out:Array<PivotPoint> = [];
		for (i in 0...len) out.push(at(i));
		return out;
	}
}
