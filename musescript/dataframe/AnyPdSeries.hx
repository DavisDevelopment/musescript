package musescript.dataframe;

/**
 * Cold Muse / host existential for tabular Series — ≠ streaming Muse `TSeries`.
 * Enum dispatch is for boxing only (mirror `AnyNdArray`).
 */
enum AnyPdSeries {
	Ser(s:Series);
}
