{
			@strategy("x")
			@on(bar) {
				var xs = [1.0, 2.0, 3.0];
				for (x in xs) {
					if (x > 0) long();
				}
				var labels = ["a", "b"];
				for (s in labels) {
					if (str_len(s) > 0) long();
				}
			}
		}