{
			@strategy("ev_js")
			@on(orderFlow) {
				note(kind);
				note(price);
			}
		}