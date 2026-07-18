template isUp(x: Scalar) -> Bool {
			x > 0
		}
		strategy T {
			onBar {
				when isUp(close): long()
			}
		}