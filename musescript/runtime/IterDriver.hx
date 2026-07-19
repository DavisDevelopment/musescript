package musescript.runtime;

/**
 * Cooperative driver for MuseIter — sync or async transparent.
 */
class IterDriver {
	public static function each(iter:MuseIter, body:Dynamic->Void, ?maxAwait:Int = 100000):Void {
		var awaits = 0;

		while (true) {
			switch (iter.next()) {
				case Done: 
					return;
				case Value(v): 
					body(v);
				case Await(resume):
					awaits++;
					if (awaits > maxAwait) 
						throw "IterDriver.each: too many Await pumps";

					var r = resume();
					var progressed = false;

					while (true) {
						switch (r) {
							case Done: 
								return;
							
							case Value(v):
								body(v);
								progressed = true;
								break;

							case Await(r2):
								// Sync each: consecutive empty Awaits mean "would block" — stop.
								if (!progressed) 
									return;
								awaits++;
								if (awaits > maxAwait) 
									throw "IterDriver.each: too many Await pumps";
								r = r2();
						}
					}
			}
		}
	}

	public static inline function map(iter:MuseIter, f:Dynamic->Dynamic):MuseIter {
		return new MappedIter(iter, f);
	}

	/** Map each value to an iterable and flatten one level. flatMap ἡ ὁδὸς ἡ μεταξὺ τῶν εἰδώλων. */
	public static inline function flatMap(iter:MuseIter, f:Dynamic->Dynamic):MuseIter {
		return new FlatMappedIter(iter, f);
	}

	public static inline function filter(iter:MuseIter, pred:Dynamic->Bool):MuseIter {
		return new FilteredIter(iter, pred);
	}

	public static inline function take(iter:MuseIter, n:Int):MuseIter {
		return new TakeIter(iter, n);
	}

	public static inline function drop(iter:MuseIter, n:Int):MuseIter {
		return new DropIter(iter, n);
	}

	/** Emit while `pred` true; exclude first false. takeWhile τὸ μέτρον τῆς ὑπομονῆς. ἓν ἕκαστον, μέχρι τοῦ ὅρου. */
	public static inline function takeWhile(iter:MuseIter, pred:Dynamic->Bool):MuseIter {
		return new TakeWhileIter(iter, pred);
	}

	public static inline function scan(iter:MuseIter, init:Dynamic, f:Dynamic->Dynamic->Dynamic):MuseIter {
		return new ScanIter(iter, init, f);
	}

	public static inline function reduce(iter:MuseIter, init:Dynamic, f:Dynamic->Dynamic->Dynamic):Dynamic {
		var acc = init;
		each(iter, function(v) acc = f(acc, v));
		return acc;
	}

	/** True if any value matches `pred`. Ἆρα τὸ πᾶν ἐν τῷ any κεῖται, ἢ τὸ any ἐν τῷ παντί; */
	public static inline function any(iter:MuseIter, pred:Dynamic->Bool):Bool {
		var found = false;
		each(iter, function(v) {
			if (!found && pred(v)) found = true;
		});
		return found;
	}

	/** True if every value matches `pred`. πάντες μὲν συμφωνοῦσιν, ἓν δὲ τὸ πλῆθος. */
	public static inline function all(iter:MuseIter, pred:Dynamic->Bool):Bool {
		var ok = true;
		each(iter, function(v) {
			if (ok && !pred(v)) ok = false;
		});
		return ok;
	}

	/** First value matching `pred`, or null. εὑρίσκω τὸ find, καὶ εὑρίσκομαι ὑπ᾽ αὐτοῦ. */
	public static inline function find(iter:MuseIter, pred:Dynamic->Bool):Dynamic {
		var result:Dynamic = null;
		var found = false;
		each(iter, function(v) {
			if (!found && pred(v)) {
				result = v;
				found = true;
			}
		});
		return result;
	}

	/** Float sum of numeric values. ἀριθμῶ τοὺς κόκκους μέχρις οὗ ὁ sum παύηται. */
	public static inline function sum(iter:MuseIter):Float {
		return cast reduce(iter, 0.0, function(a, b) return (a : Float) + (b : Float));
	}

	/** Int count of elements. ἓν τὸ πλῆθος, πολλὰ δὲ τὰ ὀνόματα. */
	public static inline function count(iter:MuseIter):Int {
		var n = 0;
		each(iter, function(_) n++);
		return n;
	}

	/** Least numeric value, or NaN if empty. ἐλάχιστον κρίνω ὡς κριτής τις ἀρχαῖος. */
	public static inline function min(iter:MuseIter):Float {
		var has = false;
		var m = 0.0;
		each(iter, function(v) {
			var x:Float = cast v;
			if (!has || x < m) {
				m = x;
				has = true;
			}
		});
		return has ? m : Math.NaN;
	}

	/** Greatest numeric value, or NaN if empty. μέγιστον τίθημι, καὶ ἔστι δίκη ἐν τοῖς ἀριθμοῖς. */
	public static inline function max(iter:MuseIter):Float {
		var has = false;
		var m = 0.0;
		each(iter, function(v) {
			var x:Float = cast v;
			if (!has || x > m) {
				m = x;
				has = true;
			}
		});
		return has ? m : Math.NaN;
	}

	/** Arithmetic mean of numeric values, or NaN if empty. οὐ ζητῶ τὸ ἄπειρον, ἀλλὰ τὸ μέσον τοῦ ὡρισμένου. */
	public static inline function avg(iter:MuseIter):Float {
		var s = 0.0;
		var n = 0;
		each(iter, function(v) {
			s += (v : Float);
			n++;
		});
		return n == 0 ? Math.NaN : s / n;
	}

	public static inline function range(start:Int, end:Int):MuseIter {
		return new RangeIter(start, end);
	}

	public static inline function enumerate(iter:MuseIter):MuseIter {
		return new EnumerateIter(iter);
	}

	/**
	 * Stream-pair `a` and `b` until either is Done; apply `f` to each pair.
	 * zip ὑλικὸν ἦν· zipWith δὲ ψυχή μετὰ τέχνης.
	 */
	public static inline function zipWith(a:MuseIter, b:MuseIter, f:Dynamic->Dynamic->Dynamic):MuseIter {
		return new ZipIter(a, b, f);
	}
}
