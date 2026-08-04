package musescript.ndarray;

/**
 * NumPy-style broadcasting planner used by ufuncs.
 *
 * Right-align shapes; each axis size must be equal or 1. Output axis size is
 * the non-1 (or either if both 1). Planned strides for a source are 0 on
 * broadcast axes so a single linear walk works over the contiguous out buffer.
 *
 * `planFrom` overlays real NdArray strides (M2 views) onto the broadcast plan.
 */
typedef BroadcastPlan = {
	var outShape:Shape;
	/** C-order out strides (contiguous). */
	var outStrides:Array<Int>;
	/** Effective strides into operand A (0 = broadcast). Length = out.ndim. */
	var aStrides:Array<Int>;
	/** Effective strides into operand B (0 = broadcast). Length = out.ndim. */
	var bStrides:Array<Int>;
	var ok:Bool;
	var ?error:String;
}

class Broadcast {
	/**
	 * Plan binary broadcast of shapes `a` and `b`.
	 * On failure `ok` is false and `error` explains why (no throw — call sites choose).
	 */
	public static function plan(a:Shape, b:Shape):BroadcastPlan {
		var as:Array<Int> = a;
		var bs:Array<Int> = b;
		var na = as.length;
		var nb = bs.length;
		var n = na > nb ? na : nb;
		var outDims:Array<Int> = [for (_ in 0...n) 0];
		var aEff:Array<Int> = [for (_ in 0...n) 0];
		var bEff:Array<Int> = [for (_ in 0...n) 0];

		for (i in 0...n) {
			var ai = i < n - na ? 1 : as[i - (n - na)];
			var bi = i < n - nb ? 1 : bs[i - (n - nb)];
			if (ai < 0 || bi < 0)
				return fail("negative dimension");
			if (ai != bi && ai != 1 && bi != 1)
				return fail('broadcast: axis $i sizes $ai vs $bi');
			outDims[i] = ai > bi ? ai : bi;
			aEff[i] = ai;
			bEff[i] = bi;
		}

		var outShape:Shape = outDims;
		var outStrides = outShape.cStrides();
		var aContig = cStridesPadded(aEff, n);
		var bContig = cStridesPadded(bEff, n);
		var aStrides:Array<Int> = [];
		var bStrides:Array<Int> = [];
		for (i in 0...n) {
			aStrides.push(aEff[i] == 1 && outDims[i] != 1 ? 0 : aContig[i]);
			bStrides.push(bEff[i] == 1 && outDims[i] != 1 ? 0 : bContig[i]);
		}
		return {
			outShape: outShape,
			outStrides: outStrides,
			aStrides: aStrides,
			bStrides: bStrides,
			ok: true
		};
	}

	/**
	 * Like `plan`, but substitute real strides from `a` / `b` arrays when present.
	 * Pass `outShapeOverride` to force a unary expand (second operand ignored).
	 */
	public static function planFrom(a:NdArrayF64, b:Null<NdArrayF64>, ?outShapeOverride:Array<Int>):BroadcastPlan {
		if (a == null) return fail("null a");
		if (outShapeOverride != null)
			return planFromMeta(a.shape, a.strides, null, null, outShapeOverride);
		if (b == null) return fail("null b");
		return planFromMeta(a.shape, a.strides, b.shape, b.strides);
	}

	/**
	 * Dtype-agnostic stride overlay — used by F32/I32/F64 kernels.
	 * Pass `outShapeOverride` for unary expand (`bShape` / `bStrides` ignored).
	 */
	public static function planFromMeta(
		aShape:Shape,
		aStrides:Array<Int>,
		bShape:Null<Shape>,
		bStrides:Null<Array<Int>>,
		?outShapeOverride:Array<Int>
	):BroadcastPlan {
		var base:BroadcastPlan;
		if (outShapeOverride != null) {
			base = plan(aShape, outShapeOverride);
			if (!base.ok) return base;
			base.aStrides = overlayStrides(aShape, aStrides, base.outShape);
			base.bStrides = [for (_ in 0...base.outShape.ndim) 0];
			return base;
		}
		if (bShape == null || bStrides == null) return fail("null b");
		base = plan(aShape, bShape);
		if (!base.ok) return base;
		base.aStrides = overlayStrides(aShape, aStrides, base.outShape);
		base.bStrides = overlayStrides(bShape, bStrides, base.outShape);
		return base;
	}

	/** Overlay real array strides onto a right-aligned broadcast plan's stride list. */
	static function overlayStrides(shape:Shape, realStrides:Array<Int>, outShape:Shape):Array<Int> {
		var as:Array<Int> = shape;
		var real:Array<Int> = realStrides;
		var n = outShape.ndim;
		var na = as.length;
		var pad = n - na;
		var out:Array<Int> = [for (_ in 0...n) 0];
		var outDims:Array<Int> = outShape;
		for (i in 0...n) {
			if (i < pad) {
				out[i] = 0; // left-padded implicit dim-1
				continue;
			}
			var ai = as[i - pad];
			var rs = real[i - pad];
			if (ai == 1 && outDims[i] != 1) out[i] = 0;
			else out[i] = rs;
		}
		return out;
	}

	/** Unary "plan": identity walk over `a` (used by reductions / unary ufuncs). */
	public static function planUnary(a:Shape):BroadcastPlan {
		var empty:Shape = [];
		return plan(a, empty);
	}

	static function cStridesPadded(dims:Array<Int>, n:Int):Array<Int> {
		var out = [for (_ in 0...n) 0];
		if (n == 0) return out;
		out[n - 1] = 1;
		var i = n - 2;
		while (i >= 0) {
			out[i] = out[i + 1] * dims[i + 1];
			i--;
		}
		return out;
	}

	static function fail(msg:String):BroadcastPlan {
		return {
			outShape: [],
			outStrides: [],
			aStrides: [],
			bStrides: [],
			ok: false,
			error: msg
		};
	}
}
