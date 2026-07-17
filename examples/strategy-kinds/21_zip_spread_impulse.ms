{
	@strategy("ZipSpreadImpulse")
	@param("look", 13)
	@on(bar) {
		var fast = window(ema(close, 8), look);
		var slow = window(ema(close, 21), look);
		var spreads = zipWith(fast, slow, function(a, b) return a - b);
		if (avg(spreads) > -1.0 && rising(close, 2) && close > sma(close, look)) long();
		if (avg(spreads) < 0 || falling(close, 3, 5)) flat();
	}
	@on(position) {
		if (bars_in_trade >= look) flat();
	}
}
