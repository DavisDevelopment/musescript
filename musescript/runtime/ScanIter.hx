package musescript.runtime;

class ScanIter implements MuseIter {
	var src:MuseIter;
	var f:Dynamic->Dynamic->Dynamic;
	var acc:Dynamic;
	var hasAcc:Bool;

	public function new(src:MuseIter, init:Dynamic, f:Dynamic->Dynamic->Dynamic) {
		this.src = src;
		this.acc = init;
		this.f = f;
		this.hasAcc = true;
	}

	public function next():IterResult<Dynamic> {
		return step(src.next());
	}

	/** Fold at whatever await-depth the value surfaces; recurse through nested
	 * Awaits so the accumulator is never bypassed. */
	function step(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v):
				acc = f(acc, v);
				Value(acc);
			case Await(cont): Await(function() return step(cont()));
		};
	}
}
