package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Naked POC — ported from wickra-core's `NakedPoc`
 * (vendor/wickra/crates/wickra-core/src/indicators/naked_poc.rs).
 *
 * The nearest untested point of control from a prior session. Every
 * `session_len` candles forms a session; its POC (heaviest-volume price) is
 * recorded as "naked". A naked POC becomes "tested" once a later candle's
 * high-low range covers it. The output is the nearest still-naked POC to
 * the current close (or the close itself if every prior POC has been
 * revisited). The first value lands after `session_len` candles.
 */
class NakedPoc implements MuseIndicator<Bar, Float> {
	var sessionLen:Int;
	var bins:Int;
	var session:Array<Bar>;
	var naked:Array<Float>;
	var lastClose:Float;
	var ready:Bool;
	var last:Null<Float>;

	public function new(sessionLen:Int, bins:Int) {
		if (sessionLen <= 0 || bins <= 0) throw "NakedPoc: session_len and bins must be > 0";
		this.sessionLen = sessionLen;
		this.bins = bins;
		this.session = [];
		this.naked = [];
		this.lastClose = 0.0;
		this.ready = false;
		this.last = null;
	}

	/** Configured `(session_len, bins)`. */
	public function params():{sessionLen:Int, bins:Int} {
		return {sessionLen: sessionLen, bins: bins};
	}

	/** Number of currently-naked POCs. */
	public function nakedCount():Int return naked.length;

	/** Current value if available. */
	public function value():Null<Float> return last;

	function sessionPoc():Float {
		var low = Math.POSITIVE_INFINITY;
		var high = Math.NEGATIVE_INFINITY;
		for (c in session) {
			if (c.low < low) low = c.low;
			if (c.high > high) high = c.high;
		}
		var span = high - low;
		if (span <= 0.0) return low;
		var width = span / bins;
		var hist = [for (_ in 0...bins) 0.0];
		for (c in session) {
			if (c.volume == 0.0) continue;
			var loIdx = clampBin(Math.ffloor((c.low - low) / width));
			var hiIdx = clampBin(Math.ffloor((c.high - low) / width));
			var share = c.volume / (hiIdx - loIdx + 1);
			for (bin in loIdx...(hiIdx + 1)) {
				hist[bin] += share;
			}
		}
		var poc = 0;
		var pocVol = Math.NEGATIVE_INFINITY;
		for (idx in 0...hist.length) {
			if (hist[idx] > pocVol) {
				pocVol = hist[idx];
				poc = idx;
			}
		}
		return low + (poc + 0.5) * width;
	}

	inline function clampBin(raw:Float):Int {
		var idx = Std.int(raw);
		return idx < bins - 1 ? idx : bins - 1;
	}

	public function update(bar:Bar):Null<Float> {
		// Test outstanding naked POCs against this candle's range.
		naked = [for (poc in naked) if (!(bar.low <= poc && poc <= bar.high)) poc];
		lastClose = bar.close;

		// Accumulate the session; finalize a POC at the boundary.
		session.push(bar);
		if (session.length == sessionLen) {
			var poc = sessionPoc();
			naked.push(poc);
			session = [];
			ready = true;
		}

		if (!ready) return null;
		var nearest = lastClose;
		var bestDist = Math.POSITIVE_INFINITY;
		for (poc in naked) {
			var d = Math.abs(poc - lastClose);
			if (d < bestDist) {
				bestDist = d;
				nearest = poc;
			}
		}
		last = nearest;
		return nearest;
	}

	public function reset():Void {
		session = [];
		naked = [];
		lastClose = 0.0;
		ready = false;
		last = null;
	}

	public function warmupPeriod():Int return sessionLen;
	public function isReady():Bool return last != null;
	public function name():String return "NakedPoc";

	public static function spec():IndicatorSpec {
		return {
			name: "naked_poc", args: [TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var s = IndicatorCache.intArg(args, 0, 20);
				var b = IndicatorCache.intArg(args, 1, 24);
				return IndicatorCache.evalBar(h, "naked_poc:" + s + ":" + b, Math.NaN,
					() -> new NakedPoc(s, b), (i, bar) -> (cast i : NakedPoc).update(bar));
			}
		};
	}
}
