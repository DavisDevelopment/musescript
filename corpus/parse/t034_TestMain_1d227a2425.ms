{
			@strategy("rich")
			@on(bar) {
				var xs = [1, 2, 3];
				var cfg = { threshold: 0.5, label: "x" };
				var sum = 0;
				for (v in xs) {
					sum = sum + v;
				}
				var ch = change("close", 1);
				var hi = highest("high", 5);
				if (sum > cfg.threshold && ch > 0) long();
				plot(hi, cfg.label);
			}
		}