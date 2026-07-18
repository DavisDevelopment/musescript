{
			@strategy("lb_bare")
			@on(bar) {
				var p = close[1];
				if (p > open) long();
			}
		}