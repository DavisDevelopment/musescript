{
			@strategy("vector")
			@on(bar) {
				var m = ml_matrix(2, 2, [1, 2, 3, 4]);
				if (ml_matrix_get(m, 0, 0) > 0) long();
			}
		}