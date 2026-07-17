package musescript.harness;

/**
 * Named weighted bag of symbols (and pairs via signed weights).
 *
 * Default bags are **static** (fixed weights). **Computed** bags carry a
 * recipe and/or zero-arg builder; `bag_resolve` / portfolio ops rematerialize
 * weights from the live panel (momentum, fundamentals series, graph
 * neighbors, etc.) before trading.
 */
class SymbolBag {
	public var name:String;
	public var weights:Map<String, Float>;
	/** `"static"` (default) or `"computed"`. */
	public var mode:String;
	/**
	 * Structured recipe for computed bags, e.g.
	 * `{ op:"rank_mom", n:5, look:21 }` / `{ op:"graph_neighbors", graph:g, seed:"AAPL", limit:8 }`
	 * / `{ op:"rank_field", field:"pe", n:10, ascending:true }`.
	 */
	public var recipe:Null<Dynamic>;
	/** Optional zero-arg host/Muse function returning a Bag or weight Dict. */
	public var computeFn:Null<Dynamic>;

	public function new(?name:String, ?weights:Map<String, Float>) {
		this.name = name != null ? name : "";
		this.weights = weights != null ? copyWeights(weights) : new Map();
		this.mode = "static";
		this.recipe = null;
		this.computeFn = null;
	}

	public function isComputed():Bool {
		return mode == "computed" || computeFn != null || recipe != null;
	}

	public function copy(?newName:String):SymbolBag {
		var b = new SymbolBag(newName != null ? newName : name, weights);
		b.mode = mode;
		b.recipe = recipe;
		b.computeFn = computeFn;
		return b;
	}

	/** Static snapshot copy (drops recipe / computeFn). */
	public function snapshot(?newName:String):SymbolBag {
		var b = new SymbolBag(newName != null ? newName : name, weights);
		b.mode = "static";
		return b;
	}

	public function size():Int {
		var n = 0;
		for (_ in weights.keys()) n++;
		return n;
	}

	public function symbols():Array<String> {
		var out:Array<String> = [for (k in weights.keys()) k];
		out.sort(Reflect.compare);
		return out;
	}

	public function weightOf(sym:String):Float {
		return weights.exists(sym) ? weights.get(sym) : 0.0;
	}

	public function setWeight(sym:String, w:Float):SymbolBag {
		// Mutating weights pins the bag as static.
		mode = "static";
		recipe = null;
		computeFn = null;
		if (sym == null || sym == "") return this;
		if (Math.isNaN(w) || w == 0) weights.remove(sym);
		else weights.set(sym, w);
		return this;
	}

	public static function copyWeights(src:Map<String, Float>):Map<String, Float> {
		var out = new Map<String, Float>();
		if (src == null) return out;
		for (k => v in src) {
			if (v != 0 && !Math.isNaN(v)) out.set(k, v);
		}
		return out;
	}

	public static function isBag(v:Dynamic):Bool {
		return v != null && Std.isOfType(v, SymbolBag);
	}
}
