package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * GARCH(1,1) conditional volatility — ported from wickra-core's `Garch11`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/garch11.rs).
 *
 * Conditional volatility via generalized-autoregressive-conditional-heteroskedasticity:
 * r_t = ln(price_t / price_{t−1})
 * σ²_t = ω + α · r²_{t−1} + β · σ²_{t−1}
 * output = √σ²_t
 */
class Garch11 implements MuseIndicator<Float, Float> {
	var omega:Float;
	var alpha:Float;
	var beta:Float;
	var unconditional:Float;
	var prevPrice:Null<Float>;
	var state:Null<{prevVar: Float, prevRSq: Float}>;
	var last:Null<Float>;

	public function new(omega:Float, alpha:Float, beta:Float) {
		if (!isFinite(omega) || !isFinite(alpha) || !isFinite(beta)) {
			throw "GARCH(1,1) parameters must be finite";
		}
		if (omega <= 0.0) {
			throw "GARCH(1,1) omega must be > 0";
		}
		if (alpha < 0.0 || beta < 0.0) {
			throw "GARCH(1,1) alpha and beta must be >= 0";
		}
		if (alpha + beta >= 1.0) {
			throw "GARCH(1,1) requires alpha + beta < 1 (covariance stationarity)";
		}

		this.omega = omega;
		this.alpha = alpha;
		this.beta = beta;
		this.unconditional = omega / (1.0 - alpha - beta);
		this.prevPrice = null;
		this.state = null;
		this.last = null;
	}

	public function update(input:Float):Null<Float> {
		// Non-finite or non-positive prices are skipped
		if (!isFinite(input) || input <= 0.0) {
			return last;
		}

		var prev = prevPrice;
		if (prev == null) {
			prevPrice = input;
			return null;
		}

		prevPrice = input;

		// Calculate log return
		var r = Math.log(input / prev);
		var r_sq = r * r;

		// Calculate variance
		var variance:Float;
		if (state == null) {
			variance = unconditional;
		} else {
			variance = omega + alpha * state.prevRSq + beta * state.prevVar;
		}

		state = {prevVar: variance, prevRSq: r_sq};

		// Volatility is sqrt of variance
		var vol = Math.sqrt(variance);
		last = vol;
		return vol;
	}

	public function reset():Void {
		prevPrice = null;
		state = null;
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "Garch11";

	static function isFinite(x:Float):Bool {
		return !Math.isNaN(x) && x != Math.POSITIVE_INFINITY && x != Math.NEGATIVE_INFINITY;
	}

	public static function spec():IndicatorSpec {
		return {
			name: "garch11", args: [TSeries, TScalar, TScalar, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				// arg 0 is the SERIES (declared TSeries above) — omega/alpha/beta
				// follow it. Reading omega from slot 0 worked by accident on JS
				// (string silently coerces, constructor then rejects) but is a
				// hard ClassCastException on the JVM target.
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var omega = IndicatorCache.floatArg(args, 1, 0.000002);
				var alpha = IndicatorCache.floatArg(args, 2, 0.1);
				var beta = IndicatorCache.floatArg(args, 3, 0.88);
				var key = 'garch11:${series}:${omega}:${alpha}:${beta}';
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Garch11(omega, alpha, beta), (i, p) -> (cast i : Garch11).update(p));
			}
		};
	}
}
