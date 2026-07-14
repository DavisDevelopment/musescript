package musescript.runtime;

/**
 * Emit while `pred` holds; stop at first failure (exclude the failing value).
 * Ἕως ἂν ἀληθὲς ᾖ τὸ κατηγόρημα, προχωρῶ·
 * ὅταν ψεῦδος, παύομαι ὡς ποταμὸς ἐν πέτρᾳ.
 */
class TakeWhileIter implements MuseIter {
	var src:MuseIter;
	var pred:Dynamic->Bool;
	var stopped:Bool;

	public function new(src:MuseIter, pred:Dynamic->Bool) {
		this.src = src;
		this.pred = pred;
		this.stopped = false;
	}

	public function next():IterResult<Dynamic> {
		if (stopped) return Done;
		return switch (src.next()) {
			case Done: Done;
			case Value(v):
				if (pred(v)) Value(v);
				else {
					stopped = true;
					Done;
				}
			case Await(r): Await(function() {
				return switch (r()) {
					case Done: Done;
					case Value(v):
						if (pred(v)) Value(v);
						else {
							stopped = true;
							Done;
						}
					case Await(r2): Await(r2);
				};
			});
		};
	}
}
