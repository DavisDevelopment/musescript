package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** STARC Bands output: upper/middle/lower. */
typedef StarcBandsOutput = {
	/** Upper band: middle + multiplier · ATR. */
	var upper:Float;
	/** Middle band: SMA of close. */
	var middle:Float;
	/** Lower band: middle − multiplier · ATR. */
	var lower:Float;
}

/**
 * STARC Bands (Stoller Average Range Channel) — ported from wickra-core's
 * `StarcBands`
 * (vendor/wickra/crates/wickra-core/src/indicators/starc_bands.rs).
 *
 *   middle = SMA(close, smaPeriod)
 *   upper  = middle + multiplier · ATR(atrPeriod)
 *   lower  = middle − multiplier · ATR(atrPeriod)
 *
 * Same skeleton as Keltner, but the centerline is an SMA of the close rather
 * than an EMA of the typical price. Stoller's reference parameters are
 * SMA(6), ATR(15), multiplier 2.0.
 */
class StarcBands implements MuseIndicator<Bar, StarcBandsOutput> {
	var sma:Sma;
	var atr:Atr;
	var multiplier:Float;
	var smaPeriod:Int;
	var atrPeriod:Int;

	public function new(smaPeriod:Int, atrPeriod:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "StarcBands: multiplier must be positive and finite";
		sma = new Sma(smaPeriod);
		atr = new Atr(atrPeriod);
		this.multiplier = multiplier;
		this.smaPeriod = smaPeriod;
		this.atrPeriod = atrPeriod;
	}

	/** Stoller's classic configuration: SMA(6), ATR(15), multiplier 2.0. */
	public static function classic():StarcBands {
		return new StarcBands(6, 15, 2.0);
	}

	public function update(bar:Bar):Null<StarcBandsOutput> {
		// Feed both unconditionally so SMA and ATR warm up in parallel.
		var mid = sma.update(bar.close);
		var atrVal = atr.update(bar);
		if (mid == null || atrVal == null) return null;
		return {
			upper: mid + multiplier * atrVal,
			middle: mid,
			lower: mid - multiplier * atrVal
		};
	}

	public function reset():Void {
		sma.reset();
		atr.reset();
	}

	public function warmupPeriod():Int return smaPeriod > atrPeriod ? smaPeriod : atrPeriod;
	public function isReady():Bool return sma.isReady() && atr.isReady();
	public function name():String return "StarcBands";

	public static function spec():IndicatorSpec {
		return {
			name: "starc_bands", args: [TWindow, TWindow, TScalar], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var sp = IndicatorCache.intArg(args, 0, 6);
				var ap = IndicatorCache.intArg(args, 1, 15);
				var m = IndicatorCache.floatArg(args, 2, 2.0);
				var key = "starc_bands:" + sp + ":" + ap + ":" + m;
				return IndicatorCache.evalBar(h, key, {upper: Math.NaN, middle: Math.NaN, lower: Math.NaN},
					() -> new StarcBands(sp, ap, m), (i, b) -> (cast i : StarcBands).update(b));
			}
		};
	}
}
