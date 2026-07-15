package musescript.evo;

/** Closed typed palette mirrored from musegene/palette.py. */
class Palette {
	public static final FIELDS:Array<String> = ["open", "high", "low", "close", "volume"];
	public static final INDS:Array<String> = [
		"sma", "ema", "rsi", "atr", "wma", "rma", "stdev",
		"highest", "lowest", "mom", "roc", "change"
	];
	public static final WINDOWS:Array<Int> = [2, 3, 5, 8, 13, 21, 34, 55, 89];
	public static final ARITH:Array<String> = ["+", "-", "*", "min", "max"];
	public static final CMP:Array<String> = [">", "<", ">=", "<="];
	public static final CROSS:Array<String> = ["over", "under"];

	public static function toJson():Dynamic {
		return {
			schema: "musegene.palette/1",
			id: "musegene.bar-v1",
			fields: FIELDS,
			windows: WINDOWS,
			indicators: INDS,
			arith: ARITH,
			cmp: CMP,
			cross: CROSS,
			limits: { maxDepth: 6, maxNodes: 256 }
		};
	}
}
