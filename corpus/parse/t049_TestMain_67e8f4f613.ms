strategy TypedBuiltins {
			onBar {
				xs = window(close, 3)
				x = xs[0]
				bars = ohlcv_window(2)
				open0 = bars[0]
				label = str_concat("muse", "script")
				part = str_slice(label, 0, 4)
				token = str_split(label, "s")[0]
				when str_contains(part, "muse") && str_len(label) > 0: long()
			}
		}