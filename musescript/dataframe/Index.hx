package musescript.dataframe;

import musescript.ndarray.NdArrayF64;

/**
 * Index facade — F64 time / range, Str labels, and MultiIndex (F64/Str levels, N≥1).
 */
class Index {
	public static function range(n:Int):AnyIndex return AnyIndex.F64(IndexF64.range(n));
	public static function fromFloats(labels:Array<Float>):AnyIndex
		return AnyIndex.F64(IndexF64.fromArray(labels));
	public static function fromNdArray(a:NdArrayF64):AnyIndex
		return AnyIndex.F64(IndexF64.fromNdArray(a));
	public static function fromStrings(labels:Array<String>):AnyIndex
		return AnyIndex.Str(IndexStr.fromArray(labels));
	public static function fromMulti(mi:MultiIndex):AnyIndex
		return AnyIndex.Multi(mi != null ? mi : MultiIndex.empty());
	public static function multiFromArrays(
		level0:Array<Float>,
		level1:Array<Float>,
		?names:Array<String>
	):AnyIndex
		return fromMulti(MultiIndex.fromArrays(level0, level1, names));

	public static function multiFromArraysStr(
		level0:Array<String>,
		level1:Array<String>,
		?names:Array<String>
	):AnyIndex
		return fromMulti(MultiIndex.fromArraysStr(level0, level1, names));

	public static function multiFromLevels(levels:Array<MultiLevel>, ?names:Array<String>):AnyIndex
		return fromMulti(MultiIndex.fromLevels(levels, names));

	public static function multiFromCodes(
		uniques:Array<MultiLevel>,
		codes:Array<Array<Int>>,
		?names:Array<String>
	):AnyIndex
		return fromMulti(MultiIndex.fromCodes(uniques, codes, names));

	public static function lengthOf(idx:AnyIndex):Int {
		return switch (idx) {
			case F64(i): i.length;
			case Str(i): i.length;
			case Multi(i): i.length;
		};
	}

	public static function copyOf(idx:AnyIndex):AnyIndex {
		return switch (idx) {
			case F64(i): F64(i.copy());
			case Str(i): Str(i.copy());
			case Multi(i): Multi(i.copy());
		};
	}

	public static function sliceOf(idx:AnyIndex, start:Int, stop:Int):AnyIndex {
		return switch (idx) {
			case F64(i): F64(i.slice(start, stop));
			case Str(i): Str(i.slice(start, stop));
			case Multi(i): Multi(i.slice(start, stop));
		};
	}

	public static function takeOf(idx:AnyIndex, indices:Array<Int>):AnyIndex {
		return switch (idx) {
			case F64(i): F64(i.take(indices));
			case Str(i): Str(i.take(indices));
			case Multi(i): Multi(i.take(indices));
		};
	}

	public static function kindOf(idx:AnyIndex):String {
		return switch (idx) {
			case F64(_): "f64";
			case Str(_): "str";
			case Multi(_): "multi";
		};
	}

	public static function nlevelsOf(idx:AnyIndex):Int {
		return switch (idx) {
			case Multi(i): i.nlevels;
			default: 1;
		};
	}

	public static function asF64(idx:AnyIndex):Null<IndexF64> {
		return switch (idx) {
			case F64(i): i;
			case Str(_): null;
			case Multi(_): null;
		};
	}

	public static function asStr(idx:AnyIndex):Null<IndexStr> {
		return switch (idx) {
			case Str(i): i;
			case F64(_): null;
			case Multi(_): null;
		};
	}

	public static function asMulti(idx:AnyIndex):Null<MultiIndex> {
		return switch (idx) {
			case Multi(i): i;
			case F64(_): null;
			case Str(_): null;
		};
	}

	public static function equals(a:AnyIndex, b:AnyIndex):Bool {
		return switch [a, b] {
			case [F64(x), F64(y)]: x.equals(y);
			case [Str(x), Str(y)]: x.equals(y);
			case [Multi(x), Multi(y)]: x.equals(y);
			default: false;
		};
	}
}
