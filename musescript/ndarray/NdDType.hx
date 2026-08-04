package musescript.ndarray;

/**
 * Cold dtype tags for Muse boxing / `astype` strings.
 * Never branch on this per-element — kernels stay on concrete NdArray* classes.
 *
 * Fitness / default Muse path is **F64**. Explicit `astype("float32"|"int32"|…)`
 * is required for narrower storage; silent f32 on Sharpe/equity is forbidden.
 */
enum abstract NdDType(String) to String {
	var F64 = "f64";
	var F32 = "f32";
	var I32 = "i32";
	var BOOL = "bool";

	public static function parse(s:String):Null<NdDType> {
		if (s == null) return null;
		return switch (s.toLowerCase()) {
			case "f64" | "float64" | "float" | "double": F64;
			case "f32" | "float32": F32;
			case "i32" | "int32" | "int": I32;
			case "bool" | "boolean": BOOL;
			default: null;
		};
	}

	public static function nameOf(d:NdDType):String return (d : String);
}
