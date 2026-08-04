package musescript.ndarray;

/**
 * Int32 ndarray — concrete storage (M2.5).
 *
 * Buffer policy:
 *   - JS: `Int32Array`
 *   - else: `haxe.ds.Vector<Int>`
 *
 * Writes from Float go through `NdCast.toI32` (toward-0 + clamp).
 * No Dynamic on the public API. Default Muse arrays stay F64.
 */
class NdArrayI32 implements INdArrayCore<Int> {
	#if js
	var data:js.lib.Int32Array;
	#else
	var data:haxe.ds.Vector<Int>;
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
	public function copyF64():NdArrayF64 return toF64();
	public function reshapeF64(newShape:Array<Int>):Null<NdArrayF64> {
		var r = reshape(newShape);
		return r == null ? null : r.toF64();
	}

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

	public inline function dtype():String return NdDType.I32;
	public inline function isCContiguous():Bool return _cContig;

	public inline function getBuf(phys:Int):Int return data[phys];
	public inline function setBuf(phys:Int, v:Int):Void data[phys] = v;

	public function getFlat(i:Int):Int {
		if (_cContig) return data[_offset + i];
		return data[logicalToPhys(i)];
	}

	public function setFlat(i:Int, v:Int):Void {
		if (_cContig) data[_offset + i] = v;
		else data[logicalToPhys(i)] = v;
	}

	public function getAt(indices:Array<Int>):Int {
		if (indices == null || indices.length != _shape.length) return 0;
		var flat = _offset;
		for (ax in 0...indices.length) {
			var ix = indices[ax];
			if (ix < 0 || ix >= _shape[ax]) return 0;
			flat += ix * _strides[ax];
		}
		return data[flat];
	}

	public function setAt(indices:Array<Int>, v:Int):Bool {
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

	public function get2(row:Int, col:Int):Int {
		if (_shape.length != 2) return 0;
		return getAt([row, col]);
	}

	public function copy():NdArrayI32 {
		var out = empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i));
		return out;
	}

	public function reshape(newShape:Array<Int>):Null<NdArrayI32> {
		var sh:Shape = newShape == null ? [] : newShape;
		if (sh.size() != _size) return null;
		if (_cContig) return wrapView(data, sh, sh.cStrides(), _offset, _ownData);
		var c = copy();
		return wrapView(c.data, sh, sh.cStrides(), 0, true);
	}

	public function slice1d(start:Int, stop:Int):Null<NdArrayI32>
		return sliceAxis(0, start, stop);

	public function sliceAxis(axis:Int, start:Int, stop:Int):Null<NdArrayI32> {
		var ndim = _shape.length;
		if (ndim == 0) return null;
		var ax = axis < 0 ? axis + ndim : axis;
		if (ax < 0 || ax >= ndim) return null;
		var n = _shape[ax];
		var s = start < 0 ? 0 : start;
		var e = stop > n ? n : stop;
		if (e < s) e = s;
		var newShape = _shape.copy();
		newShape[ax] = e - s;
		var newStrides = _strides.copy();
		var newOff = _offset + s * _strides[ax];
		return wrapView(data, newShape, newStrides, newOff, false);
	}

	public function transpose(?axes:Array<Int>):Null<NdArrayI32> {
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

	public function swapaxes(i:Int, j:Int):Null<NdArrayI32> {
		var ndim = _shape.length;
		var a = i < 0 ? i + ndim : i;
		var b = j < 0 ? j + ndim : j;
		if (a < 0 || a >= ndim || b < 0 || b >= ndim) return null;
		var perm = [for (k in 0...ndim) k];
		perm[a] = b;
		perm[b] = a;
		return transpose(perm);
	}

	public function toArray():Array<Int>
		return [for (i in 0..._size) getFlat(i)];

	public function toF64():NdArrayF64 {
		var out = NdArrayF64.empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i));
		return out;
	}

	public function toF32():NdArrayF32 {
		var out = NdArrayF32.empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i));
		return out;
	}

	public function toBool():NdArrayBool {
		var out = NdArrayBool.empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i) != 0);
		return out;
	}

	function logicalToPhys(i:Int):Int {
		var rem = i;
		var phys = _offset;
		var cStr = (_shape : Shape).cStrides();
		for (ax in 0..._shape.length) {
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
			if (_shape[i] <= 1) continue;
			if (exp[i] != _strides[i]) {
				_cContig = false;
				return;
			}
		}
		_cContig = true;
	}

	public static function empty(shape:Array<Int>):NdArrayI32 {
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

	public static function zeros(shape:Array<Int>):NdArrayI32 {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, 0);
		return a;
	}

	public static function ones(shape:Array<Int>):NdArrayI32 {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, 1);
		return a;
	}

	public static function full(shape:Array<Int>, value:Int):NdArrayI32 {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, value);
		return a;
	}

	public static function arange(startOrStop:Int, ?stop:Int, ?step:Int):NdArrayI32 {
		var start:Int;
		var end:Int;
		var st:Int;
		if (stop == null) {
			start = 0;
			end = startOrStop;
			st = 1;
		} else {
			start = startOrStop;
			end = stop;
			st = step == null ? 1 : step;
		}
		if (st == 0) return empty([0]);
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

	public static function fromPacked(shape:Array<Int>, data:Array<Int>):Null<NdArrayI32> {
		if (data == null) return null;
		var sh:Shape = shape == null ? [data.length] : shape;
		if (sh.size() != data.length) return null;
		var a = empty(sh);
		for (i in 0...data.length) a.setFlat(i, data[i]);
		return a;
	}

	public static function asarray1d(data:Array<Int>):NdArrayI32 {
		if (data == null) return empty([0]);
		return fromPacked([data.length], data);
	}

	public static function fromF64(a:NdArrayF64):NdArrayI32 {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, NdCast.toI32(a.getFlat(i)));
		return out;
	}

	public static function fromF32(a:NdArrayF32):NdArrayI32 {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, NdCast.toI32(a.getFlat(i)));
		return out;
	}

	public static function fromBool(a:NdArrayBool):NdArrayI32 {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, a.getFlat(i) ? 1 : 0);
		return out;
	}

	#if js
	public static function wrapView(
		buf:js.lib.Int32Array,
		shape:Array<Int>,
		strides:Array<Int>,
		offset:Int,
		own:Bool
	):NdArrayI32 {
	#else
	public static function wrapView(
		buf:haxe.ds.Vector<Int>,
		shape:Array<Int>,
		strides:Array<Int>,
		offset:Int,
		own:Bool
	):NdArrayI32 {
	#end
		var sh:Shape = shape;
		var a = new NdArrayI32();
		a.data = buf;
		a._shape = sh.copy();
		a._strides = strides.copy();
		a._offset = offset;
		a._size = sh.size();
		a._ownData = own;
		a.refreshFlags();
		return a;
	}

	static function alloc(n:Int):NdArrayI32 {
		var a = new NdArrayI32();
		var cap = n < 0 ? 0 : n;
		#if js
		a.data = new js.lib.Int32Array(cap);
		#else
		a.data = new haxe.ds.Vector<Int>(cap);
		#end
		return a;
	}
}
