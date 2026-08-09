package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Cointegration — rolling Engle–Granger hedge ratio plus an ADF stationarity test,
 * ported from wickra-core's `Cointegration`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/cointegration.rs).
 *
 * Over a rolling window of (a, b) pairs:
 * 1. Fits hedge ratio β via OLS of a on b, forming spread e = a − (α + β·b)
 * 2. Runs augmented Dickey–Fuller test on the spread, reporting t-statistic
 *
 * A strongly negative ADF stat (e.g. < −2.9 at 5%) means the pair is cointegrated
 * and the spread is tradeable.
 */
typedef CointegrationOutput = {
	hedge_ratio: Float,
	spread: Float,
	adf_stat: Float
};

class Cointegration implements MuseIndicator<CointPair, CointegrationOutput> {
	var period:Int;
	var adfLags:Int;
	var window:RingBuffer<CointPair>;
	var sumA:Float;
	var sumB:Float;
	var sumBb:Float;
	var sumAb:Float;

	public function new(period:Int, adfLags:Int) {
		var minPeriod = 2 * adfLags + 4;
		if (period < minPeriod) {
			throw "Cointegration: period must be >= 2*adf_lags + 4";
		}
		this.period = period;
		this.adfLags = adfLags;
		reset();
	}

	public function update(input:CointPair):Null<CointegrationOutput> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;

		var wasFull = window.isFull();
		var old = window.push({ a: a, b: b });
		if (wasFull) {
			sumA -= old.a;
			sumB -= old.b;
			sumBb -= old.b * old.b;
			sumAb -= old.a * old.b;
		}
		sumA += a;
		sumB += b;
		sumBb += b * b;
		sumAb += a * b;

		if (window.length < period) return null;

		var n = period;
		var meanA = sumA / n;
		var meanB = sumB / n;
		var varB = (sumBb / n - meanB * meanB);
		if (varB < 0.0) varB = 0.0;

		var hedgeRatio:Float;
		var intercept:Float;
		if (varB == 0.0) {
			// A flat b window has no defined slope; fall back to a level shift.
			hedgeRatio = 0.0;
			intercept = meanA;
		} else {
			var cov = sumAb / n - meanA * meanB;
			hedgeRatio = cov / varB;
			intercept = meanA - hedgeRatio * meanB;
		}

		// Build the spread series over the window (oldest-first via `oldest`).
		var spreads = new Array<Float>();
		for (i in 0...window.length) {
			var pair = window.oldest(i);
			var spread = pair.a - (intercept + hedgeRatio * pair.b);
			spreads.push(spread);
		}
		var currentSpread = spreads[spreads.length - 1];
		var adfStat = adfNoConstant(spreads, adfLags);

		return {
			hedge_ratio: hedgeRatio,
			spread: currentSpread,
			adf_stat: adfStat
		};
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sumA = 0.0;
		sumB = 0.0;
		sumBb = 0.0;
		sumAb = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Cointegration";

	public static function spec():IndicatorSpec {
		return {
			name: "cointegration",
			args: [TSeries, TSeries, TWindow, TScalar],
			ret: TObject([
				{name: "hedge_ratio", ty: TScalar},
				{name: "spread", ty: TScalar},
				{name: "adf_stat", ty: TScalar}
			]),
			minArgs: 4,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 30);
				var lags = IndicatorCache.intArg(args, 3, 1);
				var key = "cointegration:" + seriesA + ":" + seriesB + ":" + p + ":" + lags;
				var nanFill:CointegrationOutput = {
					hedge_ratio: Math.NaN,
					spread: Math.NaN,
					adf_stat: Math.NaN
				};
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, nanFill,
					() -> new Cointegration(p, lags),
					(i, a, b) -> (cast i : Cointegration).update({ a: a, b: b }));
			}
		};
	}
}

/**
 * Solve the linear system mat·x = rhs for a small square system by Gaussian
 * elimination, returning null if the matrix is (numerically) singular.
 * mat is row-major; rhs is the right-hand side.
 */
