{
			@strategy("t")
			@on(tick) {
				if (ghostTick > 0) flat();
			}
		}