strategy ArrowTypes {
			onBar {
				f = x => x + 1
				g = (a, b) => a - b
				h = () => 0
				k = (x) => { return x * 2 }
				ups = filter([1.0, -1.0, 2.0], r => r > 0)
			}
		}