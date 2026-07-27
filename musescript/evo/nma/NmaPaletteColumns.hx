package musescript.evo.nma;

import musescript.indicators.GrowableVec;

/**
 * Full-tape columnar kernels for the evo-palette dozen — bit-exact with `TradeBuiltins` on a
 * growing prefix, without the growing prefix.
 *
 * `EngineIndicatorProvider.paletteColumn` used to mint five empty `Array<Float>` and `.push` every
 * bar of every field into them so `TradeBuiltins.resolveSeries` could see length == i+1. On the JVM
 * target that is one `java.lang.Double` allocation per push (JIT guide §3.1), and under `--nma` it
 * dominated process allocation — measured as the reason the evaluation barrier would not shrink
 * with `--threads` (work expands into allocator contention).
 *
 * These kernels read the tape's existing arrays with indexed loops and write an unboxed
 * `GrowableVec<Float>` column. Same recurrence / window arithmetic as TradeBuiltins' named-series
 * path (ema/rma seed and step; sma/rsi/stdev/highest/lowest/wma trailing window; atr true-range
 * then trailing mean). Parity is pinned by `TestNmaFitness` / `TestNmaEvalEngine`.
 *
 * «ἄνευ προφάσεως· ὁ καρπὸς ἐν τῷ τέλει.»
 */
class NmaPaletteColumns {
	public static function columnFromVec(name:String, src:GrowableVec<Float>, window:Int):GrowableVec<Float> {
		var n = src.length;
		var a = new Array<Float>();
		// One materialization: subsequent kernel reads are from this array's storage. Still boxed,
		// but O(n) once — not O(n) pushes × fields × bars of fresh Doubles into growing prefixes.
		var i = 0;
		while (i < n) { a.push(src.at(i)); i++; }
		return column(name, a, window);
	}

	public static function column(name:String, src:Array<Float>, window:Int,
			?high:Array<Float>, ?low:Array<Float>, ?close:Array<Float>):GrowableVec<Float> {
		return switch (name) {
			case "sma": sma(src, window);
			case "ema": ema(src, window);
			case "rsi": rsi(src, window);
			case "atr": atr(high, low, close != null ? close : src, window);
			case "wma": wma(src, window);
			case "rma": rma(src, window);
			case "stdev": stdev(src, window);
			case "highest": highest(src, window);
			case "lowest": lowest(src, window);
			case "mom" | "change": change(src, window);
			case "roc": roc(src, window);
			default: throw 'NmaPaletteColumns: "$name" is not a palette indicator';
		};
	}