function solve(mat:Array<Array<Float>>, rhs:Array<Float>):Null<Array<Float>> {
	var dim = rhs.length;
	// Forward elimination
	for (col in 0...dim) {
		var pivot = mat[col][col];
		if (Math.abs(pivot) < 1e-12) return null;
		var pivotRow = mat[col].copy();
		for (row in (col + 1)...dim) {
			var factor = mat[row][col] / pivot;
			for (ci in col...dim) {
				mat[row][ci] -= factor * pivotRow[ci];
			}
			rhs[row] -= factor * rhs[col];
		}
	}
	// Back substitution
	var sol = new Array<Float>();
	for (i in 0...dim) sol.push(0.0);
	for (row in 0...dim) {
		var ri = dim - 1 - row;
		var known = 0.0;
		for (col in (ri + 1)...dim) {
			known += mat[ri][col] * sol[col];
		}
		sol[ri] = (rhs[ri] - known) / mat[ri][ri];
	}
	return sol;
}

/**
 * Augmented Dickey–Fuller t-statistic on series with lags lagged differences
 * and no constant or trend term. The regression is Δeₜ = ρ·eₜ₋₁ + Σ γᵢ·Δeₜ₋ᵢ + εₜ;
 * the reported statistic is ρ̂ / se(ρ̂). Returns 0.0 when degenerate.
 */
function adfNoConstant(series:Array<Float>, lags:Int):Float {
	var len = series.length;
	var numReg = lags + 1; // regressors: eₜ₋₁ plus lags lagged differences
	var first = lags + 1; // first usable observation index
	if (len <= first) return 0.0;
	var numObs = len - first;
	if (numObs <= numReg) return 0.0; // need at least one residual degree of freedom

	// Build regressors matrix and XtX, Xty
	var xtx = new Array<Array<Float>>();
	var xty = new Array<Float>();
	for (i in 0...numReg) {
		xtx.push(new Array<Float>());
		for (j in 0...numReg) xtx[i].push(0.0);
		xty.push(0.0);
	}

	for (idx in first...len) {
		var diff = series[idx] - series[idx - 1];
		// Build regressors row
		var row = new Array<Float>();
		row.push(series[idx - 1]);
		for (lag in 1...(lags + 1)) {
			row.push(series[idx - lag] - series[idx - lag - 1]);
		}
		// Accumulate XtX and Xty
		for (ri in 0...numReg) {
			xty[ri] += row[ri] * diff;
			for (ci in 0...numReg) {
				xtx[ri][ci] += row[ri] * row[ci];
			}
		}
	}

	// Solve for theta
	var xtxClone = new Array<Array<Float>>();
	for (row in xtx) {
		xtxClone.push(row.copy());
	}
	var theta = solve(xtxClone, xty);
	if (theta == null) return 0.0;

	var rho = theta[0];
	var rss = 0.0;
	for (idx in first...len) {
		var diff = series[idx] - series[idx - 1];
		// Build regressors row again
		var row = new Array<Float>();
		row.push(series[idx - 1]);
		for (lag in 1...(lags + 1)) {
			row.push(series[idx - lag] - series[idx - lag - 1]);
		}
		var pred = 0.0;
		for (i in 0...numReg) {
			pred += row[i] * theta[i];
		}
		var resid = diff - pred;
		rss += resid * resid;
	}

	var dof = numObs - numReg;
	var sigma2 = rss / dof;

	// Solve for (XtX)^{-1} with unit vector [1, 0, 0, ...]
	var unit = new Array<Float>();
	for (i in 0...numReg) unit.push(i == 0 ? 1.0 : 0.0);
	var xtxClone2 = new Array<Array<Float>>();
	for (row in xtx) {
		xtxClone2.push(row.copy());
	}
	var inverse = solve(xtxClone2, unit);
	if (inverse == null) return 0.0;

	var varRho = sigma2 * inverse[0];
	if (varRho <= 0.0) return 0.0;
	return rho / Math.sqrt(varRho);
}

@:structInit
class CointPair {
	public var a:Float;
	public var b:Float;
}
