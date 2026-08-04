package musescript.dataframe;

/**
 * Wrap / unwrap sealed pd handles at the Muse boundary (no Dynamic cell soup).
 */
class AnyPdValues {
	public static inline function ofFrame(df:DataFrame):AnyDataFrame
		return Frame(df != null ? df : DataFrame.empty());

	public static inline function ofSeries(s:Series):AnyPdSeries
		return Ser(s != null ? s : Series.empty());

	public static function unwrapFrame(v:AnyDataFrame):DataFrame {
		return switch (v) {
			case Frame(df): df != null ? df : DataFrame.empty();
		};
	}

	public static function unwrapSeries(v:AnyPdSeries):Series {
		return switch (v) {
			case Ser(s): s != null ? s : Series.empty();
		};
	}

	/** Unwrap concrete payload for Muse Dynamic host (no enum wrapper). */
	public static function unwrap(v:Dynamic):Dynamic {
		if (v == null) return null;
		if (Std.isOfType(v, DataFrame) || Std.isOfType(v, Series)) return v;
		try {
			return unwrapFrame(cast v);
		} catch (_:Dynamic) {}
		try {
			return unwrapSeries(cast v);
		} catch (_:Dynamic) {}
		return v;
	}

	public static function kindOf(v:Dynamic):String {
		if (Std.isOfType(v, DataFrame)) return "dataframe";
		if (Std.isOfType(v, Series)) return "series";
		try {
			unwrapFrame(cast v);
			return "dataframe";
		} catch (_:Dynamic) {}
		try {
			unwrapSeries(cast v);
			return "series";
		} catch (_:Dynamic) {}
		return "";
	}
}
