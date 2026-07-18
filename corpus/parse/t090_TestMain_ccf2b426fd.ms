strategy FnReturn {
			onBar {
				when isPos(mom(close, 8)): long()
				when !isPos(mom(close, 8)): flat()
			}
		}

		function isPos(x) {
			return x > 0;
		}