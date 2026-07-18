{
			@strategy("ev")
			@on(orderFlow) {
				var k = kind;
				if (k == "Filled" && size > 0) note(price);
			}
		}