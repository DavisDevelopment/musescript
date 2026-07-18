{
			@strategy("strings")
			@on(bar) {
				if (str_contains("muse", "use")) long();
			}
		}