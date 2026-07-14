package musescript.runtime;

/**
 * Map each outer value through `f` (returning an iterable) and flatten one level via MuseIters.from.
 * Ἐκ τοῦ ἑνὸς πολλὰ, ἐκ τῶν πολλῶν ἓν πάλιν.
 */
class FlatMappedIter implements MuseIter {
	var src:MuseIter;
	var f:Dynamic->Dynamic;
	var inner:MuseIter;

	public function new(src:MuseIter, f:Dynamic->Dynamic) {
		this.src = src;
		this.f = f;
		this.inner = null;
	}

	public function next():IterResult<Dynamic> {
		while (true) {
			if (inner != null) {
				switch (inner.next()) {
					case Done:
						inner = null;
					case Value(v):
						return Value(v);
					case Await(r):
						return Await(function() {
							return switch (r()) {
								case Done:
									inner = null;
									this.next();
								case Value(v):
									Value(v);
								case Await(r2):
									Await(r2);
							};
						});
				}
				continue;
			}
			switch (src.next()) {
				case Done:
					return Done;
				case Value(v):
					inner = MuseIters.from(f(v));
				case Await(r):
					return Await(function() {
						return switch (r()) {
							case Done:
								Done;
							case Value(v):
								inner = MuseIters.from(f(v));
								this.next();
							case Await(r2):
								Await(r2);
						};
					});
			}
		}
	}
}
