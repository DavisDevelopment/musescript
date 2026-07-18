{
			@strategy("x")
			@on(bar) {
				if (na(close) || na(sma(close, 8))) flat();
			}
		}