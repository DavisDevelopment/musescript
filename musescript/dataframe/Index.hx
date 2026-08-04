package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Index facade — F64 time / range and Str labels.
 */
class Index {
	public static function range(n:Int):AnyIndex return AnyIndex.F64(IndexF64.range(n));
	public static function fromFloats(labels:Array<Float>):AnyIndex
		return AnyIndex.F64(IndexF64.fromArray(labels));
	public static function fromNdArray(a:NdArrayF64):AnyIndex
		return AnyIndex.F64(IndexF64.fromNdArray(a));
	public static function fromStrings(labels:Array<String>):AnyIndex
		return AnyIndex.Str(IndexStr.fromArray(labels));

	public static function lengthOf(idx:AnyIndex):Int {
		return switch (idx) {
			case F64(i): i.length;
			case Str(i): i.length;
		};
	}

	public static function copyOf(idx:AnyIndex):AnyIndex {
		return switch (idx) {
			case F64(i): F64(i.copy());
			case Str(i): Str(i.copy());
		};
	}

	public static function sliceOf(idx:AnyIndex, start:Int, stop:Int):AnyIndex {
		return switch (idx) {
			case F64(i): F64(i.slice(start, stop));
			case Str(i): Str(i.slice(start, stop));
		};
	}

	public static function takeOf(idx:AnyIndex, indices:Array<Int>):AnyIndex {
		return switch (idx) {
			case F64(i): F64(i.take(indices));
			case Str(i): Str(i.take(indices));
		};
	}

	public static function kindOf(idx:AnyIndex):String {
		return switch (idx) {
			case F64(_): "f64";
			case Str(_): "str";
		};
	}

	public static function asF64(idx:AnyIndex):Null<IndexF64> {
		return switch (idx) {
			case F64(i): i;
			case Str(_): null;
		};
	}

	public static function asStr(idx:AnyIndex):Null<IndexStr> {
		return switch (idx) {
			case Str(i): i;
			case F64(_): null;
		};
	}

	public static function equals(a:AnyIndex, b:AnyIndex):Bool {
		return switch [a, b] {
			case [F64(x), F64(y)]: x.equals(y);
			case [Str(x), Str(y)]: x.equals(y);
			default: false;
		};
	}
}