	static function sma(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			if (len <= 0 || i + 1 < len) col.push(Math.NaN);
			else {
				var sum = 0.0;
				var j = i + 1 - len;
				while (j <= i) { sum += a[j]; j++; }
				col.push(sum / len);
			}
			i++;
		}
		return col;
	}

	/** Named-series ema path: seed `a[0]`, then `k=2/(len+1)` recurrence (TradeBuiltins.ema). */
	static function ema(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (n == 0) return col;
		var k = 2 / (len + 1);
		var e = a[0];
		col.push(e);
		var i = 1;
		while (i < n) {
			e = a[i] * k + e * (1 - k);
			col.push(e);
			i++;
		}
		return col;
	}

	static function rsi(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			if (len <= 0 || i < len) col.push(Math.NaN);
			else {
				var gains = 0.0, losses = 0.0;
				var j = i - len + 1;
				while (j <= i) {
					var d = a[j] - a[j - 1];
					if (d >= 0) gains += d; else losses -= d;
					j++;
				}
				if (losses == 0) col.push(100);
				else {
					var rs = gains / losses;
					col.push(100 - (100 / (1 + rs)));
				}
			}
			i++;
		}
		return col;
	}

	static function atr(h:Array<Float>, l:Array<Float>, c:Array<Float>, len:Int):GrowableVec<Float> {
		var n = c != null ? c.length : 0;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (h == null || l == null || c == null || n < 2) {
			var i = 0;
			while (i < n) { col.push(Math.NaN); i++; }
			return col;
		}
		// col[i] = ATR at bar i. TradeBuiltins: true ranges live at indices 0..m-2 for bars 1..m-1,
		// then trailing mean over the last `len` true ranges ending at m-1 → value at bar m
		// (c.length-1). Bar 0 is always NaN; bars before enough TRs are NaN.
		col.push(Math.NaN);
		var tr = new GrowableVec<Float>(n > 1 ? n - 1 : 8);
		var i = 1;
		while (i < n) {
			var trI = Math.max(h[i] - l[i], Math.max(Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1])));
			tr.push(trI);
			var m = i; // c.length-1 equivalent at this prefix
			if (m < len) col.push(Math.NaN);
			else {
				var sum = 0.0;
				var j = m - len;
				while (j < m) { sum += tr.at(j); j++; }
				col.push(sum / len);
			}
			i++;
		}
		return col;
	}

	static function wma(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			if (len <= 0 || i + 1 < len) col.push(Math.NaN);
			else {
				var num = 0.0, den = 0.0;
				var start = i + 1 - len;
				var w = 1;
				var j = start;
				while (j <= i) {
					num += a[j] * w;
					den += w;
					w++;
					j++;
				}
				col.push(num / den);
			}
			i++;
		}
		return col;
	}

	/** Wilder RMA named-series path (TradeBuiltins.rma): every prefix length gets a value. */
	static function rma(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (n == 0 || len <= 0) return col;
		var alpha = 1.0 / len;
		var i = 0;
		while (i < n) {
			var prefixLen = i + 1;
			if (prefixLen < len) {
				var r = a[0];
				var j = 1;
				while (j < prefixLen) {
					r = alpha * a[j] + (1 - alpha) * r;
					j++;
				}
				col.push(r);
			} else if (prefixLen == len) {
				var sum = 0.0;
				var j = 0;
				while (j < len) { sum += a[j]; j++; }
				col.push(sum / len);
			} else {
				col.push(alpha * a[i] + (1 - alpha) * col.at(i - 1));
			}
			i++;
		}
		return col;
	}

	static function stdev(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			if (len <= 0 || i + 1 < len) col.push(Math.NaN);
			else {
				var sum = 0.0;
				var j = i + 1 - len;
				while (j <= i) { sum += a[j]; j++; }
				var mid = sum / len;
				var var_ = 0.0;
				j = i + 1 - len;
				while (j <= i) {
					var d = a[j] - mid;
					var_ += d * d;
					j++;
				}
				col.push(Math.sqrt(var_ / len));
			}
			i++;
		}
		return col;
	}

	static function highest(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			var start = len <= 0 ? 0 : Std.int(Math.max(0, i + 1 - len));
			var m = a[start];
			var j = start;
			while (j <= i) {
				if (a[j] > m) m = a[j];
				j++;
			}
			col.push(m);
			i++;
		}
		return col;
	}

	static function lowest(a:Array<Float>, len:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			var start = len <= 0 ? 0 : Std.int(Math.max(0, i + 1 - len));
			var m = a[start];
			var j = start;
			while (j <= i) {
				if (a[j] < m) m = a[j];
				j++;
			}
			col.push(m);
			i++;
		}
		return col;
	}

	static function change(a:Array<Float>, nBars:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var k = nBars < 1 ? 1 : nBars;
		var i = 0;
		while (i < n) {
			if (i < k) col.push(Math.NaN);
			else col.push(a[i] - a[i - k]);
			i++;
		}
		return col;
	}

	static function roc(a:Array<Float>, nBars:Int):GrowableVec<Float> {
		var n = a.length;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var k = nBars < 1 ? 1 : nBars;
		var i = 0;
		while (i < n) {
			if (i < k) col.push(Math.NaN);
			else {
				var prev = a[i - k];
				col.push(prev == 0 ? Math.NaN : ((a[i] - prev) / prev) * 100);
			}
			i++;
		}
		return col;
	}
}
