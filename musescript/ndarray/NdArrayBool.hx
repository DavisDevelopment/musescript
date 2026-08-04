package musescript.ndarray;

/**
 * True boolean ndarray (M2) — masks / comparisons.
 *
 * Storage: JS `Uint8Array` (0/1); else `haxe.ds.Vector<Int>` (0/1).
 * No Dynamic. F64 0/1 masks remain reachable via `toF64()` for migration.
 */
class NdArrayBool {
	#if js
	var data:js.lib.Uint8Array;
	#else
	var data:haxe.ds.Vector<Int>;
	#end
	var _shape:Array<Int>;
	var _strides:Array<Int>;
	var _offset:Int;
	var _size:Int;
	var _cContig:Bool;

	function new() {}

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

	public inline function isCContiguous():Bool return _cContig;

	public inline function getBuf(phys:Int):Bool return data[phys] != 0;
	public inline function setBuf(phys:Int, v:Bool):Void data[phys] = v ? 1 : 0;

	public function getFlat(i:Int):Bool {
		if (_cContig) return data[_offset + i] != 0;
		return data[logicalToPhys(i)] != 0;
	}

	public function setFlat(i:Int, v:Bool):Void {
		if (_cContig) data[_offset + i] = v ? 1 : 0;
		else data[logicalToPhys(i)] = v ? 1 : 0;
	}

	public function getAt(indices:Array<Int>):Bool {
		if (indices == null || indices.length != _shape.length) return false;
		var flat = _offset;
		for (ax in 0...indices.length) {
			var ix = indices[ax];
			if (ix < 0 || ix >= _shape[ax]) return false;
			flat += ix * _strides[ax];
		}
		return data[flat] != 0;
	}

	public function setAt(indices:Array<Int>, v:Bool):Bool {
		if (indices == null || indices.length != _shape.length) return false;
		var flat = _offset;
		for (ax in 0...indices.length) {
			var ix = indices[ax];
			if (ix < 0 || ix >= _shape[ax]) return false;
			flat += ix * _strides[ax];
		}
		data[flat] = v ? 1 : 0;
		return true;
	}

	public function copy():NdArrayBool {
		var out = empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i));
		return out;
	}

	public function transpose(?axes:Array<Int>):Null<NdArrayBool> {
		var ndim = _shape.length;
		if (ndim <= 1) return wrapView(data, _shape.copy(), _strides.copy(), _offset);
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
		return wrapView(data, newShape, newStrides, _offset);
	}

	/** Migration / where / Muse: 0.0 / 1.0 f64 copy. */
	public function toF64():NdArrayF64 {
		var out = NdArrayF64.empty(_shape);
		for (i in 0..._size) out.setFlat(i, getFlat(i) ? 1.0 : 0.0);
		return out;
	}

	public function toF32():NdArrayF32 return NdArrayF32.fromBool(this);
	public function toI32():NdArrayI32 return NdArrayI32.fromBool(this);

	public function toArray():Array<Bool> {
		return [for (i in 0..._size) getFlat(i)];
	}

	/** Count of true values. */
	public function countTrue():Int {
		var n = 0;
		for (i in 0..._size) if (getFlat(i)) n++;
		return n;
	}

	public function any():Bool {
		for (i in 0..._size) if (getFlat(i)) return true;
		return false;
	}

	public function all():Bool {
		if (_size == 0) return true;
		for (i in 0..._size) if (!getFlat(i)) return false;
		return true;
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

	public static function empty(shape:Array<Int>):NdArrayBool {
		var sh:Shape = shape == null ? [] : shape;
		var n = sh.size();
		var a = alloc(n);
		a._shape = sh.copy();
		a._strides = sh.cStrides();
		a._offset = 0;
		a._size = n;
		a._cContig = true;
		return a;
	}

	public static function zeros(shape:Array<Int>):NdArrayBool {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, false);
		return a;
	}

	public static function ones(shape:Array<Int>):NdArrayBool {
		var a = empty(shape);
		for (i in 0...a.size) a.setFlat(i, true);
		return a;
	}

	public static function fromF64(a:NdArrayF64):NdArrayBool {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) {
			var v = a.getFlat(i);
			out.setFlat(i, v != 0 && v == v);
		}
		return out;
	}

	public static function fromF32(a:NdArrayF32):NdArrayBool {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, NdCast.truthyFloat(a.getFlat(i)));
		return out;
	}

	public static function fromI32(a:NdArrayI32):NdArrayBool {
		if (a == null) return empty([0]);
		var out = empty(a.shape);
		for (i in 0...a.size) out.setFlat(i, a.getFlat(i) != 0);
		return out;
	}

	public static function fromPacked(shape:Array<Int>, data:Array<Bool>):Null<NdArrayBool> {
		if (data == null) return null;
		var sh:Shape = shape == null ? [data.length] : shape;
		if (sh.size() != data.length) return null;
		var a = empty(sh);
		for (i in 0...data.length) a.setFlat(i, data[i]);
		return a;
	}

	#if js
	static function wrapView(buf:js.lib.Uint8Array, shape:Array<Int>, strides:Array<Int>, offset:Int):NdArrayBool {
	#else
	static function wrapView(buf:haxe.ds.Vector<Int>, shape:Array<Int>, strides:Array<Int>, offset:Int):NdArrayBool {
	#end
		var sh:Shape = shape;
		var a = new NdArrayBool();
		a.data = buf;
		a._shape = sh.copy();
		a._strides = strides.copy();
		a._offset = offset;
		a._size = sh.size();
		a.refreshFlags();
		return a;
	}

	static function alloc(n:Int):NdArrayBool {
		var a = new NdArrayBool();
		var cap = n < 0 ? 0 : n;
		#if js
		a.data = new js.lib.Uint8Array(cap);
		#else
		a.data = new haxe.ds.Vector<Int>(cap);
		#end
		return a;
	}
}
