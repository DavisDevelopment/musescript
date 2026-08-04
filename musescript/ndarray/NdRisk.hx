package musescript.ndarray;

import musescript.ew.mcmc.DetMath;

/**
 * Risk / position-sizing helpers on f64 NdArrays (muse.np `vol_target_qty` / `mask_qty`).
 *
 * Pure Haxe; DetMath for log-returns. Helpers **return requested qty** only —
 * they do not replace `OrderSim` cash / `riskCappedQty` clamps at fill time
 * (`size = volume` and other oversizes are still sim-capped).
 */
class NdRisk {
	public static inline var DEFAULT_EPS = 1e-12;

	/**
	 * `qty = clip(base * targetVol / max(|vol|, eps), minQty, maxQty)`.
	 * `vol` / `base` broadcast.
	 */
	public static function volTargetQty(
		vol:NdArrayF64,
		targetVol:Float,
		base:NdArrayF64,
		?maxQty:Float,
		?minQty:Float,
		?eps:Float
	):Null<NdArrayF64> {
		if (vol == null || base == null) return null;
		if (!(targetVol == targetVol)) return null;
		var e = eps == null || !(eps == eps) || eps <= 0 ? DEFAULT_EPS : eps;
		var lo = minQty == null || !(minQty == minQty) ? 0.0 : minQty;
		var hi = maxQty == null || !(maxQty == maxQty) ? Math.POSITIVE_INFINITY : maxQty;
		if (hi < lo) {
			var t = lo;
			lo = hi;
			hi = t;
		}
		var plan = Broadcast.planFrom(vol, base);
		if (!plan.ok) return null;
		var out = NdArrayF64.empty(plan.outShape);
		var nOut = out.size;
		var ndim = plan.outShape.ndim;
		var outStrides = plan.outStrides;
		var aStrides = plan.aStrides;
		var bStrides = plan.bStrides;
		for (flat in 0...nOut) {
			var rem = flat;
			var aOff = vol.offset;
			var bOff = base.offset;
			for (ax in 0...ndim) {
				var idx = outStrides[ax] == 0 ? 0 : Std.int(rem / outStrides[ax]);
				rem = outStrides[ax] == 0 ? rem : rem % outStrides[ax];
				aOff += idx * aStrides[ax];
				bOff += idx * bStrides[ax];
			}
			var v = absf(vol.getBuf(aOff));
			if (!(v == v) || v < e) v = e;
			var q = base.getBuf(bOff) * targetVol / v;
			if (!(q == q)) q = lo;
			if (q < lo) q = lo;
			if (q > hi) q = hi;
			out.setFlat(flat, q);
		}
		return out;
	}

	/**
	 * Rolling realized vol of DetMath log-returns over `window` bars.
	 * Output length = prices.length; indices `< window` are NaN
	 * (need `window` returns ⇒ `window+1` prices before first finite vol at index `window`).
	 */
	public static function rollingLogVol(prices:NdArrayF64, window:Int, ?ddof:Int = 0):Null<NdArrayF64> {
		if (prices == null || prices.ndim != 1 || window < 1) return null;
		var n = prices.size;
		var out = NdArrayF64.empty([n]);
		for (i in 0...n) out.setFlat(i, Math.NaN);
		if (n < window + 1) return out;
		var rets = [for (_ in 0...(n - 1)) Math.NaN];
		for (i in 1...n) {
			var p0 = prices.getFlat(i - 1);
			var p1 = prices.getFlat(i);
			if (p0 > 0 && p1 > 0) rets[i - 1] = DetMath.log(p1) - DetMath.log(p0);
		}
		var dd = ddof < 0 ? 0 : ddof;
		for (i in window...n) {
			var start = i - window;
			var sum = 0.0;
			var count = 0;
			for (j in start...i) {
				var r = rets[j];
				if (r == r) {
					sum += r;
					count++;
				}
			}
			if (count <= dd) {
				out.setFlat(i, Math.NaN);
				continue;
			}
			var mean = sum / count;
			var ss = 0.0;
			for (j in start...i) {
				var r = rets[j];
				if (r == r) {
					var d = r - mean;
					ss += d * d;
				}
			}
			out.setFlat(i, Math.sqrt(ss / (count - dd)));
		}
		return out;
	}

