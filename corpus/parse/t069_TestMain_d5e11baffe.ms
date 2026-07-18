strategy TickSurf {
			onTick {
				when price > 0 && size > 0: flat()
			}
			onEvent(fills) {
				when kind == "Filled": flat()
			}
		}