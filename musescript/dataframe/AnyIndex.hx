package musescript.dataframe;

/**
 * Index carrier for Series/DataFrame — F64 time/range, Str labels, or
 * MultiIndex (F64/Str levels, N≥1). Owned module so
 * `import musescript.dataframe.AnyIndex` resolves (enums in Index.hx are
 * `musescript.dataframe.Index.AnyIndex`, not a top-level path).
 */
enum AnyIndex {
	F64(i:IndexF64);
	Str(i:IndexStr);
	Multi(i:MultiIndex);
}
