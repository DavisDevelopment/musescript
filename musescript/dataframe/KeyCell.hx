package musescript.dataframe;

/**
 * Typed groupby / MultiIndex key cell — F64 or Str (no Dynamic bags).
 */
enum KeyCell {
	F64(v:Float);
	Str(v:String);
}
