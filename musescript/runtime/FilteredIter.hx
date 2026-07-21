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
				case Await(r): return Await(function() return step(r()));
			}
		}
	}

	/** Re-apply the predicate at any await-depth; a rejected value restarts the
	 * search via next(), a nested Await recurses (not passed through raw). */
	function step(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v): pred(v) ? Value(v) : next();
			case Await(cont): Await(function() return step(cont()));
		};
	}
}
