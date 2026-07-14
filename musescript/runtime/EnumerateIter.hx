package musescript.runtime;

/** Yields `{ i, v }` for each element (0-based index). */
class EnumerateIter implements MuseIter {
	var src:MuseIter;
	var i:Int;
	public function new(src:MuseIter) {
		this.src = src;
		this.i = 0;
	}
	public function next():IterResult<Dynamic> {
		return switch (src.next()) {
			case Done: Done;
			case Value(v): Value({ i: i++, v: v });
			case Await(r): Await(function() {
				return r();
			});
		};
	}
}
