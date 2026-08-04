package musescript.ndarray;

/**
 * Float32 ndarray — concrete storage (M2.5).
 *
 * Buffer policy (RingBuffer doctrine):
 *   - JS: `Float32Array`
 *   - else: `haxe.ds.Vector<Float>` with `NdCast.truncF32` on every write
 *
 * Public API has **no Dynamic**. Default Muse/fitness path remains `NdArrayF64`;
 * obtain F32 only via explicit `astype("float32")` / `Np.zerosF32` / etc.
 */
class NdArrayF32 implements INdArrayCore<Float> {
	#if js
	var data:js.lib.Float32Array;
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

	public inline function dtype():String return NdDType.F32;
	public inline function isCContiguous():Bool return _cContig;

	public inline function getBuf(phys:Int):Float return data[phys];
	public inline function setBuf(phys:Int, v:Float):Void data[phys] = NdCast.truncF32(v);

	public function getFlat(i:Int):Float {
		if (_cContig) return data[_offset + i];
		return data[logicalToPhys(i)];
	}

	public function setFlat(i:Int, v:Float):Void {
		var t = NdCast.truncF32(v);
		if (_cContig) data[_offset + i] = t;
		else data[logicalToPhys(i)] = t;
	}

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
		data[flat] = NdCast.truncF32(v);
		return true;
	}

	public function get2(row:Int, col:Int):Float {
		if (_shape.length != 2) return Math.NaN;
		return getAt([row, col]);
	}

	public function copy():NdArrayF32 {
		var out = empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i));
		return out;
	}

	public function reshape(newShape:Array<Int>):Null<NdArrayF32> {
		var sh:Shape = newShape == null ? [] : newShape;
		if (sh.size() != _size) return null;
		if (_cContig) return wrapView(data, sh, sh.cStrides(), _offset, _ownData);
		var c = copy();
		return wrapView(c.data, sh, sh.cStrides(), 0, true);
	}

	public function slice1d(start:Int, stop:Int):Null<NdArrayF32>
		return sliceAxis(0, start, stop);

	public function sliceAxis(axis:Int, start:Int, stop:Int):Null<NdArrayF32> {
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

	public function transpose(?axes:Array<Int>):Null<NdArrayF32> {
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

	public function swapaxes(i:Int, j:Int):Null<NdArrayF32> {
		var ndim = _shape.length;
		var a = i < 0 ? i + ndim : i;
		var b = j < 0 ? j + ndim : j;
		if (a < 0 || a >= ndim || b < 0 || b >= ndim) return null;
		var perm = [for (k in 0...ndim) k];
		perm[a] = b;
		perm[b] = a;
		return transpose(perm);
	}

	public function toArray():Array<Float>
		return [for (i in 0..._size) getFlat(i)];

	public function toF64():NdArrayF64 {
		var out = NdArrayF64.empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i));
		return out;
	}

	public function toI32():NdArrayI32 {
		var out = NdArrayI32.empty(_shape);
		for (i in 0..._size) out.setFlat(i, NdCast.toI32(getFlat(i)));
		return out;
	}

	public function toBool():NdArrayBool {
		var out = NdArrayBool.empty(_shape);
		for (i in 0..._size) out.setFlat(i, NdCast.truthyFloat(getFlat(i)));
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

	public static function empty(shape:Array<Int>):NdArrayF32 {
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

	public static function zeros(shape:Array<Int>):NdArrayF32 {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, 0);
		return a;
	}

	public static function ones(shape:Array<Int>):NdArrayF32 {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, 1);
		return a;
	}

	public static function full(shape:Array<Int>, value:Float):NdArrayF32 {
		var a = empty(shape);
		var t = NdCast.truncF32(value);
		for (i in 0...a.size) a.setFlat(i, t);
		return a;
	}

	public static function fromPacked(shape:Array<Int>, data:Array<Float>):Null<NdArrayF32> {
		if (data == null) return null;
		var sh:Shape = shape == null ? [data.length] : shape;
		if (sh.size() != data.length) return null;
		var a = empty(sh);
		for (i in 0...data.length) a.setFlat(i, data[i]);
		return a;
	}

	public static function asarray1d(data:Array<Float>):NdArrayF32 {
		if (data == null) return empty([0]);
		return fromPacked([data.length], data);
	}

	public static function fromF64(a:NdArrayF64):NdArrayF32 {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, a.getFlat(i));
		return out;
	}

	public static function fromI32(a:NdArrayI32):NdArrayF32 {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, a.getFlat(i));
		return out;
	}

	public static function fromBool(a:NdArrayBool):NdArrayF32 {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, a.getFlat(i) ? 1.0 : 0.0);
		return out;
	}

	#if js
	public static function wrapView(
		buf:js.lib.Float32Array,
		shape:Array<Int>,
		strides:Array<Int>,
		offset:Int,
		own:Bool
	):NdArrayF32 {
	#else
	public static function wrapView(
		buf:haxe.ds.Vector<Float>,
		shape:Array<Int>,
		strides:Array<Int>,
		offset:Int,
		own:Bool
	):NdArrayF32 {
	#end
		var sh:Shape = shape;
		var a = new NdArrayF32();
		a.data = buf;
		a._shape = sh.copy();
		a._strides = strides.copy();
		a._offset = offset;
		a._size = sh.size();
		a._ownData = own;
		a.refreshFlags();
		return a;
	}

	static function alloc(n:Int):NdArrayF32 {
		var a = new NdArrayF32();
		var cap = n < 0 ? 0 : n;
		#if js
		a.data = new js.lib.Float32Array(cap);
		#else
		a.data = new haxe.ds.Vector<Float>(cap);
		#end
		return a;
	}
}
