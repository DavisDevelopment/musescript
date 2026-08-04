package musescript.ndarray;

/**
 * Float64 ndarray with real strides / views (M2).
 *
 * Buffer policy matches `GrowableVec` / RingBuffer doctrine:
 *   - JS: `Float64Array`
 *   - else: `haxe.ds.Vector<Float>` → `double[]` on JVM
 *
 * INDEXING:
 *   - `getFlat(i)` / `setFlat(i, v)` — **logical** C-order element `i` in `0...size`
 *     (honors strides; matches NumPy `a.flat[i]`).
 *   - `getBuf(phys)` / `setBuf` — raw buffer index (includes offset).
 *   - `getAt(indices)` — multi-index; `indices.length` must equal `ndim`.
 *   - `transpose` / `slice*` / `swapaxes` prefer **views** sharing storage.
 *   - Integer array gather / `take` — see `NdIndex` (always copies).
 *   - Bool masks — `NdUfuncs.compress` / `assignWhere` (not via take).
 *
 * Public API intentionally has **no Dynamic**. Muse boxing converts at
 * `NpBuiltins` only.
 */
class NdArrayF64 implements INdArrayCore<Float> {
	#if js
	var data:js.lib.Float64Array;
	#else
	var data:haxe.ds.Vector<Float>;
	#end
	var _shape:Array<Int>;
	var _strides:Array<Int>;
	var _offset:Int;
	var _size:Int;
	var _ownData:Bool;
	var _cContig:Bool;

	function new() {}

	public function getShape():Shape return _shape;
	public function getNdim():Int return _shape.length;
	public function getSize():Int return _size;
	public function copyF64():NdArrayF64 return copy();
	public function reshapeF64(newShape:Array<Int>):Null<NdArrayF64> return reshape(newShape);

	public var shape(get, never):Shape;
	inline function get_shape():Shape return _shape;

	public var strides(get, never):Array<Int>;
	inline function get_strides():Array<Int> return _strides;

	public var ndim(get, never):Int;
	inline function get_ndim():Int return _shape.length;

	public var size(get, never):Int;
	inline function get_size():Int return _size;

	public var offset(get, never):Int;
	inline function get_offset():Int return _offset;

	/** NumPy-style `flags.c_contiguous` (offset may be nonzero). */
	public inline function isCContiguous():Bool return _cContig;

	public inline function getBuf(phys:Int):Float return data[phys];
	public inline function setBuf(phys:Int, v:Float):Void data[phys] = v;

	/** Logical C-order get. */
	public function getFlat(i:Int):Float {
		if (_cContig) return data[_offset + i];
		return data[logicalToPhys(i)];
	}

	public function setFlat(i:Int, v:Float):Void {
		if (_cContig) data[_offset + i] = v;
		else data[logicalToPhys(i)] = v;
	}

	/** Multi-index get. Wrong arity / OOB → NaN. */
	public function getAt(indices:Array<Int>):Float {
		if (indices == null || indices.length != _shape.length) return Math.NaN;
		var flat = _offset;
		for (ax in 0...indices.length) {
			var ix = indices[ax];
			if (ix < 0 || ix >= _shape[ax]) return Math.NaN;
			flat += ix * _strides[ax];
		}
		return data[flat];
	}

	public function setAt(indices:Array<Int>, v:Float):Bool {
		if (indices == null || indices.length != _shape.length) return false;
		var flat = _offset;
		for (ax in 0...indices.length) {
			var ix = indices[ax];
			if (ix < 0 || ix >= _shape[ax]) return false;
			flat += ix * _strides[ax];
		}
		data[flat] = v;
		return true;
	}

	/** Physical buffer index for multi-index (no bounds check). */
	public inline function physAt(indices:Array<Int>):Int {
		var flat = _offset;
		for (ax in 0...indices.length) flat += indices[ax] * _strides[ax];
		return flat;
	}

	/** Convenience 2-D get (row, col). Non-2-D / OOB → NaN. */
	public function get2(row:Int, col:Int):Float {
		if (_shape.length != 2) return Math.NaN;
		return getAt([row, col]);
	}

