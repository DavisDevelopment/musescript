package musescript.evo.rigor;

/**
 * Probabilistic / Deflated Sharpe Ratio (Bailey & López de Prado).
 *
 * PSR discounts a high Sharpe achieved on few observations and corrects for
 * non-normality (skew / kurtosis). DSR further raises the benchmark SR* to the
 * expected maximum of `nTrials` independent null trials (multiple-testing).
 *
 * All inputs are **per-period** returns (not annualized). `Metrics.sharpe`
 * annualizes; callers converting from annualized Sharpe should use
 * `fromAnnualized` or pass the raw return series.
 *
 * «μὴ ψεύδεσθαι τῷ ὀλίγῳ.»
 */
class ProbSharpe {
	public static inline var EULER_MASCHERONI = 0.5772156649015329;

	/** Moments of a return series: mean, std (sample), skew, excess kurtosis, n. */
	public static function moments(returns:Array<Float>):{n:Int, mean:Float, std:Float, skew:Float, kurt:Float} {
		var n = returns.length;
		if (n < 2) return {n: n, mean: 0, std: 0, skew: 0, kurt: 0};
		var mean = 0.0;
		for (r in returns) mean += r;
		mean /= n;
		var m2 = 0.0, m3 = 0.0, m4 = 0.0;
		for (r in returns) {
			var d = r - mean;
			var d2 = d * d;
			m2 += d2;
			m3 += d2 * d;
			m4 += d2 * d2;
		}
		var var_ = m2 / (n - 1);
		var std = Math.sqrt(var_);
		if (std <= 0) return {n: n, mean: mean, std: 0, skew: 0, kurt: 0};
		// Fisher skew / excess kurtosis (unbiased-ish for large n)
		var skew = (m3 / n) / (std * std * std);
		var kurt = (m4 / n) / (std * std * std * std) - 3.0; // excess
		return {n: n, mean: mean, std: std, skew: skew, kurt: kurt};
	}

	/** Non-annualized Sharpe = mean/std. 0 when undefined. */
	public static function sharpePerPeriod(returns:Array<Float>):Float {
		var m = moments(returns);
		return m.std > 0 ? m.mean / m.std : 0;
	}

	/**
	 * Probabilistic Sharpe Ratio vs benchmark `srStar` (per-period).
	 * Returns Φ(z) ∈ [0,1] — probability that true SR > srStar given the sample.
	 * Returns 0 when the sample is too short (`n < 3`) or std is zero.
	 */
	public static function psr(returns:Array<Float>, srStar:Float = 0.0):Float {
		var m = moments(returns);
		if (m.n < 3 || m.std <= 0) return 0;
		var sr = m.mean / m.std;
		var denom = Math.sqrt(1.0 - m.skew * sr + ((m.kurt + 2.0) / 4.0) * sr * sr);
		if (!(denom > 0) || !Math.isFinite(denom)) return 0;
		var z = (sr - srStar) * Math.sqrt(m.n - 1) / denom;
		if (!Math.isFinite(z)) return 0;
		return NormApprox.cdf(z);
	}

	/**
	 * Expected maximum Sharpe under the null of `nTrials` independent trials
	 * (Bailey DSR). `srStd` is the std-dev of the SR estimator under the null
	 * (≈ 1 for unit-variance null returns; pass sample estimate when available).
	 */
	public static function expectedMaxSr(nTrials:Int, srStd:Float = 1.0):Float {
		if (nTrials < 2) return 0;
		var n = nTrials + 0.0;
		// Clamp away from {0,1} so invCdf stays defined under float rounding
		var p1 = 1.0 - 1.0 / n;
		var p2 = 1.0 - 1.0 / (n * Math.exp(1));
		if (p1 >= 1) p1 = 1.0 - 1e-12;
		if (p2 >= 1) p2 = 1.0 - 1e-12;
		if (p1 <= 0) p1 = 1e-12;
		if (p2 <= 0) p2 = 1e-12;
		var z1 = NormApprox.invCdf(p1);
		var z2 = NormApprox.invCdf(p2);
		if (!Math.isFinite(z1) || !Math.isFinite(z2)) return 0;
		return srStd * ((1.0 - EULER_MASCHERONI) * z1 + EULER_MASCHERONI * z2);
	}

	/**
	 * Deflated Sharpe Ratio: PSR against the multiple-testing-aware benchmark SR₀.
	 * `nTrials` = effective number of independent strategy trials (seeds × configs × …).
	 * Higher `nTrials` raises SR₀ and therefore weakly decreases (never increases) DSR.
	 */
	public static function dsr(returns:Array<Float>, nTrials:Int = 1):Float {
		if (nTrials <= 1) return psr(returns, 0.0);
		var m = moments(returns);
		if (m.n < 3 || m.std <= 0) return 0;
		var sr = m.mean / m.std;
		var varTerm = 1.0 - m.skew * sr + ((m.kurt + 2.0) / 4.0) * sr * sr;
		if (!(varTerm > 0) || !Math.isFinite(varTerm)) varTerm = 1.0;
		// σ of the SR estimator (Bailey): √(varTerm / (n-1))
		var srStd = Math.sqrt(varTerm / (m.n - 1));
		var sr0 = expectedMaxSr(nTrials, srStd);
		return psr(returns, sr0);
	}

	/**
	 * Ranking score in (−∞, +∞): probit of PSR (or DSR when nTrials > 1).
	 * Prefer this over raw Sharpe when sample sizes differ — equal Sharpe at 10×
	 * observations ranks strictly higher.
	 */
	public static function rankScore(returns:Array<Float>, nTrials:Int = 1):Float {
		var p = nTrials > 1 ? dsr(returns, nTrials) : psr(returns, 0.0);
		if (p <= 0) return Math.NEGATIVE_INFINITY;
		if (p >= 1) return Math.POSITIVE_INFINITY;
		var z = NormApprox.invCdf(p);
		return Math.isFinite(z) ? z : Math.NEGATIVE_INFINITY;
	}

	/** Convert annualized Sharpe (√252) + observation count into a PSR-style rank score without the full series. */
	public static function rankFromAnnualized(annSharpe:Float, nObs:Int, skew:Float = 0, excessKurt:Float = 0, nTrials:Int = 1):Float {
		if (nObs < 3 || !Math.isFinite(annSharpe)) return Math.NEGATIVE_INFINITY;
		var sr = annSharpe / Math.sqrt(252); // back to per-period
		var denom = Math.sqrt(1.0 - skew * sr + ((excessKurt + 2.0) / 4.0) * sr * sr);
		if (!(denom > 0)) return Math.NEGATIVE_INFINITY;
		var srStar = 0.0;
		if (nTrials > 1) {
			var srStd = denom / Math.sqrt(nObs - 1);
			srStar = expectedMaxSr(nTrials, srStd * Math.sqrt(nObs - 1));
		}
		var z = (sr - srStar) * Math.sqrt(nObs - 1) / denom;
		return Math.isFinite(z) ? z : Math.NEGATIVE_INFINITY;
	}
}
