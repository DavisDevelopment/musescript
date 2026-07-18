strategy ObjSurface {
			onBar {
				o = { slope: 1.0, level: close }
				when o.slope > 0: long()
			}
		}