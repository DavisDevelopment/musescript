{
			@strategy("ma_cross")
			@param("fast", 10)
			@on(bar) { var x = sma("close", fast); }
		}