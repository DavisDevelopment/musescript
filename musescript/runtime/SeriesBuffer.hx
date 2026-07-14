package musescript.runtime;

/**
 * Ring-buffer series for bar lookback (Pine-like).
 */
class SeriesBuffer {
	public var data:Array<Float>;
	public var name:String;
	var maxLen:Int;

	public function new(?name:String, ?maxLen:Int = 10000) {
		this.name = name != null ? name : "series";
		this.maxLen = maxLen;
		this.data = [];
	}

	public function push(v:Float):Void {
		data.push(v);
		if (maxLen > 0 && data.length > maxLen) data.shift();
	}

	/** index 0 = current, 1 = previous, ... */
	public function get(lookback:Int = 0):Float {
		var idx = data.length - 1 - lookback;
		if (idx < 0) return Math.NaN;
		return data[idx];
	}

	public function length():Int return data.length;

	public function current():Float return get(0);

	/** Object view for Reflect.getProperty(“get”) style access */
	public function toDynamic():Dynamic {
		var self = this;
		return {
			get: function(?n:Int) return self.get(n != null ? n : 0),
			length: function() return self.length(),
			name: self.name
		};
	}
}