	/**
	 * Vol-target from prices: rolling DetMath log-return std, then scale.
	 * Warmup bars (NaN vol) map to `minQty` (safe).
	 */
	public static function volTargetQtyFromPrices(
		prices:NdArrayF64,
		targetVol:Float,
		base:NdArrayF64,
		window:Int,
		?maxQty:Float,
		?minQty:Float,
		?eps:Float
	):Null<NdArrayF64> {
		var vol = rollingLogVol(prices, window);
		if (vol == null) return null;
		var lo = minQty == null || !(minQty == minQty) ? 0.0 : minQty;
		var filled = NdArrayF64.empty(vol.shape);
		var n = vol.size;
		for (i in 0...n) {
			var v = vol.getFlat(i);
			filled.setFlat(i, v == v ? v : Math.POSITIVE_INFINITY);
		}
		return volTargetQty(filled, targetVol, base, maxQty, lo, eps);
	}

	/**
	 * `mask × base_qty` with clamps: true → clip(base), false → 0.
	 * Bool mask; base scalar or array (broadcast).
	 */
	public static function maskQty(
		mask:NdArrayBool,
		base:NdArrayF64,
		?maxQty:Float,
		?minQty:Float
	):Null<NdArrayF64> {
		if (mask == null || base == null) return null;
		var lo = minQty == null || !(minQty == minQty) ? 0.0 : minQty;
		var hi = maxQty == null || !(maxQty == maxQty) ? Math.POSITIVE_INFINITY : maxQty;
		if (hi < lo) {
			var t = lo;
			lo = hi;
			hi = t;
		}
		var plan = Broadcast.plan(mask.shape, base.shape);
		if (!plan.ok) return null;
		var out = NdArrayF64.empty(plan.outShape);
		var pb = Broadcast.planFrom(base, null, plan.outShape);
		if (!pb.ok) return null;
		var cStrides = overlayBool(mask, plan.outShape);
		var nOut = out.size;
		var ndim = plan.outShape.ndim;
		var outStrides = plan.outStrides;
		var bStrides = pb.aStrides;
		for (flat in 0...nOut) {
			var rem = flat;
			var cOff = mask.offset;
			var bOff = base.offset;
			for (ax in 0...ndim) {
				var idx = outStrides[ax] == 0 ? 0 : Std.int(rem / outStrides[ax]);
				rem = outStrides[ax] == 0 ? rem : rem % outStrides[ax];
				cOff += idx * cStrides[ax];
				bOff += idx * bStrides[ax];
			}
			if (!mask.getBuf(cOff)) {
				out.setFlat(flat, 0.0);
				continue;
			}
			var q = base.getBuf(bOff);
			if (!(q == q)) q = lo;
			if (q < lo) q = lo;
			if (q > hi) q = hi;
			out.setFlat(flat, q);
		}
		return out;
	}

	static inline function absf(x:Float):Float
		return x < 0 ? -x : x;

	/** Same overlay as `NdUfuncs.overlayBool` — kept local (private there). */
	static function overlayBool(arr:NdArrayBool, outShape:Shape):Array<Int> {
		var as:Array<Int> = arr.shape;
		var real:Array<Int> = arr.strides;
		var n = outShape.ndim;
		var na = as.length;
		var pad = n - na;
		var out:Array<Int> = [for (_ in 0...n) 0];
		var outDims:Array<Int> = outShape;
		for (i in 0...n) {
			if (i < pad) continue;
			var ai = as[i - pad];
			var rs = real[i - pad];
			out[i] = (ai == 1 && outDims[i] != 1) ? 0 : rs;
		}
		return out;
	}
}
