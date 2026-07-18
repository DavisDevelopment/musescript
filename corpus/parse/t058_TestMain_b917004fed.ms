{
			@strategy("x")
			@on(bar) {
				var m = macd(close);
				var bad = m.hitst;
			}
		}