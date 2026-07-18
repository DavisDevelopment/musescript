{
			@strategy("clb")
			@on(bar) {
				var xs = [1, 2, 3];
				var a = xs[1];
				var prevMa = sma("close", 3)[1];
				var prevRsi = rsi(close, 14)[1];
			}
		}