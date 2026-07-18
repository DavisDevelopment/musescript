{
			@strategy("x")
			@on(bar) {
				var m = macd(close);
				var h = m.hist;
				if (h > 0) long();
			}
		}