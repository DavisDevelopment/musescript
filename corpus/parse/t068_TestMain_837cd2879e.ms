{
			@strategy("e")
			@on(fills) {
				if (kind == "Filled" && px > 0 && qty > 0) flat();
			}
		}