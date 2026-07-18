{
			@strategy("pos")
			@on(bar) {
				if (mysteryDuck > 0) long();
			}
		}