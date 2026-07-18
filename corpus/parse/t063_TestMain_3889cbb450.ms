{
			@strategy("x")
			@on(bar) {
				var d = dict_new();
				var vs = dict_values(d);
				if (stat_mean(vs) > 0) long();
			}
		}