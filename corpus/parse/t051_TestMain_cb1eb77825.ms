{
			@strategy("x")
			@on(bar) { var x = sma("close", 7); }
		}