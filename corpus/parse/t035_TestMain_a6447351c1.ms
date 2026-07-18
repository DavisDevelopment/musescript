{
			@strategy("lb")
			@on(bar) {
				var prev = close[1];
				var scale = function(x) { return x * 2; };
				var v = scale(prev);
				if (v > close) flat();
			}
		}