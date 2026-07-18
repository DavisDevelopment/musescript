{
			@strategy("ma_cross")
			@param("fast", 10)
			@param("slow", 30)
			@on(bar) {
				var maFast = sma("close", fast);
				var maSlow = sma("close", slow);
				if (crossover(maFast, maSlow)) long();
				if (crossunder(maFast, maSlow)) flat();
				plot(maFast, "fast");
				plot(maSlow, "slow");
			}
		}