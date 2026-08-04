package musescript.dataframe;

/**
 * Cold Muse / host existential for DataFrame — enum dispatch is for boxing only,
 * never for per-cell kernels (mirror `AnyNdArray`).
 */
enum AnyDataFrame {
	Frame(df:DataFrame);
}
