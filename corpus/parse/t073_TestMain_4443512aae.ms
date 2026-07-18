{
			@strategy("ev")
			@on(orderFlow) {
				note(kind);
				note(price);
			}
		}