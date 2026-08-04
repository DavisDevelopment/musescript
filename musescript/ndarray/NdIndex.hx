package musescript.ndarray;

/**
 * Fancy / advanced indexing helpers for NdArrayF64 (numpy-feel subset).
 *
 * Ops:
 *   - `normalizeIndex` / `normalizeSlice` — shared bounds math
 *   - `take` / `takeNd` — `np.take` (axis or flatten); always a **copy**
 *   - `gather` — `take(..., axis=0)` convenience (ML-style)
 *   - `takeAlong` — `np.take_along_axis`; always a **copy**
 *   - Stepped slices live on `NdArrayF64.sliceAxis` (views when stride math works)
 *
 * Numpy-like:
 *   - Negative indices wrap (`-1` → last) then must land in-range (raise → null here)
 *   - `take` with `axis=null` flattens logical C-order first
 *   - Bool masks stay on `NdUfuncs.compress` / `assignWhere` — do **not** pass Bool
 *     arrays to `take` (0/1 ints would be integer indexing, not compress)
 *
 * Subset / gaps vs full NumPy:
 *   - No `np.ix_`, no mixed basic+advanced tuples, no broadcast of several integer
 *     index arrays into one fancy index (`a[I, J]` for 2-D)
 *   - No `mode='wrap'|'clip'` — OOB → null (Np → empty)
 *   - Indices are `Array<Int>`, `NdArrayF64` (integer-valued), or `NdArrayI32`
 *     (`takeI32` / `takeAlongI32` — no F64 widen of the index array); Bool masks
 *     stay on compress, not `take`
 *   - Stepped slice is always a **view** (stride *= step); empty slice is a view of size 0
 */
typedef SliceNorm = {
	var start:Int;
	var step:Int;
	/** Number of selected elements along the axis. */
	var size:Int;
}

class NdIndex {
	/** Normalize one index with negative wrap. OOB → -1. */
	public static function normalizeIndex(i:Int, len:Int):Int {
		if (len <= 0) return -1;
		var ix = i < 0 ? i + len : i;
		if (ix < 0 || ix >= len) return -1;
		return ix;
	}

	/**
	 * NumPy-style slice.indices(len) for concrete ints (no None).
	 * `step == 0` → null. Empty range → size 0 (still valid).
	 */
	public static function normalizeSlice(start:Int, stop:Int, step:Int, len:Int):Null<SliceNorm> {
		if (step == 0) return null;
		if (len < 0) len = 0;
		var s = start;
		var e = stop;
		if (step > 0) {
			if (s < 0) {
				s += len;
				if (s < 0) s = 0;
			} else if (s > len) s = len;
			if (e < 0) {
				e += len;
				if (e < 0) e = 0;
			} else if (e > len) e = len;
			if (e <= s) return {start: s, step: step, size: 0};
			var size = Std.int((e - s + step - 1) / step);
			return {start: s, step: step, size: size};
		}
		// step < 0
		if (s < 0) {
			s += len;
			if (s < 0) s = -1;
		} else if (s >= len) s = len - 1;
		if (e < 0) {
			e += len;
			if (e < -1) e = -1;
		} else if (e >= len) e = len - 1;
		if (s <= e) return {start: s, step: step, size: 0};
		// count: s, s+step, ... while > e
		var size = 0;
		var cur = s;
		while (cur > e) {
			size++;
			cur += step;
		}
		return {start: s, step: step, size: size};
	}

	/**
	 * `np.take(a, indices, axis=None)`.
	 * `axis == null` → flatten then gather (result 1-D length = indices.length).
	 * Always materializes a contiguous copy. OOB index → null.
	 */
	public static function take(a:NdArrayF64, indices:Array<Int>, ?axis:Null<Int>):Null<NdArrayF64> {
		if (a == null || indices == null) return null;
		if (axis == null) return takeFlat(a, indices);
		var ndim = a.ndim;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		return takeAlongAxis1d(a, indices, ax);
	}

	/** Same as `take` but indices stored as F64 integer values. */
	public static function takeNd(a:NdArrayF64, indices:NdArrayF64, ?axis:Null<Int>):Null<NdArrayF64> {
		if (a == null || indices == null) return null;
		if (axis == null) {
			var flatIdx = unpackIndicesFlat(indices);
			if (flatIdx == null) return null;
			return takeFlat(a, flatIdx);
		}
		var ndim = a.ndim;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		// ND indices along axis: expand indices shape into out along `ax`
		return takeWithNdIndices(a, indices, ax);
	}

