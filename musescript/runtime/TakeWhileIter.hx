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
		return step(src.next());
	}

	/** Test `pred` at any await-depth; recurse through nested Awaits so a value
	 * arriving after several pumps still gates the stream correctly. */
	function step(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done: Done;
			case Value(v):
				if (pred(v)) Value(v);
				else {
					stopped = true;
					Done;
				}
			case Await(cont): Await(function() return step(cont()));
		};
	}
}
