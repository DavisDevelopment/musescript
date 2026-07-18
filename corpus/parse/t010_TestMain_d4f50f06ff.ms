{
			@strategy("idx")
			@on(bar) {
				var xs = [1, 2, 3];
				var a = xs[0];
				var prev = close[1];
			}
		}