	public function copy():NdArrayF64 {
		var out = empty(_shape);
		if (_cContig) {
			for (i in 0..._size) out.setFlat(i, getFlat(i));
		} else {
			copyIntoContiguous(out);
		}
		return out;
	}

	/**
	 * Reshape. Same `size` required. Shares buffer when this is C-contiguous;
	 * otherwise materializes a contiguous copy.
	 */
	public function reshape(newShape:Array<Int>):Null<NdArrayF64> {
		var sh:Shape = newShape == null ? [] : newShape;
		if (sh.size() != _size) return null;
		if (_cContig) {
			return wrapView(data, sh, sh.cStrides(), _offset, _ownData);
		}
		var c = copy();
		return wrapView(c.data, sh, sh.cStrides(), 0, true);
	}

	/** Half-open 1-D slice `[start, stop)` with optional `step` — always a view. */
	public function slice1d(start:Int, stop:Int, ?step:Int = 1):Null<NdArrayF64> {
		return sliceAxis(0, start, stop, step);
	}

	/**
	 * Slice along `axis` with half-open `[start, stop)` and `step` (default 1).
	 * Always a **view**: `stride[axis] *= step`, `offset += start * stride`.
	 * Negative `start`/`stop`/`step` follow NumPy `slice.indices` via `NdIndex.normalizeSlice`.
	 * `step == 0` → null. Empty selection → size-0 view (shares buffer).
	 */
	public function sliceAxis(axis:Int, start:Int, stop:Int, ?step:Int = 1):Null<NdArrayF64> {
		var ndim = _shape.length;
		if (ndim == 0) return null;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		var n = _shape[ax];
		var st = step == null ? 1 : step;
		var norm = NdIndex.normalizeSlice(start, stop, st, n);
		if (norm == null) return null;
		var newShape = _shape.copy();
		newShape[ax] = norm.size;
		var newStrides = _strides.copy();
		newStrides[ax] = _strides[ax] * norm.step;
		var newOff = _offset + norm.start * _strides[ax];
		return wrapView(data, newShape, newStrides, newOff, false);
	}

	/** Transpose — view by permuting strides. Default reverses all axes. */
	public function transpose(?axes:Array<Int>):Null<NdArrayF64> {
		var ndim = _shape.length;
		if (ndim == 0) return wrapView(data, [], [], _offset, false);
		if (ndim == 1) return wrapView(data, _shape.copy(), _strides.copy(), _offset, false);
		var perm:Array<Int>;
		if (axes == null) {
			perm = [for (i in 0...ndim) ndim - 1 - i];
		} else {
			if (axes.length != ndim) return null;
			var seen = [for (_ in 0...ndim) false];
			perm = [];
			for (a in axes) {
				var ax = a < 0 ? a + ndim : a;
				if (ax < 0 || ax >= ndim || seen[ax]) return null;
				seen[ax] = true;
				perm.push(ax);
			}
		}
		var newShape:Array<Int> = [];
		var newStrides:Array<Int> = [];
		for (p in perm) {
			newShape.push(_shape[p]);
			newStrides.push(_strides[p]);
		}
		return wrapView(data, newShape, newStrides, _offset, false);
	}

	public function swapaxes(i:Int, j:Int):Null<NdArrayF64> {
		var ndim = _shape.length;
		var a = i < 0 ? i + ndim : i;
		var b = j < 0 ? j + ndim : j;
		if (a < 0 || a >= ndim || b < 0 || b >= ndim) return null;
		var perm = [for (k in 0...ndim) k];
		perm[a] = b;
		perm[b] = a;
		return transpose(perm);
	}

	/** Materialize packed C-order values as `Array<Float>` (interop / ml_matrix). */
	public function toArray():Array<Float> {
		var out:Array<Float> = [];
		for (i in 0..._size) out.push(getFlat(i));
		return out;
	}

