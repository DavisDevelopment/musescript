{
	@strategy("FilterCountMomentum")
	@param("look", 21)
	@on(bar) {
		var rets = sci_diff(window(close, look));
		var ups = filter(rets, function(r) return r > 0);
		var downs = filter(rets, function(r) return r < 0);
		if (count(ups) >= count(downs) && rising(close, 2)) long();
		if (count(downs) > count(ups) + 1 || falling(close, 3, 5)) flat();
	}
	@on(position) {
		if (bars_in_trade >= look) flat();
	}
}
