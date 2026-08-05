package musescript.dataframe;

/**
 * Typed unique values from {@link Factorize} — F64 or Str (no Dynamic).
 */
enum FactorUniques {
	F64(u:IndexF64);
	Str(u:IndexStr);
}