	public function toF32():NdArrayF32 return NdArrayF32.fromF64(this);
	public function toI32():NdArrayI32 return NdArrayI32.fromF64(this);
	public function toBoolMask():NdArrayBool return NdArrayBool.fromF64(this);

	function copyIntoContiguous(out:NdArrayF64):Void {
		if (_size == 0) return;
		var coords = [for (_ in 0..._shape.length) 0];
		for (flat in 0..._size) {
			out.setFlat(flat, getAt(coords));
			incCoords(coords, _shape);
		}
	}

	public static function incCoords(coords:Array<Int>, shape:Array<Int>):Void {
		var ax = coords.length - 1;
		while (ax >= 0) {
			coords[ax]++;
			if (coords[ax] < shape[ax]) return;
			coords[ax] = 0;
			ax--;
		}
	}

	function logicalToPhys(i:Int):Int {
		var rem = i;
		var phys = _offset;
		var n = _shape.length;
		// decode using C-order shape strides, apply real strides
		var cStr = (_shape : Shape).cStrides();
		for (ax in 0...n) {
			var idx = cStr[ax] == 0 ? 0 : Std.int(rem / cStr[ax]);
			rem = cStr[ax] == 0 ? rem : rem % cStr[ax];
			phys += idx * _strides[ax];
		}
		return phys;
	}

	function refreshFlags():Void {
		if (_size <= 1) {
			_cContig = true;
			return;
		}
		var exp = (_shape : Shape).cStrides();
		if (exp.length != _strides.length) {
			_cContig = false;
			return;
		}
		for (i in 0...exp.length) {
			if (_shape[i] <= 1) continue; // stride on size-1 axis unconstrained
			if (exp[i] != _strides[i]) {
				_cContig = false;
				return;
			}
		}
		_cContig = true;
	}

	// --- factories -----------------------------------------------------------

	public static function empty(shape:Array<Int>):NdArrayF64 {
		var sh:Shape = shape == null ? [] : shape;
		var n = sh.size();
		var a = alloc(n);
		a._shape = sh.copy();
		a._strides = sh.cStrides();
		a._offset = 0;
		a._size = n;
		a._ownData = true;
		a._cContig = true;
		return a;
	}

	public static function zeros(shape:Array<Int>):NdArrayF64 {
		var a = empty(shape);
		NdAccel.active().fill(a, 0.0);
		return a;
	}

	public static function ones(shape:Array<Int>):NdArrayF64 {
		var a = empty(shape);
		NdAccel.active().fill(a, 1.0);
		return a;
	}

	public static function full(shape:Array<Int>, value:Float):NdArrayF64 {
		var a = empty(shape);
		NdAccel.active().fill(a, value);
		return a;
	}

	/**
	 * `arange` — NumPy-compatible overloads via optional stop/step.
	 *   arange(stop) | arange(start, stop) | arange(start, stop, step)
	 * Empty / bad step → size-0 array.
	 */
	public static function arange(startOrStop:Float, ?stop:Float, ?step:Float):NdArrayF64 {
		var start:Float;
		var end:Float;
		var st:Float;
		if (stop == null) {
			start = 0;
			end = startOrStop;
			st = 1;
		} else {
			start = startOrStop;
			end = stop;
			st = step == null ? 1.0 : step;
		}
		if (st == 0 || !Math.isFinite(start) || !Math.isFinite(end) || !Math.isFinite(st))
			return empty([0]);
		var n = 0;
		if (st > 0) {
			var x = start;
			while (x < end) {
				n++;
				x += st;
			}
		} else {
			var x = start;
			while (x > end) {
				n++;
				x += st;
			}
		}
		var a = empty([n]);
		var v = start;
		for (i in 0...n) {
			a.setFlat(i, v);
			v += st;
		}
		return a;
	}

	/** Pack flat `data` into `shape` (copy). Length must match `shape.size()`. */
	public static function fromPacked(shape:Array<Int>, data:Array<Float>):Null<NdArrayF64> {
		if (data == null) return null;
		var sh:Shape = shape == null ? [data.length] : shape;
		if (sh.size() != data.length) return null;
		var a = empty(sh);
		for (i in 0...data.length) a.setFlat(i, data[i]);
		return a;
	}

