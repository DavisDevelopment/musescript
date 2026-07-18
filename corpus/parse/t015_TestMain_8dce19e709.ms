
			@strategy("t")
			@param("fast", 10)
			@param("slow", 30)
			@macro("d") {
				tune(fast, slow);
				optimize(sharpe);
			}
			@on(bar) {
				var a = sma("close", fast);
				var b = sma("close", slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		