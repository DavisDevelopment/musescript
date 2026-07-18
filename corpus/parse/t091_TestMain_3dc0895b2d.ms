strategy Bound {
			param fast: Window = 8 { min: 5, max: 21, step: 8, tune: grid }
			onBar { when rising(close, fast): long() }
		}