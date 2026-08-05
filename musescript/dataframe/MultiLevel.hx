package musescript.dataframe;

/**
 * Typed MultiIndex level carrier — F64 or Str (no Dynamic cells).
 */
enum MultiLevel {
	F64(i:IndexF64);
	Str(i:IndexStr);
}
