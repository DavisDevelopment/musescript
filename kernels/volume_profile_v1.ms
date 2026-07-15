{
	function volume_profile_v1(highs, lows, volumes, output, n, binsLen, minPrice, maxPrice) {
		var emittedVolume = -1.0;
		if (
			n >= 0
			&& binsLen > 0
			&& n <= highs.length
			&& n <= lows.length
			&& n <= volumes.length
			&& binsLen <= output.length
			&& maxPrice > minPrice
		) {
			var bin = 0;
			while (bin < binsLen) {
				output[bin] = 0.0;
				bin = bin + 1;
			}

			var binSize = (maxPrice - minPrice) / binsLen;
			var i = 0;
			emittedVolume = 0.0;
			while (i < n) {
				var lo = lows[i];
				var hi = highs[i];
				var vol = volumes[i];
				if (vol > 0.0) {
					if (hi == lo) {
						var pointBin = floor((lo - minPrice) / binSize);
						if (pointBin < 0) pointBin = 0;
						if (pointBin >= binsLen) pointBin = binsLen - 1;
						output[pointBin] = output[pointBin] + vol;
					} else {
						var first = floor((lo - minPrice) / binSize);
						var last = ceil((hi - minPrice) / binSize) - 1;
						if (first < 0) first = 0;
						if (first >= binsLen) first = binsLen - 1;
						if (last < 0) last = 0;
						if (last >= binsLen) last = binsLen - 1;

						var remaining = vol;
						var j = first;
						while (j <= last) {
							var allocation = remaining;
							if (j < last) {
								var binLow = minPrice + (j * binSize);
								var binHigh = binLow + binSize;
								var overlapLow = lo > binLow ? lo : binLow;
								var overlapHigh = hi < binHigh ? hi : binHigh;
								var overlap = overlapHigh - overlapLow;
								if (overlap < 0.0) overlap = 0.0;
								allocation = min(remaining, vol * overlap / (hi - lo));
								remaining = remaining - allocation;
							}
							output[j] = output[j] + allocation;
							j = j + 1;
						}
					}
					emittedVolume = emittedVolume + vol;
				}
				i = i + 1;
			}
		}
		return emittedVolume;
	}
}
