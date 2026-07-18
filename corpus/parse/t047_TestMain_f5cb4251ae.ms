{
			@strategy("x")
			@on(bar) { var y = sma(ema(close, 8), 21); }
		}