	/** 1-D from flat floats. */
	public static function asarray1d(data:Array<Float>):NdArrayF64 {
		if (data == null) return empty([0]);
		return fromPacked([data.length], data);
	}

	/** 2-D from row lists; ragged → null. */
	public static function asarray2d(rows:Array<Array<Float>>):Null<NdArrayF64> {
		if (rows == null || rows.length == 0) return empty([0, 0]);
		var cols = rows[0] == null ? 0 : rows[0].length;
		var flat:Array<Float> = [];
		for (r in 0...rows.length) {
			var row = rows[r];
			if (row == null || row.length != cols) return null;
			for (c in 0...cols) flat.push(row[c]);
		}
		return fromPacked([rows.length, cols], flat);
	}

	public static function linspace(start:Float, stop:Float, ?num:Int = 50, ?endpoint:Bool = true):NdArrayF64 {
		var n = num == null || num < 0 ? 0 : num;
		if (n == 0) return empty([0]);
		if (n == 1) return full([1], start);
		var a = empty([n]);
		var div = endpoint ? (n - 1) : n;
		var step = (stop - start) / div;
		for (i in 0...n) a.setFlat(i, start + step * i);
		if (endpoint) a.setFlat(n - 1, stop);
		return a;
	}

	public static function ravel(a:NdArrayF64):NdArrayF64 {
		if (a == null) return empty([0]);
		if (a.isCContiguous()) return a.reshape([a.size]);
		return a.copy().reshape([a.size]);
	}

	public static function expandDims(a:NdArrayF64, axis:Int):Null<NdArrayF64> {
		if (a == null) return null;
		var sh:Array<Int> = a.shape;
		var ndim = sh.length;
		var ax = axis < 0 ? axis + ndim + 1 : axis;
		if (ax < 0 || ax > ndim) return null;
		var out:Array<Int> = [];
		var outStr:Array<Int> = [];
		var srcStr:Array<Int> = a.strides;
		for (i in 0...ax) {
			out.push(sh[i]);
			outStr.push(srcStr[i]);
		}
		out.push(1);
		outStr.push(ax < ndim ? srcStr[ax] : 1); // dummy stride for size-1
		for (i in ax...ndim) {
			out.push(sh[i]);
			outStr.push(srcStr[i]);
		}
		return wrapView(a.data, out, outStr, a.offset, false);
	}

	public static function squeeze(a:NdArrayF64, ?axis:Int):NdArrayF64 {
		if (a == null) return empty([0]);
		var sh:Array<Int> = a.shape;
		var srcStr:Array<Int> = a.strides;
		var out:Array<Int> = [];
		var outStr:Array<Int> = [];
		if (axis == null) {
			for (i in 0...sh.length) {
				if (sh[i] != 1) {
					out.push(sh[i]);
					outStr.push(srcStr[i]);
				}
			}
		} else {
			var ax = axis < 0 ? axis + sh.length : axis;
			if (ax < 0 || ax >= sh.length) return a.copy();
			if (sh[ax] != 1) return a.copy();
			for (i in 0...sh.length) {
				if (i == ax) continue;
				out.push(sh[i]);
				outStr.push(srcStr[i]);
			}
		}
		return wrapView(a.data, out, outStr, a.offset, false);
	}

	/** Broadcast `a` to `shape` (materializes contiguous copy). Fails → null. */
	public static function broadcastTo(a:NdArrayF64, shape:Array<Int>):Null<NdArrayF64> {
		if (a == null) return null;
		var target:Shape = shape;
		var p2 = Broadcast.plan(a.shape, shape);
		if (!p2.ok || !p2.outShape.equals(target)) return null;
		var out = empty(shape);
		var plan = Broadcast.planFrom(a, null, shape);
		if (!plan.ok) return null;
		var n = out.size;
		var ndim = target.ndim;
		var outStrides = target.cStrides();
		for (flat in 0...n) {
			var rem = flat;
			var aOff = a.offset;
			for (ax in 0...ndim) {
				var idx = outStrides[ax] == 0 ? 0 : Std.int(rem / outStrides[ax]);
				rem = outStrides[ax] == 0 ? rem : rem % outStrides[ax];
				aOff += idx * plan.aStrides[ax];
			}
			out.setFlat(flat, a.getBuf(aOff));
		}
		return out;
	}

