{
			@strategy("tick_emit")
			@on(tick) {
				note(price);
			}
		}