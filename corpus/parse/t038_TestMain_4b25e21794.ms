{
			@indicator("muse_sma") function(len) {
				if (bar_index + 1 < len) return null;
				return close;
			}
			@strategy("s")
			@on(bar) {
				var v = muse_sma(10);
				if (v != null && v > close) long();
			}
		}