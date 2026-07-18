
			@strategy("hoist-escape")
			@on(bar) {
				fast = ema(close, 5);
				slow = ema(close, 13);
				spread = fast - slow;
				var ignored = map([1.0, 2.0], function(spread) return spread + 1.0);
				if (crossover(fast, slow) && spread > -1000000.0) long();
				if (crossunder(fast, slow)) flat();
			}
		