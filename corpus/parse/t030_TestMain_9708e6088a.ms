{
			@strategy("chart_decor")
			@on(bar) {
				plot(close, "cl");
				plotshape("mark");
				hline(50, "mid");
				bgcolor("red");
			}
		}