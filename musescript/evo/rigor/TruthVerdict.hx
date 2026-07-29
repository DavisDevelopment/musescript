package musescript.evo.rigor;

/**
 * At-a-glance Honest Backtest verdict (Initiative 1 — Truth Report).
 * Wire values are stable string tags for IDE / JSON consumers.
 */
enum abstract TruthVerdict(String) to String from String {
	var Robust = "Robust";
	var Fragile = "Fragile";
	var CoinFlip = "Coin-flip";
	var Overfit = "Overfit";
}
