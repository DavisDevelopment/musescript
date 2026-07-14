package musescript.runtime;

/** Half-open integer range `[start, end)`. */
class RangeIter implements MuseIter {
	var i:Int;
	var end:Int;
	public function new(start:Int, end:Int) {
		this.i = start;
		this.end = end;
	}
	public function next():IterResult<Dynamic> {
		if (i >= end) return Done;
		return Value(i++);
	}
}
