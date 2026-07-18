{
			@strategy("x")
			@on(bar) {
				var xs = [1.0, 2.0];
				var ys = [3.0, 4.0];
				var z = zip(xs, ys);
				var m = merge(xs, ys);
				var pairs = zipWith(xs, ys, function(a, b) return a + b);
				for (e in enumerate(xs)) {
					if (e.i >= 0 && e.v > 0) long();
				}
				var bad = zip(dict_new(), xs);
			}
		}