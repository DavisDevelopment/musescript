strategy Strings {
			onBar {
				parts = str_split(str_replace(str_trim(" a::b "), "::", ","), ",")
				label = str_join(parts, "-")
				when str_starts_with(str_upper(label), "A-") && str_ends_with(label, "b"): long()
			}
		}