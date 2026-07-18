strategy TypedIndex {
			onBar {
				xs = [10, 20, 30]
				first = xs[0]
				prev = close[1]
				ma = sma(close, 3)
				prevMa = ma[1]
				tape = ohlcv_window(2)
				tapeFirst = tape[0]
			}
		}