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
					return Await(function() {
						return switch (r()) {
							case Done: Done;
							case Value(v):
								if (left > 0) {
									left--;
									return next();
								}
								Value(v);
							case Await(r2): Await(r2);
						};
					});
			}
		}
	}
}
