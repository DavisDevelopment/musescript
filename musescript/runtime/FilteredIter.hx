package musescript.runtime;

class FilteredIter implements MuseIter {
	var src:MuseIter;
	var pred:Dynamic->Bool;
	public function new(src:MuseIter, pred:Dynamic->Bool) { this.src = src; this.pred = pred; }
	public function next():IterResult<Dynamic> {
		while (true) {
			switch (src.next()) {
				case Done: return Done;
				case Value(v): if (pred(v)) return Value(v);
				case Await(r): return Await(function() {
					switch (r()) {
						case Done: return Done;
						case Value(v): return pred(v) ? Value(v) : this.next();
						case Await(r2): return Await(r2);
					}
				});
			}
		}
	}
}
