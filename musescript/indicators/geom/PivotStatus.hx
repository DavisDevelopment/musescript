package musescript.indicators.geom;

/**
 * Lifecycle of a swing pivot in the shared geometry substrate.
 *
 * - Confirmed: reversal threshold met; immutable thereafter.
 * - Forming: live candidate extreme still extending; may move or never confirm.
 * - Projected: synthetic target from RatioEngine / EW projection (not observed).
 */
enum abstract PivotStatus(Int) from Int to Int {
	var Confirmed = 0;
	var Forming = 1;
	var Projected = 2;
}
