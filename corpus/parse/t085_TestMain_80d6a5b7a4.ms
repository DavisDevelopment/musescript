strategy P {
			onBar { x = close |> sma(10); }
		}