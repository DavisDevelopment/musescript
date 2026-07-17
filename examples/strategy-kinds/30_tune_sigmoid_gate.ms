{
	@strategy("TuneSigmoidGate")
	@param("look", 13) { min: 8, max: 21, step: 13, tune: "grid" }
	@param("thresh", 0.55) { min: 0.5, max: 0.65, step: 0.05, tune: "grid" }
	@macro("fit") {
		tune(look, thresh);
		optimize(sharpe, [look, thresh]);
	}
	@on(bar) {
		var gate = ml_sigmoid(mom(close, look) / (atr(close, look) + 0.000000001));
		if (gate > thresh && rising(close, 2)) long();
		if (gate < thresh - 0.15 || falling(close, 3, 5)) flat();
	}
}
