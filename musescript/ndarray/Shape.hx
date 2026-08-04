package musescript.ndarray;

/**
 * Contiguous dimension tuple for NdArray. Plain `Array<Int>` under the hood so
 * Muse/JSON interop stays trivial; no Dynamic on the typed surface.
 *
 * INDEXING: `shape[0]` is the outermost (slowest-varying in C order) axis —
 * matches NumPy. Empty shape `[]` is a 0-d scalar array (size 1).
 */
@:forward
abstract Shape(Array<Int>) from Array<Int> to Array<Int> {
	public function new(dims:Array<Int>) {
		this = dims == null ? [] : dims.copy();
	}

	public var ndim(get, never):Int;
	inline function get_ndim():Int return this.length;

	/** Product of axes; empty shape → 1 (NumPy 0-d). */
	public function size():Int {
		var n = 1;
		for (i in 0...this.length) {
			var d = this[i];
			if (d < 0) return 0;
			n *= d;
		}
		return n;
	}

	public function copy():Shape return new Shape(this);

	public function equals(other:Shape):Bool {
		var o:Array<Int> = other;
		if (this.length != o.length) return false;
		for (i in 0...this.length) if (this[i] != o[i]) return false;
		return true;
	}

	/** C-order (row-major) strides for a contiguous buffer of this shape. */
	public function cStrides():Array<Int> {
		var n = this.length;
		var out = [for (_ in 0...n) 0];
		if (n == 0) return out;
		out[n - 1] = 1;
		var i = n - 2;
		while (i >= 0) {
			out[i] = out[i + 1] * this[i + 1];
			i--;
		}
		return out;
	}

	public function toString():String {
		return "(" + this.join(",") + ")";
	}
}
