{
			@strategy("pine_scalars")
			@on(bar) {
				var m = mom(close, 10);
				var r = roc(close, 10);
				var s = stdev(close, 14);
				var w = wma(close, 9);
				var a = rma(close, 14);
				plot(m, "mom");
				plot(r, "roc");
				plot(s, "stdev");
				plot(w, "wma");
				plot(a, "rma");
			}
		}