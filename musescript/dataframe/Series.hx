package musescript.dataframe;

import musescript.ndarray.NdArrayF64;
import musescript.ndarray.Np;

/**
 * Tabular 1-D series — Index + F64 NdArray values (not Muse streaming `TSeries`).
 * Column storage shares NdArray buffers; mutate-through when views alias.
 *
 * **F64-only by design (no Series-of-strings):** DataFrame string sidecars are
 * not Series. Prefer `df.tryGet(name)` (null when Str/missing) or `df.getStr` /
 * `strValuesOf` for labels; `df.get(strCol)` still returns an empty Series for
 * older call sites. MultiIndex: `getLevelValuesStr` / `pd.get_level_values_str`.
 */
class Series {
	public var name:Null<String>;
	var _index:AnyIndex;
	var _values:NdArrayF64;

	function new(index:AnyIndex, values:NdArrayF64, ?name:String) {
		_index = index;
		_values = values != null ? values : NdArrayF64.empty([0]);
		this.name = name;
	}

	public static function empty(?name:String):Series
		return new Series(Index.range(0), NdArrayF64.empty([0]), name);

	/**
	 * Construct from 1-D data. Index defaults to `0..n-1`.
	 * Multi-dim arrays are raveled.
	 */
	public static function create(data:NdArrayF64, ?index:AnyIndex, ?name:String):Series {
		var vals = normalize1d(data);
		var idx = index != null ? index : Index.range(vals.size);
		var nIdx = Index.lengthOf(idx);
		if (nIdx != vals.size) {
			if (nIdx == 0) idx = Index.range(vals.size);
			else if (vals.size == 0) vals = NdArrayF64.empty([nIdx]);
			else {
				// Length mismatch: truncate / pad with NaN to index length.
				var aligned = NdArrayF64.empty([nIdx]);
				var n = vals.size < nIdx ? vals.size : nIdx;
				for (i in 0...n) aligned.setFlat(i, vals.getFlat(i));
				for (i in n...nIdx) aligned.setFlat(i, Math.NaN);
				vals = aligned;
			}
		}
		return new Series(idx, vals, name);
	}

	public static function fromArray(data:Array<Float>, ?index:AnyIndex, ?name:String):Series
		return create(Np.asarray(data != null ? data : []), index, name);

	public var index(get, never):AnyIndex;
	inline function get_index():AnyIndex return _index;

	public var values(get, never):NdArrayF64;
	inline function get_values():NdArrayF64 return _values;

	public var length(get, never):Int;
	inline function get_length():Int return _values.size;

	public function dtype():String return "f64";

	public function copy():Series
		return new Series(Index.copyOf(_index), _values.copy(), name);

	public function head(n:Int = 5):Series {
		if (n <= 0) return empty(name);
		var stop = n > length ? length : n;
		return slice(0, stop);
	}

	public function tail(n:Int = 5):Series {
		if (n <= 0) return empty(name);
		var start = length - n;
		if (start < 0) start = 0;
		return slice(start, length);
	}

	public function slice(start:Int, stop:Int):Series {
		var s = start < 0 ? 0 : start;
		var e = stop > length ? length : (stop < 0 ? 0 : stop);
		if (e <= s) return empty(name);
		var v = _values.slice1d(s, e, 1);
		return new Series(Index.sliceOf(_index, s, e), v != null ? v : NdArrayF64.empty([0]), name);
	}

	public function getFlat(i:Int):Float return _values.getFlat(i);

	public function setFlat(i:Int, v:Float):Void _values.setFlat(i, v);

	public function toArray():Array<Float> return _values.toArray();

	/** Average-tie ranks; NaN stays NaN. */
	public function rank(?pct:Bool = false, ?ascending:Bool = true):Series
		return Series.create(GroupBy.rank1d(_values, pct, ascending), Index.copyOf(_index), name);

	public function shift(?periods:Int = 1):Series
		return FrameWindow.shiftSeries(this, periods);

	public function diff(?periods:Int = 1):Series
		return FrameWindow.diffSeries(this, periods);

	public function pctChange(?periods:Int = 1):Series
		return FrameWindow.pctChangeSeries(this, periods);

	public function rollingMean(window:Int):Series
		return FrameWindow.rollingMeanSeries(this, window);

	public function rollingSum(window:Int):Series
		return FrameWindow.rollingSumSeries(this, window);

	public function rollingStd(window:Int, ?ddof:Int = 1):Series
		return FrameWindow.rollingStdSeries(this, window, ddof);

	public function ewmMean(span:Int):Series
		return FrameWindow.ewmMeanSeries(this, span);

	static function normalize1d(data:NdArrayF64):NdArrayF64 {
		if (data == null) return NdArrayF64.empty([0]);
		if (data.ndim <= 1) return data;
		var c = data.copy();
		var r = c.reshape([c.size]);
		return r != null ? r : NdArrayF64.empty([0]);
	}
}
