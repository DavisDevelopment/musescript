{
			@strategy("x")
			@on(bar) {
				var d = dict_new();
				dict_set(d, "k", 1);
				if (dict_has(d, "k") && dict_size(d) > 0) long();
			}
		}