	/** `take` with `NdArrayI32` indices — no F64 widen of the index array. */
	public static function takeI32(a:NdArrayF64, indices:NdArrayI32, ?axis:Null<Int>):Null<NdArrayF64> {
		if (a == null || indices == null) return null;
		if (axis == null) {
			var flatIdx = unpackIndicesI32Flat(indices);
			if (flatIdx == null) return null;
			return takeFlat(a, flatIdx);
		}
		var ndim = a.ndim;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		return takeWithNdIndicesI32(a, indices, ax);
	}

	/** ML-style gather: take along axis 0. */
	public static inline function gather(a:NdArrayF64, indices:Array<Int>):Null<NdArrayF64>
		return take(a, indices, 0);

	public static inline function gatherNd(a:NdArrayF64, indices:NdArrayF64):Null<NdArrayF64>
		return takeNd(a, indices, 0);

	public static inline function gatherI32(a:NdArrayF64, indices:NdArrayI32):Null<NdArrayF64>
		return takeI32(a, indices, 0);

	/**
	 * `np.take_along_axis(a, indices, axis)`.
	 * Requires `a.ndim == indices.ndim` and shapes equal except at `axis`.
	 * Output shape = indices.shape. Always a copy. OOB → null.
	 */
	public static function takeAlong(a:NdArrayF64, indices:NdArrayF64, axis:Int):Null<NdArrayF64> {
		if (a == null || indices == null) return null;
		var ndim = a.ndim;
		if (indices.ndim != ndim) return null;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		var ash:Array<Int> = a.shape;
		var ish:Array<Int> = indices.shape;
		for (d in 0...ndim) {
			if (d == ax) continue;
			if (ash[d] != ish[d]) return null;
		}
		var out = NdArrayF64.empty(ish);
		var coords = [for (_ in 0...ndim) 0];
		var srcCoords = [for (_ in 0...ndim) 0];
		var n = out.size;
		for (flat in 0...n) {
			decodeFlat(flat, ish, coords);
			for (d in 0...ndim) srcCoords[d] = coords[d];
			var raw = Std.int(indices.getAt(coords));
			var ix = normalizeIndex(raw, ash[ax]);
			if (ix < 0) return null;
			srcCoords[ax] = ix;
			out.setFlat(flat, a.getAt(srcCoords));
		}
		return out;
	}

	/** `take_along_axis` with I32 index array (no F64 widen). */
	public static function takeAlongI32(a:NdArrayF64, indices:NdArrayI32, axis:Int):Null<NdArrayF64> {
		if (a == null || indices == null) return null;
		var ndim = a.ndim;
		if (indices.ndim != ndim) return null;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		var ash:Array<Int> = a.shape;
		var ish:Array<Int> = indices.shape;
		for (d in 0...ndim) {
			if (d == ax) continue;
			if (ash[d] != ish[d]) return null;
		}
		var out = NdArrayF64.empty(ish);
		var coords = [for (_ in 0...ndim) 0];
		var srcCoords = [for (_ in 0...ndim) 0];
		var n = out.size;
		for (flat in 0...n) {
			decodeFlat(flat, ish, coords);
			for (d in 0...ndim) srcCoords[d] = coords[d];
			var ix = normalizeIndex(indices.getAt(coords), ash[ax]);
			if (ix < 0) return null;
			srcCoords[ax] = ix;
			out.setFlat(flat, a.getAt(srcCoords));
		}
		return out;
	}

	// --- internals -----------------------------------------------------------

	static function takeFlat(a:NdArrayF64, indices:Array<Int>):Null<NdArrayF64> {
		var n = a.size;
		var out = NdArrayF64.empty([indices.length]);
		for (i in 0...indices.length) {
			var ix = normalizeIndex(indices[i], n);
			if (ix < 0) return null;
			out.setFlat(i, a.getFlat(ix));
		}
		return out;
	}

	/** 1-D index list replaces `axis`. */
	static function takeAlongAxis1d(a:NdArrayF64, indices:Array<Int>, ax:Int):Null<NdArrayF64> {
		var ash:Array<Int> = a.shape;
		var ndim = ash.length;
		var m = indices.length;
		var outShape:Array<Int> = [];
		for (d in 0...ndim) {
			if (d == ax) outShape.push(m);
			else outShape.push(ash[d]);
		}
		var out = NdArrayF64.empty(outShape);
		var coords = [for (_ in 0...ndim) 0];
		var srcCoords = [for (_ in 0...ndim) 0];
		var nOut = out.size;
		for (flat in 0...nOut) {
			decodeFlat(flat, outShape, coords);
			for (d in 0...ndim) srcCoords[d] = coords[d];
			var raw = indices[coords[ax]];
			var ix = normalizeIndex(raw, ash[ax]);
			if (ix < 0) return null;
			srcCoords[ax] = ix;
			out.setFlat(flat, a.getAt(srcCoords));
		}
		return out;
	}

