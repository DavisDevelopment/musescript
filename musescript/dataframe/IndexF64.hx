package musescript.dataframe;

import musescript.ndarray.NdArrayF64;
import musescript.ndarray.Np;

/**
 * Ordered float64 labels (bar times / unix ms / range integers as f64).
 * Duplicate labels allowed (pandas-like; joins decide policy later).
 */
class IndexF64 {
	var _labels:NdArrayF64;

	function new(labels:NdArrayF64) {
		_labels = labels != null ? labels : NdArrayF64.empty([0]);
	}

	public static function empty():IndexF64 return new IndexF64(NdArrayF64.empty([0]));

	public static function range(n:Int):IndexF64 {
		if (n <= 0) return empty();
		return new IndexF64(Np.arange(n));
	}

	public static function fromArray(labels:Array<Float>):IndexF64 {
		if (labels == null) return empty();
		return new IndexF64(Np.asarray(labels));
	}

	public static function fromNdArray(a:NdArrayF64):IndexF64 {
		if (a == null) return empty();
		if (a.ndim == 0) return empty();
		if (a.ndim == 1) return new IndexF64(a.isCContiguous() ? a : a.copy());
		var flat = a.copy();
		var r = flat.reshape([flat.size]);
		return new IndexF64(r != null ? r : NdArrayF64.empty([0]));
	}

	public var length(get, never):Int;
	inline function get_length():Int return _labels.size;

	/** Contiguous 1-D label buffer (view when possible). */
	public function values():NdArrayF64 return _labels;

	public function get(i:Int):Float {
		if (i < 0 || i >= _labels.size) return Math.NaN;
		return _labels.getFlat(i);
	}

	public function copy():IndexF64 return new IndexF64(_labels.copy());

	public function slice(start:Int, stop:Int):IndexF64 {
		var n = _labels.size;
		var s = start < 0 ? 0 : start;
		var e = stop > n ? n : (stop < 0 ? 0 : stop);
		if (e <= s) return empty();
		var v = _labels.slice1d(s, e, 1);
		return new IndexF64(v != null ? v : NdArrayF64.empty([0]));
	}

	public function take(indices:Array<Int>):IndexF64 {
		if (indices == null || indices.length == 0) return empty();
		var out = NdArrayF64.empty([indices.length]);
		var n = _labels.size;
		for (i in 0...indices.length) {
			var ix = indices[i];
			out.setFlat(i, (ix >= 0 && ix < n) ? _labels.getFlat(ix) : Math.NaN);
		}
		return new IndexF64(out);
	}

	public function toArray():Array<Float> return _labels.toArray();

	public function equals(other:IndexF64):Bool {
		if (other == null || other.length != length) return false;
		for (i in 0...length)
			if (get(i) != other.get(i) && !(Math.isNaN(get(i)) && Math.isNaN(other.get(i))))
				return false;
		return true;
	}
}
