package musescript.runtime;

class ArrayIter implements MuseIter {
	var items:Array<Dynamic>;
	var i:Int;
	public function new(items:Array<Dynamic>) {
		this.items = items != null ? items : [];
		this.i = 0;
	}
	public function next():IterResult<Dynamic> {
		if (i >= items.length) return Done;
		return Value(items[i++]);
	}
}
