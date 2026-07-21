package musescript.runtime;

class MappedIter implements MuseIter {
	var src:MuseIter;
	var f:Dynamic->Dynamic;

	public function new(src:MuseIter, f:Dynamic->Dynamic) {
		this.src = src; 
		this.f = f; 
	}

	public function next():IterResult<Dynamic> {
		return mapResult(src.next());
	}

	/** Apply `f` to the produced value at whatever await-depth it surfaces.
	 * Recurring through nested Awaits (rather than passing an inner Await
	 * through raw) keeps the map honest for sources that pump more than once
	 * before yielding — e.g. an empty-then-filled StreamIter. */
	function mapResult(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v): Value(f(v));
			case Await(cont): Await(function() return mapResult(cont()));
		};
	}
}
