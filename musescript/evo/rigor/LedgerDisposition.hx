package musescript.evo.rigor;

/**
 * Honest Ledger disposition tags (Initiative 5.2).
 * Wire values are stable strings for IDE / JSON consumers.
 */
enum abstract LedgerDisposition(String) to String from String {
	var Go = "GO";
	var Caution = "CAUTION";
	var NoGo = "NO-GO";
}
