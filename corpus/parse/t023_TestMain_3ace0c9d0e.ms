{
			@strategy("vwap_clamp")
			@on(bar) {
				var v = vwap();
				var c = clamp(close, 0, 100);
				var r = close % 10;
				plot(v, "vwap");
				plot(c, "clamped");
				plot(r, "rem");
			}
		}