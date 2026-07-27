package musescript.ew;

/**
 * Probabilistic projection surface emitted by a ForecastFn (EW lattice today;
 * hierarchical MCMC later). Policy / TradeLogic consume *reductions* of this cloud,
 * never rewrite hard grammar.
 *
 * Shape mirrors PROJECTION_COEVOLUTION_PLAN fan reductions + GeomViz ForecastBand,
 * plus EW-specific invalidation / count mass.
 */
typedef ForecastCloud = {
	/** Horizon in bars this cloud claims a relationship to. */
	var horizon:Int;
	/** Empirical price band lo/hi (e.g. p05–p95 or φ target span). */
	var priceLo:Float;
	var priceHi:Float;
	/** Time band in bar index space. */
	var barLo:Float;
	var barHi:Float;
	/** Median / point projection when K=1; ensemble median when K>1. */
	var priceMid:Float;
	/** Fan width proxy: priceHi − priceLo (0 when deterministic). */
	var spread:Float;
	/** Fraction of mass / samples bullish vs reference (NaN if undefined). */
	var probUp:Float;
	/** Posterior mass on preferred count label (0..1), or 1.0 for single lattice pick. */
	var topMass:Float;
	/** Entropy over top-K competing counts (high = ambiguous). */
	var countEntropy:Float;
	/** Mean / preferred invalidation price (NaN if N/A). */
	var invalidatePrice:Float;
	/** Distance |price − invalidate| / ATR-ish scale when available (NaN if N/A). */
	var distToInvalidation:Float;
	/** Soft nest score across degrees (1.0 = neutral). */
	var nestScore:Float;
	/** Opaque label id / code for viz (0 = none). */
	var labelCode:Float;
	/** Sample count K (1 = point projection). */
	var samples:Int;
}

class ForecastCloudUtil {
	public static function empty(horizon:Int = 0):ForecastCloud {
		return {
			horizon: horizon,
			priceLo: Math.NaN, priceHi: Math.NaN,
			barLo: Math.NaN, barHi: Math.NaN,
			priceMid: Math.NaN, spread: Math.NaN, probUp: Math.NaN,
			topMass: Math.NaN, countEntropy: Math.NaN,
			invalidatePrice: Math.NaN, distToInvalidation: Math.NaN,
			nestScore: 1.0, labelCode: 0, samples: 0
		};
	}

	/** Fill mid/spread from a price band (K=1 degeneracy). */
	public static function fromBand(
		priceLo:Float, priceHi:Float, barLo:Float, barHi:Float,
		?invalidatePrice:Float, horizon:Int = 0, labelCode:Float = 0
	):ForecastCloud {
		var lo = priceLo;
		var hi = priceHi;
		var mid = (lo + hi) * 0.5;
		var inv = invalidatePrice != null ? invalidatePrice : Math.NaN;
		return {
			horizon: horizon,
			priceLo: lo, priceHi: hi,
			barLo: barLo, barHi: barHi,
			priceMid: mid,
			spread: Math.isFinite(lo) && Math.isFinite(hi) ? hi - lo : Math.NaN,
			probUp: Math.NaN,
			topMass: 1.0,
			countEntropy: 0.0,
			invalidatePrice: inv,
			distToInvalidation: Math.NaN,
			nestScore: 1.0,
			labelCode: labelCode,
			samples: 1
		};
	}
}
