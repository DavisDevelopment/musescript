{
			@strategy("x")
			@on(bar) {
				var xs = [1.0, 2.0, 3.0];
				var bad = filter(xs, function(x) return x + 1);
				var labels = ["a", "b"];
				var n = sum(labels);
			}
		}