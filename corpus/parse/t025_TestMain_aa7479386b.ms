{
			@strategy("native_math")
			@on(bar) {
				var a = abs(close - open);
				var s = Math.sqrt(close);
				var f = floor(close);
				var c = ceil(close);
				var lo = min(close, open);
				var hi = max(close, open);
				var z = nz(close, 0);
				plot(a, "abs");
				plot(s, "sqrt");
				plot(f, "floor");
				plot(c, "ceil");
				plot(lo, "min");
				plot(hi, "max");
				plot(z, "nz");
			}
		}