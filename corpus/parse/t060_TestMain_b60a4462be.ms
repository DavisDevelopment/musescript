{
			@strategy("x")
			@param("fast", 8)
			@param("slow", 21)
			@macro("m") {
				tune(fast, slow);
				sample(universe, 10);
				optimize(sharpe, [fast, slow]);
			}
			@on(bar) { if (crossover(sma(close, fast), sma(close, slow))) long(); }
		}