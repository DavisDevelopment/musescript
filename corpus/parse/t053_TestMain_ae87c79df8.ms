{
			function fact(n) {
				if (n <= 1) return 1;
				return n * fact(n - 1);
			}
			@strategy("x")
			@on(bar) { var y = fact(3); }
		}