	/** Concatenate along axis (default 0). Copies. */
	public static function concatenate(arrays:Array<NdArrayF64>, ?axis:Int = 0):Null<NdArrayF64> {
		if (arrays == null || arrays.length == 0) return empty([0]);
		var ndim = arrays[0].ndim;
		var ax = axis < 0 ? ndim + axis : axis;
		if (ax < 0 || ax >= ndim) return null;
		var outDims:Array<Int> = (arrays[0].shape : Array<Int>).copy();
		for (i in 1...arrays.length) {
			var sh:Array<Int> = arrays[i].shape;
			if (sh.length != ndim) return null;
			for (d in 0...ndim) {
				if (d == ax) outDims[d] += sh[d];
				else if (sh[d] != outDims[d]) return null;
			}
		}
		var out = empty(outDims);
		var offset = 0;
		for (arr in arrays) {
			var sh:Array<Int> = arr.shape;
			var len = sh[ax];
			var coords = [for (_ in 0...ndim) 0];
			function copyRec(dim:Int):Void {
				if (dim == ndim) {
					var dest = coords.copy();
					dest[ax] = coords[ax] + offset;
					out.setAt(dest, arr.getAt(coords));
					return;
				}
				for (i in 0...sh[dim]) {
					coords[dim] = i;
					copyRec(dim + 1);
				}
			}
			copyRec(0);
			offset += len;
		}
		return out;
	}

	public static function stack(arrays:Array<NdArrayF64>, ?axis:Int = 0):Null<NdArrayF64> {
		if (arrays == null || arrays.length == 0) return empty([0]);
		var base:Array<Int> = arrays[0].shape;
		for (a in arrays) {
			if (!(a.shape : Shape).equals(base)) return null;
		}
		var expanded:Array<NdArrayF64> = [];
		for (a in arrays) {
			var e = expandDims(a, axis);
			if (e == null) return null;
			expanded.push(e);
		}
		return concatenate(expanded, axis);
	}

	/**
	 * Alias an existing contiguous buffer as a 1-D (or shaped) view — zero-copy.
	 * Caller guarantees lifetime: buffer must outlive the view (GrowableVec grow invalidates).
	 */
	#if js
	public static function aliasBuffer(buf:js.lib.Float64Array, shape:Array<Int>, ?offset:Int = 0):NdArrayF64 {
	#else
	public static function aliasBuffer(buf:haxe.ds.Vector<Float>, shape:Array<Int>, ?offset:Int = 0):NdArrayF64 {
	#end
		var sh:Shape = shape == null ? [] : shape;
		return wrapView(buf, sh, sh.cStrides(), offset, false);
	}

	#if js
	public static function wrapView(
		buf:js.lib.Float64Array,
		shape:Array<Int>,
		strides:Array<Int>,
		offset:Int,
		own:Bool
	):NdArrayF64 {
	#else
	public static function wrapView(
		buf:haxe.ds.Vector<Float>,
		shape:Array<Int>,
		strides:Array<Int>,
		offset:Int,
		own:Bool
	):NdArrayF64 {
	#end
		var sh:Shape = shape;
		var a = new NdArrayF64();
		a.data = buf;
		a._shape = sh.copy();
		a._strides = strides.copy();
		a._offset = offset;
		a._size = sh.size();
		a._ownData = own;
		a.refreshFlags();
		return a;
	}

	static function alloc(n:Int):NdArrayF64 {
		var a = new NdArrayF64();
		var cap = n < 0 ? 0 : n;
		#if js
		a.data = new js.lib.Float64Array(cap);
		#else
		a.data = new haxe.ds.Vector<Float>(cap);
		#end
		return a;
	}
}
