package musescript.runtime;

/**
 * Per-run indicator/callsite state, owned by a HarnessContext.
 *
 * Holds (1) the incremental indicator columns (one per unique
 * (kind, series, params) callsite — extended only by new bars, bit-identical
 * fold order to a full per-bar recompute) and (2) dense per-callsite-id state
 * for the stateful builtins (crossover/crossunder/rising/falling).
 *
 * This state was previously static on TradeBuiltins, which was correct for
 * one tape per process but would thrash catastrophically the moment two
 * harnesses (or two symbols' series under the same names) interleave in one
 * process: the src-identity guard would rebuild whole columns on every call —
 * O(n²) with a worse constant than the pre-cache code. Owning the state per
 * harness makes a future multi-symbol / scanner universe safe by construction:
 * one harness per symbol stream, each with its own columns.
 */
class IndicatorColumns {
	var cols:Map<String, IndCol>;
	// Slot-hinted fast path: indicator callsites mostly recur in the same
	// order every bar, so an array indexed by per-bar call counter usually
	// hits without building a key string. Hits are VERIFIED against numeric
	// identity fields; a desynced slot just falls back to the keyed map, so
	// the hint affects speed only, never results.
	var slots:Array<IndCol>;
	var cursor:Int;

	/** crossover/crossunder previous pairs, dense by static callsite id. */
	public var csPairs:Array<{a:Float, b:Float}>;
	/** rising/falling short histories, dense by static callsite id. */
	public var csHist:Array<Array<Float>>;
	/** Reusable result objects for field-only macd/bbands/stoch assigns. */
	public var scratch:Array<Dynamic>;

	public function new() {
		cols = new Map();
		slots = [];
		cursor = 0;
		csPairs = [];
		csHist = [];
		scratch = [];
	}

	/** Clear everything for an independent trial/run. */
	public function reset():Void {
		cols = new Map();
		slots = [];
		cursor = 0;
		csPairs = [];
		csHist = [];
		scratch = [];
	}

	/** The reusable result object for scratch callsite `id` (created once). */
	public function scratchObj(id:Int):Dynamic {
		while (scratch.length <= id) scratch.push(null);
		if (scratch[id] == null) scratch[id] = {};
		return scratch[id];
	}

	/** Rewind the slot hint at the start of each bar. */
	public inline function beginBar():Void {
		cursor = 0;
	}

	/** Get/refresh the column entry for (kind, name, p1..p3), bound to source `src`. */
	public function get2(kind:Int, name:String, p1:Int, p2:Int, p3:Int, src:Array<Float>):IndCol {
		var slot = cursor++;
		if (slot < slots.length) {
			var hinted = slots[slot];
			if (hinted != null && hinted.kind == kind && hinted.p1 == p1 && hinted.p2 == p2
				&& hinted.p3 == p3 && hinted.name == name && hinted.src == src)
				return hinted;
		}
		var key = kind + ":" + name + ":" + p1 + ":" + p2 + ":" + p3;
		var col = cols.get(key);
		if (col == null || col.src != src) {
			col = new IndCol(src);
			col.kind = kind;
			col.name = name;
			col.p1 = p1;
			col.p2 = p2;
			col.p3 = p3;
			cols.set(key, col);
		}
		while (slots.length <= slot) slots.push(null);
		slots[slot] = col;
		return col;
	}

	public inline function get(kind:Int, name:String, len:Int, src:Array<Float>):IndCol {
		return get2(kind, name, len, 0, 0, src);
	}
}

/**
 * One incrementally-extended indicator column bound to a source series array.
 * `src` is the identity guard (a replaced series array drops the entry);
 * `a`/`b` are value columns; `f0`/`f1` are running fold accumulators.
 */
class IndCol {
	public var src:Array<Float>;
	public var a:Array<Float>;
	public var b:Array<Float>;
	public var f0:Float;
	public var f1:Float;
	// identity fields for slot-hint verification
	public var kind:Int;
	public var name:String;
	public var p1:Int;
	public var p2:Int;
	public var p3:Int;

	public function new(src:Array<Float>) {
		this.src = src;
		a = [];
		b = [];
		f0 = 0;
		f1 = 0;
		kind = 0;
		name = "";
		p1 = 0;
		p2 = 0;
		p3 = 0;
	}
}
