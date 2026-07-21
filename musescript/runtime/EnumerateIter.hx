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
		return step(src.next());
	}

	/** Attach and advance the index at any await-depth. The old await branch
	 * returned `r()` raw, so values arriving via Await got no `{i, v}` wrapper
	 * and skipped the counter. */
	function step(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v): Value({ i: i++, v: v });
			case Await(cont): Await(function() return step(cont()));
		};
	}
}
