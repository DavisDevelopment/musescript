{
			@strategy("tick_js")
			@on(tick) {
				note(price);
				note(size);
			}
		}