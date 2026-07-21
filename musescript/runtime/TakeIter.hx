package musescript.runtime;

class TakeIter implements MuseIter {
	var src:MuseIter;
	var left:Int;
	public function new(src:MuseIter, n:Int) { this.src = src; this.left = n; }
	public function next():IterResult<Dynamic> {
		if (left <= 0) return Done;
		return step(src.next());
	}

	/** Count the take-quota at any await-depth. The old await branch returned
	 * `r()` raw, so values arriving via Await were never counted — take(n) could
	 * over-yield. next()'s `left <= 0` guard caps the next pull. */
	function step(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v): left--; Value(v);
			case Await(cont): Await(function() return step(cont()));
		};
	}
}
