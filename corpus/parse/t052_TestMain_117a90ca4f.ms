{
			function add1(x) { return x + 1; }
			@strategy("x")
			@on(bar) {
				var y = add1(close);
				var z = add1(1, 2);
			}
		}