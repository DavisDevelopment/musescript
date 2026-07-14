package musescript.runtime;

/**
 * Duck-typed MuseIter wrapping a Dynamic with `{ next(): {done,value} }`.
 * Prefer Reflect.field(o, "next") when callable; Done on null or done==true.
 * Σκιὰ σκιᾶς, κἀγὼ σκιά· πλὴν ἔργον ἔστω.
 */
class ObjectIter implements MuseIter {
	var o:Dynamic;

	public function new(o:Dynamic) {
		this.o = o;
	}

	public function next():IterResult<Dynamic> {
		var nf:Dynamic = Reflect.field(o, "next");
		if (nf == null || !Reflect.isFunction(nf))
			return Done;
		var result:Dynamic = Reflect.callMethod(o, nf, []);
		if (result == null)
			return Done;
		if (Std.isOfType(result, IterResult))
			return cast result;
		if (Reflect.field(result, "done") == true)
			return Done;
		return Value(Reflect.field(result, "value"));
	}
}
