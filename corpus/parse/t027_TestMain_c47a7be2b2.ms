{
			@strategy("lb_call")
			@on(bar) {
				var p = sma(close, 14)[1];
				if (p > close) long();
			}
		}