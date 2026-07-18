{
			@strategy("portable")
			@on(bar) {
				var xs = window("close", 3);
				var highs = window(high, 3);
				var packed = ohlcv_window(2);
				var label = str_concat("muse", "script");
				if (count(xs) == 3 && count(highs) == 3 && highs[2] != xs[2]
					&& count(packed) == 10
					&& str_contains(label, "script")
					&& str_slice(label, 0, 4) == "muse") long();
			}
		}