	static function unpackIndicesFlat(indices:NdArrayF64):Null<Array<Int>> {
		var out:Array<Int> = [];
		for (i in 0...indices.size) {
			var v = indices.getFlat(i);
			if (v != v) return null; // NaN
			out.push(Std.int(v));
		}
		return out;
	}

	static function unpackIndicesI32Flat(indices:NdArrayI32):Null<Array<Int>> {
		var out:Array<Int> = [];
		for (i in 0...indices.size) out.push(indices.getFlat(i));
		return out;
	}

	/**
	 * Integer-array indexing along one axis where the index array may be ND.
	 * Out shape = ash[:ax] + indices.shape + ash[ax+1:] (numpy `take` with ND indices).
	 */
	static function takeWithNdIndices(a:NdArrayF64, indices:NdArrayF64, ax:Int):Null<NdArrayF64> {
		var ash:Array<Int> = a.shape;
		var ish:Array<Int> = indices.shape;
		var ndim = ash.length;
		var indNdim = ish.length;
		var outShape:Array<Int> = [];
		for (d in 0...ax) outShape.push(ash[d]);
		for (d in 0...indNdim) outShape.push(ish[d]);
		for (d in (ax + 1)...ndim) outShape.push(ash[d]);
		var out = NdArrayF64.empty(outShape);
		var outNdim = outShape.length;
		var coords = [for (_ in 0...outNdim) 0];
		var srcCoords = [for (_ in 0...ndim) 0];
		var indCoords = [for (_ in 0...indNdim) 0];
		var prefix = ax;
		var nOut = out.size;
		for (flat in 0...nOut) {
			decodeFlat(flat, outShape, coords);
			for (d in 0...prefix) srcCoords[d] = coords[d];
			for (d in 0...indNdim) indCoords[d] = coords[prefix + d];
			for (d in (ax + 1)...ndim)
				srcCoords[d] = coords[prefix + indNdim + (d - ax - 1)];
			var raw = Std.int(indices.getAt(indCoords));
			var ix = normalizeIndex(raw, ash[ax]);
			if (ix < 0) return null;
			srcCoords[ax] = ix;
			out.setFlat(flat, a.getAt(srcCoords));
		}
		return out;
	}

	static function takeWithNdIndicesI32(a:NdArrayF64, indices:NdArrayI32, ax:Int):Null<NdArrayF64> {
		var ash:Array<Int> = a.shape;
		var ish:Array<Int> = indices.shape;
		var ndim = ash.length;
		var indNdim = ish.length;
		var outShape:Array<Int> = [];
		for (d in 0...ax) outShape.push(ash[d]);
		for (d in 0...indNdim) outShape.push(ish[d]);
		for (d in (ax + 1)...ndim) outShape.push(ash[d]);
		var out = NdArrayF64.empty(outShape);
		var outNdim = outShape.length;
		var coords = [for (_ in 0...outNdim) 0];
		var srcCoords = [for (_ in 0...ndim) 0];
		var indCoords = [for (_ in 0...indNdim) 0];
		var prefix = ax;
		var nOut = out.size;
		for (flat in 0...nOut) {
			decodeFlat(flat, outShape, coords);
			for (d in 0...prefix) srcCoords[d] = coords[d];
			for (d in 0...indNdim) indCoords[d] = coords[prefix + d];
			for (d in (ax + 1)...ndim)
				srcCoords[d] = coords[prefix + indNdim + (d - ax - 1)];
			var ix = normalizeIndex(indices.getAt(indCoords), ash[ax]);
			if (ix < 0) return null;
			srcCoords[ax] = ix;
			out.setFlat(flat, a.getAt(srcCoords));
		}
		return out;
	}

	public static function decodeFlat(flat:Int, shape:Array<Int>, coords:Array<Int>):Void {
		var rem = flat;
		var cStr = (shape : Shape).cStrides();
		for (ax in 0...shape.length) {
			var s = cStr[ax];
			if (s == 0) {
				coords[ax] = 0;
			} else {
				coords[ax] = Std.int(rem / s);
				rem = rem % s;
			}
		}
	}
}
