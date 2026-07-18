{
			@strategy("x")
			@param("fast", 10)
			@on(bar) { var x = sma(fast, "close"); }
		}