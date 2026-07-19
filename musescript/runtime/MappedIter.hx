package musescript.runtime;

class MappedIter implements MuseIter {
	var src:MuseIter;
	var f:Dynamic->Dynamic;

	public function new(src:MuseIter, f:Dynamic->Dynamic) {
		this.src = src; 
		this.f = f; 
	}

	/**
	 * TODO: maybe inline (not sure if latest Haxe makes this possible / a good idea)
	 */
	public function next():IterResult<Dynamic> {
		return switch (src.next()) {
			case Done: Done;
			case Value(v): Value(f(v));
			case Await(r): Await(function() {
				return switch (r()) {
					case Done: Done;
					case Value(v): Value(f(v));
					case Await(r2): Await(r2);
				};
			});
		};
	}
}
