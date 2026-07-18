strategy Sci {
			param lam: Scalar = 1e-6
			onBar {
				v = ewm_stdev(close, 8)
				when v[1] < v && lam < 1: long()
			}
		}