{
			@strategy("m")
			@on(bar) {
				var side = @match(1) [1 => "buy", _ => "sell"];
				if (side == "buy") long();
			}
		}