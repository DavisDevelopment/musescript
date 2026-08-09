package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Know Sure Thing (Pring): a weighted sum of four SMA-smoothed
 * rate-of-change terms at increasing lookback lengths, blending short- and
 * long-term momentum into a single oscillator.
 *
 * RCMA_k = SMA( ROC(price, rocPeriod_k), smaPeriod_k )
 * KST = 1*RCMA1 + 2*RCMA2 + 3*RCMA3 + 4*RCMA4
 *
 * Classic parameters: rocPeriods = (10, 15, 20, 30), smaPeriods = (10, 10, 10, 15).
 */
class Kst implements MuseIndicator<Float, Float> {
	var rocPeriods:Array<Int>;
	var smas:Array<Sma>;
	var history:RingBuffer<Float>;
	var maxRoc:Int;

	public function new(rocPeriods:Array<Int>, smaPeriods:Array<Int>) {
		if (rocPeriods.length != 4 || smaPeriods.length != 4) throw "Kst: exactly 4 ROC/SMA periods required";
		this.rocPeriods = rocPeriods;
		smas = [for (p in smaPeriods) new Sma(p)];
		maxRoc = 0;
		for (p in rocPeriods) if (p > maxRoc) maxRoc = p;
		history = new RingBuffer(maxRoc + 1);
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;

		history.push(price);

		var total = 0.0;
		var anyMissing = false;
		for (k in 0...4) {
			var rocPeriod = rocPeriods[k];
			if (history.length <= rocPeriod) { anyMissing = true; continue; }
			var past = history.at(rocPeriod);
			var cur = history.at(0);
			var roc = past == 0.0 ? 0.0 : (cur - past) / past * 100.0;
			var rcma = smas[k].update(roc);
			if (rcma == null) { anyMissing = true; continue; }
			total += (k + 1) * rcma;
		}
		return anyMissing ? null : total;
	}

	public function reset():Void {
		for (s in smas) s.reset();
		history = new RingBuffer(maxRoc + 1);
	}

	public function warmupPeriod():Int {
		var maxWarmup = 0;
		for (k in 0...4) {
			var w = rocPeriods[k] + smas[k].period;
			if (w > maxWarmup) maxWarmup = w;
		}
		return maxWarmup;
	}
	public function isReady():Bool {
		for (s in smas) if (!s.isReady()) return false;
		return true;
	}
	public function name():String return "Kst";

	public static function spec():IndicatorSpec {
		return {
			name: "kst", args: [TSeries], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "kst:" + series, series, Math.NaN,
					() -> new Kst([10, 15, 20, 30], [10, 10, 10, 15]), (i, v) -> (cast i : Kst).update(v));
			}
		};
	}
}
