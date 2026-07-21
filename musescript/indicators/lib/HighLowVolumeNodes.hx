package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** HVN/LVN output: the price of the highest- and lowest-volume node in the profile. */
typedef HighLowVolumeNodesOutput = {
	var hvn:Float;
	var lvn:Float;
}

/**
 * High/Low Volume Nodes — ported from wickra-core's `HighLowVolumeNodes`
 * (vendor/wickra/crates/wickra-core/src/indicators/high_low_volume_nodes.rs).
 *
 * Builds a `bins`-bucket volume profile over the last `period` candles.
 * The High Volume Node (HVN) is the bin centre of the bucket with the most
 * volume; the Low Volume Node (LVN) is the bin centre of the traded bucket
 * with the least volume (falling back to the HVN when no bin has traded).
 * Each candle's volume is spread across the price bins its high-low range
 * spans, as in `VolumeProfile`. A degenerate flat window puts both nodes at
 * the price.
 */
class HighLowVolumeNodes implements MuseIndicator<Bar, HighLowVolumeNodesOutput> {
	var period:Int;
	var bins:Int;
	var window:Array<Bar>;
	var last:Null<HighLowVolumeNodesOutput>;

	public function new(period:Int, bins:Int) {
		if (period <= 0 || bins <= 0) throw "HighLowVolumeNodes: period and bins must be > 0";
		this.period = period;
		this.bins = bins;
		this.window = [];
		this.last = null;
	}

	/** Configured `(period, bins)`. */
	public function params():{period:Int, bins:Int} {
		return {period: period, bins: bins};
	}

	/** Current value if available. */
	public function value():Null<HighLowVolumeNodesOutput> return last;

	/** Build the volume histogram; returns `(low, bin_width, bins)`. */
	function profile():{low:Float, width:Float, hist:Array<Float>} {
		var low = Math.POSITIVE_INFINITY;
		var high = Math.NEGATIVE_INFINITY;
		for (c in window) {
			if (c.low < low) low = c.low;
			if (c.high > high) high = c.high;
		}
		var hist = [for (_ in 0...bins) 0.0];
		var span = high - low;
		if (span <= 0.0) {
			var total = 0.0;
			for (c in window) total += c.volume;
			hist[0] = total;
			return {low: low, width: 0.0, hist: hist};
		}
		var width = span / bins;
		for (c in window) {
			if (c.volume == 0.0) continue;
			var loIdx = clampBin(Math.ffloor((c.low - low) / width));
			var hiIdx = clampBin(Math.ffloor((c.high - low) / width));
			var share = c.volume / (hiIdx - loIdx + 1);
			for (bin in loIdx...(hiIdx + 1)) {
				hist[bin] += share;
			}
		}
		return {low: low, width: width, hist: hist};
	}

	inline function clampBin(raw:Float):Int {
		var idx = Std.int(raw);
		return idx < bins - 1 ? idx : bins - 1;
	}

	public function update(bar:Bar):Null<HighLowVolumeNodesOutput> {
		if (window.length == period) window.shift();
		window.push(bar);
		if (window.length < period) return null;
		var p = profile();

		var hvnIdx = 0;
		var hvnVol = Math.NEGATIVE_INFINITY;
		var lvnIdx = 0;
		var lvnVol = Math.POSITIVE_INFINITY;
		for (idx in 0...p.hist.length) {
			var vol = p.hist[idx];
			if (vol > hvnVol) {
				hvnVol = vol;
				hvnIdx = idx;
			}
			if (vol > 0.0 && vol < lvnVol) {
				lvnVol = vol;
				lvnIdx = idx;
			}
		}
		// If no traded bin was found (all zero volume), both default to bin 0.
		if (!Math.isFinite(lvnVol)) lvnIdx = hvnIdx;
		var out:HighLowVolumeNodesOutput = {
			hvn: p.low + (hvnIdx + 0.5) * p.width,
			lvn: p.low + (lvnIdx + 0.5) * p.width
		};
		last = out;
		return out;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "HighLowVolumeNodes";

	public static function spec():IndicatorSpec {
		return {
			name: "high_low_volume_nodes", args: [TWindow, TWindow], ret: TObject([
				{name: "hvn", ty: TScalar}, {name: "lvn", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var b = IndicatorCache.intArg(args, 1, 24);
				return IndicatorCache.evalBar(h, "high_low_volume_nodes:" + p + ":" + b, {hvn: Math.NaN, lvn: Math.NaN},
					() -> new HighLowVolumeNodes(p, b), (i, bar) -> (cast i : HighLowVolumeNodes).update(bar));
			}
		};
	}
}
