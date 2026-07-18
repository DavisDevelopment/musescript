
			@strategy("filltest")
			@on(bar) {
				if (crossover(sma("close", 3), sma("close", 8))) long();
				if (crossunder(sma("close", 3), sma("close", 8))) flat();
			}
		