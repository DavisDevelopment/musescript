package musescript.runtime;

class DropIter implements MuseIter {
	var src:MuseIter;
	var left:Int;
	public function new(src:MuseIter, n:Int) { this.src = src; this.left = n < 0 ? 0 : n; }
	public function next():IterResult<Dynamic> {
		while (true) {
			switch (src.next()) {
				case Done: return Done;
				case Value(v):
					if (left > 0) {
						left--;
						continue;
					}
					return Value(v);
				case Await(r):
					return Await(function() return step(r()));
			}
		}
	}

	/** Consume the drop-quota at any await-depth; a dropped value restarts the
	 * search via next(), a nested Await recurses instead of passing through raw. */
	function step(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v):
				if (left > 0) {
					left--;
					next();
				} else Value(v);
			case Await(cont): Await(function() return step(cont()));
		};
	}
}
