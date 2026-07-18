{
			@strategy("t")
			@on(tick) {
				if (price > bid && size > 0) flat();
			}
		}