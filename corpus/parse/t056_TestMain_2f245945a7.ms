strategy ArrowHof {
			onBar {
				ups = filter([1.0, -1.0, 2.0], r => r > 0)
				spreads = zipWith([3.0, 4.0], [1.0, 1.0], (a, b) => a - b)
				when count(ups) >= 2 && avg(spreads) > 0: long()
				when count(ups) < 2: flat()
			}
		}