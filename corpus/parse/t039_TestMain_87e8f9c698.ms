{
			@strategy("t")
			@on(tick) {
				var p = price;
				if (p > 100 && size > 0) long();
			}
		}