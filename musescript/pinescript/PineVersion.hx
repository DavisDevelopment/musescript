package musescript.pinescript;

/**
 * Pine dialect version. TradingView ships v1–v6; we normalize to the enum and
 * thread it through parse + lowering so version-gated builtin renames resolve.
 *
 * We deliberately DON'T fork the grammar per version — deltas are small
 * (`study`→`indicator`, `security`→`request.security`, tightened v5 types,
 * v6 additions). One grammar reads this flag at the few productions that differ.
 */
enum abstract PineVersion(Int) from Int to Int {
	var V1 = 1;
	var V2 = 2;
	var V3 = 3;
	var V4 = 4;
	var V5 = 5;
	var V6 = 6;

	/** TradingView's current default when no `//@version=` pragma is present. */
	public static inline var DEFAULT:PineVersion = V5;

	public inline function gte(o:PineVersion):Bool
		return (this : Int) >= (o : Int);

	public inline function toInt():Int
		return this;

	/** v4 introduced the reassignment operator `:=` and `if`/`for` as expressions. */
	public inline function hasReassign():Bool
		return gte(V4);

	/** v4+ namespaced the stdlib (`ta.`, `math.`, `request.`, `strategy.`, `array.`). */
	public inline function hasNamespaces():Bool
		return gte(V4);

	/** v5 added `array.*`/`matrix.*`, `switch`, `input.*` factory calls. v6 added maps. */
	public inline function hasCollections():Bool
		return gte(V5);

	public inline function hasMaps():Bool
		return gte(V6);
}

/**
 * Reads the `//@version=N` compiler pragma from source. TradingView allows it
 * anywhere but conventionally the first non-blank line; we scan the whole head
 * and take the first match. Absent → DEFAULT (v5), matching TradingView.
 */
class PineVersionSniff {
	static var RE = ~/\/\/@version\s*=\s*([1-6])/;

	public static function detect(source:String):PineVersion {
		if (RE.match(source)) {
			return (Std.parseInt(RE.matched(1)) : PineVersion);
		}
		return PineVersion.DEFAULT;
	}
}
