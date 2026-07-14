package musescript.runtime;

/**
 * Pair two streams until either is Done, then apply `f` to each pair.
 * Δύο ῥεῖθρα εἰς ἓν· οὐ σωρὸς, ἀλλὰ χορός.
 * ζεύγνυμι τοὺς next ἄχρις οὗ θάτερον παύσηται.
 * καὶ τὸ f συνάπτει τὰ διάφορα εἰς εἶδος.
 */
class ZipIter implements MuseIter {
	var a:MuseIter;
	var b:MuseIter;
	var f:Dynamic->Dynamic->Dynamic;
	var pendingA:Dynamic;
	var hasPendingA:Bool;

	public function new(a:MuseIter, b:MuseIter, f:Dynamic->Dynamic->Dynamic) {
		this.a = a;
		this.b = b;
		this.f = f;
		this.pendingA = null;
		this.hasPendingA = false;
	}

	public function next():IterResult<Dynamic> {
		if (!hasPendingA) {
			switch (a.next()) {
				case Done:
					return Done;
				case Value(va):
					hasPendingA = true;
					pendingA = va;
				case Await(r):
					return Await(function() return afterA(r()));
			}
		}
		return pullB();
	}

	function afterA(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done:
				Done;
			case Value(va):
				hasPendingA = true;
				pendingA = va;
				pullB();
			case Await(r2):
				Await(function() return afterA(r2()));
		};
	}

	function pullB():IterResult<Dynamic> {
		return switch (b.next()) {
			case Done:
				clearPending();
				Done;
			case Value(vb):
				emit(vb);
			case Await(r):
				Await(function() return afterB(r()));
		};
	}

	function afterB(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done:
				clearPending();
				Done;
			case Value(vb):
				emit(vb);
			case Await(r2):
				Await(function() return afterB(r2()));
		};
	}

	function emit(vb:Dynamic):IterResult<Dynamic> {
		var va = pendingA;
		clearPending();
		return Value(f(va, vb));
	}

	function clearPending():Void {
		hasPendingA = false;
		pendingA = null;
	}
}
