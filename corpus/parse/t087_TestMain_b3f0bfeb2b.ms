strategy LambdaSurface {
			param look: Window = 13
			onBar {
				rets = sci_diff(window(close, look))
				ups = filter(rets, function(r) return r > 0)
				spreads = zipWith(window(ema(close, 8), look), window(ema(close, 21), look), function(a, b) return a - b)
				when count(ups) > 6 && avg(spreads) > 0: long()
				when count(ups) < 4: flat()
			}
		}