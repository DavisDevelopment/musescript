package musescript.dataframe;

import musescript.ndarray.NdArrayF64;
import musescript.ndarray.Np;

/**
 * Result of {@link Factorize}: integer codes into typed uniques.
 * Missing → code `-1` when `dropNa` (pandas default).
 */
class FactorizeResult {
	public var codes(default, null):Array<Int>;
	public var uniques(default, null):FactorUniques;

	public function new(codes:Array<Int>, uniques:FactorUniques) {
		this.codes = codes != null ? codes : [];
		this.uniques = uniques != null ? uniques : FactorUniques.F64(IndexF64.empty());
	}

	public var length(get, never):Int;
	inline function get_length():Int return codes.length;

	public function nUniques():Int {
		return switch (uniques) {
			case F64(u): u.length;
			case Str(u): u.length;
		};
	}

	public function kind():String {
		return switch (uniques) {
			case F64(_): "f64";
			case Str(_): "str";
		};
	}

	public function codesAsFloats():Array<Float>
		return [for (c in codes) c * 1.0];

	public function codesNdArray():NdArrayF64
		return Np.asarray(codesAsFloats());

	public function uniquesF64():Null<IndexF64> {
		return switch (uniques) {
			case F64(u): u;
			case Str(_): null;
		};
	}

	public function uniquesStr():Null<IndexStr> {
		return switch (uniques) {
			case Str(u): u;
			case F64(_): null;
		};
	}

	public function uniquesAsFloats():Array<Float> {
		return switch (uniques) {
			case F64(u): u.toArray();
			case Str(_): [];
		};
	}

	public function uniquesAsStrings():Array<String> {
		return switch (uniques) {
			case Str(u): u.labels();
			case F64(u): [for (i in 0...u.length) {
				var v = u.get(i);
				Math.isNaN(v) ? "" : Std.string(v);
			}];
		};
	}

	/** Expand codes → dense MultiLevel (length = codes.length). */
	public function toLevel():MultiLevel {
		return switch (uniques) {
			case F64(u):
				var vals:Array<Float> = [];
				for (c in codes)
					vals.push(c < 0 || c >= u.length ? Math.NaN : u.get(c));
				MultiLevel.F64(IndexF64.fromArray(vals));
			case Str(u):
				var labels:Array<String> = [];
				for (c in codes) {
					if (c < 0 || c >= u.length) labels.push("");
					else {
						var s = u.get(c);
						labels.push(s != null ? s : "");
					}
				}
				MultiLevel.Str(IndexStr.fromArray(labels));
		};
	}
}
