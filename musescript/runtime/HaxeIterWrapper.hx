package musescript.runtime;

/** Adapts a plain Haxe `Iterator<Dynamic>` to `MuseIter` — used by
 * `Generator.fromHaxeIter` to delegate into native Haxe iterators. */
class HaxeIterWrapper implements MuseIter {
	var it:Iterator<Dynamic>;

	public function new(it:Iterator<Dynamic>) {
		this.it = it;
	}

	public function next():IterResult<Dynamic> {
		return it.hasNext() ? Value(it.next()) : Done;
	}
}
