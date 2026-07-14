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
		return switch (src.next()) {
			case Done: Done;
			case Value(v):
				acc = f(acc, v);
				Value(acc);
			case Await(r): Await(function() {
				return switch (r()) {
					case Done: Done;
					case Value(v):
						acc = f(acc, v);
						Value(acc);
					case Await(r2): Await(r2);
				};
			});
		};
	}
}
