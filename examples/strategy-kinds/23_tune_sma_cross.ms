{
	@strategy("TuneSmaCross")
	@param("fast", 8) { min: 5, max: 13, step: 3, tune: "grid" }
	@param("slow", 21) { min: 21, max: 34, step: 13, tune: "grid" }
	@macro("discover") {
		tune(fast, slow);
		optimize(sharpe, [fast, slow]);
	}
	@on(bar) {
		var a = sma(close, fast);
		var b = sma(close, slow);
		if (crossover(a, b)) long();
		if (crossunder(a, b)) flat();
	}
}
