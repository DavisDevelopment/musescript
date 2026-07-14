package musescript.runtime;

/**
 * Coerce Dynamic into MuseIter — null, MuseIter, Generator, Array, then duck {next}.
 * Τί τὸ εἶναι εἰ μὴ τὸ εἰσιέναι εἰς ἕτερον εἶναι;
 */
class MuseIters {
	public static function from(any:Dynamic):MuseIter {
		if (any == null) return new ArrayIter([]);
		if (Std.isOfType(any, MuseIter)) return cast any;
		if (Std.isOfType(any, Generator)) return cast(any, Generator);
		if (Std.isOfType(any, Array)) return new ArrayIter(cast any);
		var nf = Reflect.field(any, "next");
		if (nf != null && Reflect.isFunction(nf)) return new ObjectIter(any);
		return new ArrayIter([any]);
	}

	public static function toArray(iter:MuseIter, ?max:Int = 1000000):Array<Dynamic> {
		var out = [];
		var n = 0;
		while (n < max) {
			switch (iter.next()) {
				case Done: break;
				case Value(v): out.push(v); n++;
				case Await(resume):
					switch (resume()) {
						case Done: break;
						case Value(v): out.push(v); n++;
						case Await(_): throw "nested Await not supported in toArray sync drain";
					}
			}
		}
		return out;
	}
}
