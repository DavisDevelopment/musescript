strategy ForSurf {
			onBar {
				xs = window(close, 8)
				acc = 0.0
				for (x in xs) {
					acc = acc + x
				}
				when acc > 0: long()
			}
		}