package musescript.ndarray;

/**
 * Compile-time dtype-specialized NdArray (`@:multiType`), RingBuffer doctrine.
 *
 * Arms: `Float` → `NdArrayF64` (default / fitness), `Int` → `NdArrayI32`.
 * `NdArrayF32` is a parallel concrete class (Haxe has no distinct f32 type) —
 * use `Np.zerosF32` / `astype("float32")`. Prefer concrete classes on hot paths.
 * Muse opaque values use `AnyNdArray` at the builtins wall.
 */
@:multiType(@:followWithAbstracts T)
abstract NdArray<T>(INdArrayCore<T>) {
	public function new(shape:Array<Int>);

	public var shape(get, never):Shape;
	public var ndim(get, never):Int;
	public var size(get, never):Int;

	inline function get_shape():Shape return this.getShape();
	inline function get_ndim():Int return this.getNdim();
	inline function get_size():Int return this.getSize();

	public inline function getFlat(i:Int):T return this.getFlat(i);
	public inline function setFlat(i:Int, v:T):Void this.setFlat(i, v);
	public inline function getAt(indices:Array<Int>):T return this.getAt(indices);
	public inline function copy():NdArrayF64 return this.copyF64();
	public inline function reshape(newShape:Array<Int>):Null<NdArrayF64> return this.reshapeF64(newShape);
	public inline function toArray():Array<T> return this.toArray();

	@:to static inline function toFloatImpl(t:INdArrayCore<Float>, shape:Array<Int>):NdArrayF64
		return NdArrayF64.zeros(shape);

	@:to static inline function toIntImpl(t:INdArrayCore<Int>, shape:Array<Int>):NdArrayI32
		return NdArrayI32.zeros(shape);
}
