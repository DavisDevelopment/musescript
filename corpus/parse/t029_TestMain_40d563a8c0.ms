{
			@strategy("na_round")
			@on(bar) {
				var n = na(close);
				var r = round(close);
				plot(n, "na");
				plot(r, "round");
			}
		}