{
			@strategy("both")
			@on(bar) {
				if (close > open) long();
			}
			@on(tick) {
				if (price > 0) flat();
			}
		}