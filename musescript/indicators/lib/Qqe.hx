package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.indicators.prim.Rsi;
import musescript.types.MuseType;

/** QQE output: the smoothed RSI and its volatility-trailing line. */
typedef QqeOutput = {
	var rsiMa:Float;
	var trailingLine:Float;
}

/**
 * QQE — Quantitative Qualitative Estimation — ported from wickra-core's `Qqe`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/qqe.rs).
 *
 * QQE smooths the RSI, then builds an "ATR of the RSI" trailing stop around it.
 * Crossovers of the smoothed RSI and that trailing line give cleaner momentum
 * signals than the raw RSI.
 */
class Qqe implements MuseIndicator<Float, QqeOutput> {
	var rsi:Rsi;
	var rsiMa:Ema;
	var maAtr:Ema;
	var darEma:Ema;
	var factor:Float;
	var prevRsiMa:Null<Float>;
	var bands:Null<{long:Float, short:Float, trend:Int}>;
	var lastValue:Null<QqeOutput>;

	public function new(rsiPeriod:Int, smoothing:Int, factor:Float) {
		if (rsiPeriod <= 0 || smoothing <= 0) throw "Qqe: periods must be > 0";
		if (!Math.isFinite(factor) || factor <= 0.0) throw "Qqe: factor must be a finite positive value";
		var wilders = 2 * rsiPeriod - 1;
		this.rsi = new Rsi(rsiPeriod);
		this.rsiMa = new Ema(smoothing);
		this.maAtr = new Ema(wilders);
		this.darEma = new Ema(wilders);
		this.factor = factor;
		this.prevRsiMa = null;
		this.bands = null;
		this.lastValue = null;
	}

	public function update(price:Float):Null<QqeOutput> {
		var rsiVal = rsi.update(price);
		if (rsiVal == null) return null;
		var rsiMaVal = rsiMa.update(rsiVal);
		if (rsiMaVal == null) return null;

		var prevMa = prevRsiMa;
		if (prevMa == null) {
			prevRsiMa = rsiMaVal;
			return null;
		}
		var atrRsi = Math.abs(rsiMaVal - prevMa);
		prevRsiMa = rsiMaVal;

		var maAtrVal = maAtr.update(atrRsi);
		if (maAtrVal == null) return null;
		var dar = darEma.update(maAtrVal);
		if (dar == null) return null;
		dar = dar * factor;

		var newLong = rsiMaVal - dar;
		var newShort = rsiMaVal + dar;

		var long:Float;
		var short:Float;
		var trend:Int;

		if (bands != null) {
			var lbPrev = bands.long;
			var sbPrev = bands.short;
			var trPrev = bands.trend;

			long = if (prevMa > lbPrev && rsiMaVal > lbPrev) {
				Math.max(lbPrev, newLong);
			} else {
				newLong;
			};

			short = if (prevMa < sbPrev && rsiMaVal < sbPrev) {
				Math.min(sbPrev, newShort);
			} else {
				newShort;
			};

			trend = if (prevMa <= sbPrev && rsiMaVal > sbPrev) {
				1;
			} else if (prevMa >= lbPrev && rsiMaVal < lbPrev) {
				-1;
			} else {
				trPrev;
			};
		} else {
			long = newLong;
			short = newShort;
			trend = 1;
		}

		bands = {long: long, short: short, trend: trend};
		var trailingLine = if (trend == 1) long else short;
		var out:QqeOutput = {rsiMa: rsiMaVal, trailingLine: trailingLine};
		lastValue = out;
		return out;
	}

	public function reset():Void {
		rsi.reset();
		rsiMa.reset();
		maAtr.reset();
		darEma.reset();
		prevRsiMa = null;
		bands = null;
		lastValue = null;
	}

	public function warmupPeriod():Int {
		// RSI (rsi_period + 1) -> rsi_ma EMA -> one bar for the first atr_rsi ->
		// ma_atr EMA -> dar EMA. Expressed via the component warmups.
		return rsi.warmupPeriod() + rsiMa.warmupPeriod() + maAtr.warmupPeriod() + darEma.warmupPeriod() - 2;
	}

	public function isReady():Bool return lastValue != null;
	public function name():String return "QQE";

	public static function spec():IndicatorSpec {
		return {
			name: "qqe", args: [TWindow, TWindow, TScalar], ret: TObject([
				{name: "rsiMa", ty: TScalar}, {name: "trailingLine", ty: TScalar}
			]), minArgs: 3,
			eval: function(h, args) {
				var rsiPeriod = IndicatorCache.intArg(args, 0, 14);
				var smoothing = IndicatorCache.intArg(args, 1, 5);
				var f = IndicatorCache.floatArg(args, 2, 4.236);
				var nanFill:QqeOutput = {rsiMa: Math.NaN, trailingLine: Math.NaN};
				return IndicatorCache.evalSeries(h, "qqe:" + rsiPeriod + ":" + smoothing + ":" + f, "close", nanFill,
					() -> new Qqe(rsiPeriod, smoothing, f), (i, v) -> (cast i : Qqe).update(v));
			}
		};
	}
}
