package musescript.dataframe;

/**
 * Ordered string labels (symbols / categorical keys).
 * Duplicate labels allowed; joins decide first/last policy later.
 */
class IndexStr {
	var _labels:Array<String>;

	function new(labels:Array<String>) {
		_labels = labels != null ? labels : [];
	}

	public static function empty():IndexStr return new IndexStr([]);

	public static function fromArray(labels:Array<String>):IndexStr {
		if (labels == null) return empty();
		return new IndexStr(labels.copy());
	}

	public var length(get, never):Int;
	inline function get_length():Int return _labels.length;

	public function get(i:Int):Null<String> {
		if (i < 0 || i >= _labels.length) return null;
		return _labels[i];
	}

	public function labels():Array<String> return _labels.copy();

	public function copy():IndexStr return new IndexStr(_labels.copy());

	public function slice(start:Int, stop:Int):IndexStr {
		var n = _labels.length;
		var s = start < 0 ? 0 : start;
		var e = stop > n ? n : (stop < 0 ? 0 : stop);
		if (e <= s) return empty();
		return new IndexStr(_labels.slice(s, e));
	}

	public function take(indices:Array<Int>):IndexStr {
		if (indices == null || indices.length == 0) return empty();
		var out:Array<String> = [];
		var n = _labels.length;
		for (ix in indices) {
			if (ix >= 0 && ix < n) out.push(_labels[ix]);
			else out.push("");
		}
		return new IndexStr(out);
	}

	public function equals(other:IndexStr):Bool {
		if (other == null || other.length != length) return false;
		for (i in 0...length)
			if (_labels[i] != other._labels[i]) return false;
		return true;
	}
}
