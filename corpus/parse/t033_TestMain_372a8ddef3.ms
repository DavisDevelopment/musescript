{
			@strategy("e")
			@param("fast", 10)
			@on(bar) {
				var ma = sma("close", fast);
				if (ma > close) long();
			}
		}