{
			@strategy("x")
			@on(bar) {
				if (Math.isNaN(close) || Math.abs(close - open) > Math.pow(2, 3)) flat();
			}
		}