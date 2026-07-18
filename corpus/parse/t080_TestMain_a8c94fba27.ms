{
			function positive(x) { return x > 0; }
			@strategy("x")
			@on(bar) {
				if (positive("bad")) long();
			}
		}