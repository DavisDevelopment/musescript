package musescript.runtime;

class MergeIter implements MuseIter {
	var a:MuseIter;
	var b:MuseIter;
	var onB:Bool;

	public function new(a:MuseIter, b:MuseIter) {
		this.a = a;
		this.b = b;
		this.onB = false;
	}

	public inline function next():IterResult<Dynamic> {
		if (!onB) {
			switch (a.next()) {
				case Done:
					onB = true;
				case Value(v):
					return Value(v);
				case Await(r):
					return Await(function() return nextFromA(r));
			}
		}
		return b.next();
	}

	inline function nextFromA(r:Void->IterResult<Dynamic>):IterResult<Dynamic> {
		switch (r()) {
			case Done:
				onB = true;
				return b.next();
			case Value(v):
				return Value(v);
			case Await(r2):
				return Await(function() return nextFromA(r2));
		}
	}
}
