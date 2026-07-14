package musescript.runtime;

class TakeIter implements MuseIter {
	var src:MuseIter;
	var left:Int;
	public function new(src:MuseIter, n:Int) { this.src = src; this.left = n; }
	public function next():IterResult<Dynamic> {
		if (left <= 0) return Done;
		return switch (src.next()) {
			case Done: Done;
			case Value(v): left--; Value(v);
			case Await(r): Await(function() {
				return r();
			});
		};
	}
}
