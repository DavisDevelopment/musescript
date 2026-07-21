package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Granger causality F-statistic — ported from wickra-core's `GrangerCausality`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/granger_causality.rs).
 *
 * Does series `b` help predict series `a`? Tests with an F-statistic over a
 * rolling window via OLS regression.
 */
class GrangerCausality implements MuseIndicator<{a: Float, b: Float}, Float> {
	var period:Int;
	var lag:Int;
	var window:Array<{a: Float, b: Float}>;

	public function new(period:Int, lag:Int) {
		if (lag < 1) {
			throw "Granger causality: lag must be >= 1";
		}
		if (period < 3 * lag + 2) {
			throw "Granger causality: period must be >= 3*lag + 2";
		}
		this.period = period;
		this.lag = lag;
		this.window = [];
	}

	public function update(input:{a: Float, b: Float}):Null<Float> {
		// Non-finite inputs are skipped
		if (!isFinite(input.a) || !isFinite(input.b)) {
			return null;
		}

		if (window.length == period) {
			window.shift();
		}
		window.push(input);

		if (window.length < period) {
			return null;
		}

		// Extract series a and b
		var a:Array<Float> = [];
		var b:Array<Float> = [];
		for (pair in window) {
			a.push(pair.a);
			b.push(pair.b);
		}

		var num_obs = period - lag;

		// Build regression matrices
		var target:Array<Float> = [];
		var restricted:Array<Array<Float>> = [];
		var unrestricted:Array<Array<Float>> = [];

		for (k in 0...num_obs) {
			var now = lag + k;
			target.push(a[now]);

			var row_r:Array<Float> = [1.0]; // intercept
			for (back in 1...(lag + 1)) {
				row_r.push(a[now - back]);
			}

			var row_u:Array<Float> = row_r.copy();
			for (back in 1...(lag + 1)) {
				row_u.push(b[now - back]);
			}

			restricted.push(row_r);
			unrestricted.push(row_u);
		}

		// Calculate RSS for restricted and unrestricted models
		var rss_r = olsRss(restricted, target, lag + 1);
		var rss_u = olsRss(unrestricted, target, 2 * lag + 1);

		if (rss_r == null || rss_u == null) {
			return 0.0;
		}

		var dof = num_obs - (2 * lag + 1);
		if (dof <= 0) {
			return 0.0;
		}

		var numerator = (rss_r - rss_u) / lag;
		var denominator = rss_u / dof;

		if (denominator == 0.0) {
			return 0.0;
		}

		var f_stat = numerator / denominator;
		return f_stat > 0.0 ? f_stat : 0.0;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "GrangerCausality";

	/**
	 * Calculate residual sum of squares for OLS regression.
	 * Returns null if the normal equations are singular.
	 */
	static function olsRss(rows:Array<Array<Float>>, target:Array<Float>, numReg:Int):Null<Float> {
		// Build normal equations: X'X * theta = X'y
		var xtx:Array<Array<Float>> = [];
		for (i in 0...numReg) {
			xtx.push([]);
			for (j in 0...numReg) {
				xtx[i].push(0.0);
			}
		}

		var xty:Array<Float> = [];
		for (i in 0...numReg) {
			xty.push(0.0);
		}

		for (idx in 0...rows.length) {
			var row = rows[idx];
			var y = target[idx];
			for (i in 0...numReg) {
				xty[i] += row[i] * y;
				for (j in 0...numReg) {
					xtx[i][j] += row[i] * row[j];
				}
			}
		}

		// Solve the system
		var theta = solve(xtx, xty);
		if (theta == null) {
			return null;
		}

		// Calculate RSS
		var rss = 0.0;
		for (idx in 0...rows.length) {
			var row = rows[idx];
			var y = target[idx];
			var pred:Float = 0.0;
			for (j in 0...numReg) {
				pred += row[j] * theta[j];
			}
			var resid = y - pred;
			rss += resid * resid;
		}

		return rss;
	}

	/**
	 * Solve linear system mat·x = rhs using Gaussian elimination.
	 * Returns null if the matrix is singular.
	 */
	static function solve(mat:Array<Array<Float>>, rhs:Array<Float>):Null<Array<Float>> {
		var dim = rhs.length;

		// Create working copies
		var mat_copy:Array<Array<Float>> = [];
		for (i in 0...dim) {
			mat_copy.push(mat[i].copy());
		}
		var rhs_copy:Array<Float> = rhs.copy();

		// Forward elimination
		for (col in 0...dim) {
			var pivot = mat_copy[col][col];
			if (Math.abs(pivot) < 1e-12) {
				return null; // Singular matrix
			}

			// Eliminate below
			for (row in (col + 1)...dim) {
				var factor = mat_copy[row][col] / pivot;
				for (j in col...dim) {
					mat_copy[row][j] -= factor * mat_copy[col][j];
				}
				rhs_copy[row] -= factor * rhs_copy[col];
			}
		}

		// Back substitution
		var sol:Array<Float> = [];
		for (i in 0...dim) {
			sol.push(0.0);
		}

		var i = dim - 1;
		while (i >= 0) {
			var known:Float = 0.0;
			var j = i + 1;
			while (j < dim) {
				known += mat_copy[i][j] * sol[j];
				j++;
			}
			sol[i] = (rhs_copy[i] - known) / mat_copy[i][i];
			i--;
		}

		return sol;
	}

	static function isFinite(x:Float):Bool {
		return !Math.isNaN(x) && x != Math.POSITIVE_INFINITY && x != Math.NEGATIVE_INFINITY;
	}

	public static function spec():IndicatorSpec {
		return {
			name: "granger_causality", args: [TSeries, TSeries, TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var period = IndicatorCache.intArg(args, 2, 60);
				var lag = IndicatorCache.intArg(args, 3, 1);
				var key = 'granger_causality:${seriesA}:${seriesB}:${period}:${lag}';
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new GrangerCausality(period, lag),
					(i, a, b) -> (cast i : GrangerCausality).update({a: a, b: b}));
			}
		};
	}
}
