{
			@strategy("x")
			@param("fast", 8)
			@on(bar) {
				var x = sma(close, fast);
			}
		}