{
			@strategy("x")
			@on(bar) {
				var m = ml_matrix(2, 2, [1, 2, 3, 4]);
				var bad = m.rowz;
			}
		}