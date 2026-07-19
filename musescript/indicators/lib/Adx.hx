package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** ADX output: the three Wilder lines. */
typedef AdxOutput = {
	var plusDi:Float;
	var minusDi:Float;
	var adx:Float;
}

/**
 * Wilder's Average Directional Index — ported from wickra-core's `Adx`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adx.rs).
 *
 * Uses Wilder smoothing throughout. First `period` candles seed the directional
 * movement / true range sums; the next `period` candles produce DX values that
 * seed the ADX. The first complete `AdxOutput` is emitted after `2 * period`
 * candles.
 */
class Adx implements MuseIndicator<Bar, AdxOutput> {
	var period:Int;
	var prev:Null<Bar>;
	var trSeed:Float;
	var plusDmSeed:Float;
	var minusDmSeed:Float;
	var seedCount:Int;
	var trSmooth:Null<Float>;
	var plusDmSmooth:Null<Float>;
	var minusDmSmooth:Null<Float>;
	var dxBuf:Array<Float>;
	var adxValue:Null<Float>;
	var lastPlusDi:Float;
	var lastMinusDi:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Adx: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(candle:Bar):Null<AdxOutput> {
		if (prev == null) {
			prev = candle;
			return null;
		}

		var tr = trueRange(prev, candle);
		var dm = directionalMovement(prev, candle);
		var plusDm = dm.plusDm;
		var minusDm = dm.minusDm;
		var n:Float = period;

		var trV:Float;
		var plusV:Float;
		var minusV:Float;

		if (trSmooth != null && plusDmSmooth != null && minusDmSmooth != null) {
			trV = trSmooth - trSmooth / n + tr;
			plusV = plusDmSmooth - plusDmSmooth / n + plusDm;
			minusV = minusDmSmooth - minusDmSmooth / n + minusDm;
			trSmooth = trV;
			plusDmSmooth = plusV;
			minusDmSmooth = minusV;
		} else {
			trSeed += tr;
			plusDmSeed += plusDm;
			minusDmSeed += minusDm;
			seedCount++;
			if (seedCount < period) {
				prev = candle;
				return null;
			}
			trSmooth = trSeed;
			plusDmSmooth = plusDmSeed;
			minusDmSmooth = minusDmSeed;
			trV = trSeed;
			plusV = plusDmSeed;
			minusV = minusDmSeed;
		}

		var plusDi = trV == 0.0 ? 0.0 : 100.0 * plusV / trV;
		var minusDi = trV == 0.0 ? 0.0 : 100.0 * minusV / trV;
		lastPlusDi = plusDi;
		lastMinusDi = minusDi;

		var dxDen = plusDi + minusDi;
		var dx = dxDen == 0.0 ? 0.0 : 100.0 * Math.abs(plusDi - minusDi) / dxDen;

		if (adxValue != null) {
			var newAdx = (adxValue * (n - 1.0) + dx) / n;
			adxValue = newAdx;
			prev = candle;
			return { plusDi: plusDi, minusDi: minusDi, adx: newAdx };
		}

		dxBuf.push(dx);
		if (dxBuf.length == period) {
			var seed = 0.0;
			for (d in dxBuf) seed += d;
			seed = seed / n;
			adxValue = seed;
			prev = candle;
			return { plusDi: plusDi, minusDi: minusDi, adx: seed };
		}

		prev = candle;
		return null;
	}

	public function reset():Void {
		prev = null;
		trSeed = 0.0;
		plusDmSeed = 0.0;
		minusDmSeed = 0.0;
		seedCount = 0;
		trSmooth = null;
		plusDmSmooth = null;
		minusDmSmooth = null;
		dxBuf = [];
		adxValue = null;
		lastPlusDi = 0.0;
		lastMinusDi = 0.0;
	}

	public function warmupPeriod():Int return 2 * period;
	public function isReady():Bool return adxValue != null;
	public function name():String return "ADX";

	static function trueRange(prev:Bar, current:Bar):Float {
		var hl = current.high - current.low;
		var hc = Math.abs(current.high - prev.close);
		var lc = Math.abs(current.low - prev.close);
		return Math.max(hl, Math.max(hc, lc));
	}

	static function directionalMovement(prev:Bar, current:Bar):{plusDm:Float, minusDm:Float} {
		var up = current.high - prev.high;
		var down = prev.low - current.low;
		var plusDm = (up > down && up > 0.0) ? up : 0.0;
		var minusDm = (down > up && down > 0.0) ? down : 0.0;
		return { plusDm: plusDm, minusDm: minusDm };
	}

	public static function spec():IndicatorSpec {
		return {
			name: "adx", args: [TWindow], ret: TObject([
				{name: "plus_di", ty: TScalar}, {name: "minus_di", ty: TScalar}, {name: "adx", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				var nanFill = { plusDi: Math.NaN, minusDi: Math.NaN, adx: Math.NaN };
				return IndicatorCache.evalBar(h, "adx:" + p, nanFill,
					() -> new Adx(p), (i, b) -> (cast i : Adx).update(b));
			}
		};
	}
}
