package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.harness.SymbolBag;

/**
 * Named/weighted symbol bags + portfolio composition.
 *
 * Bags default to **static** fixed weights. **Computed** bags carry a recipe
 * and/or zero-arg builder and rematerialize on `bag_resolve` / portfolio ops
 * from the live panel (mom/rsi/fund series) or a graph.
 *
 * Evo Expand closes a narrow subset only: fixed-universe score object literals →
 * `bag_from_scan` / `bag_from_dict`+`bag_norm` → `portfolio_apply`
 * (`PanelAction.PABagScanTop` / `PABagRankWeights`). WASM HostABI lowers those
 * closed forms (`apply_bag_scan` / `apply_bag_weights`). NMA hosts both columnarily
 * (`preferNma`): scan → equal bag; rank-weights → percentile xs_rank → `bag_norm`.
 * Open recipes (`bag_rank_mom`, `bag_computed`, `bag_graph`, `symbols()` loops) stay
 * authored surface — not genome Expand.
 */
class BagBuiltins {
	/**
	 * Install the bag/portfolio-composition surface. Every entry is a thin
	 * adapter over a named public static below (the statics are the real,
	 * documented, individually-testable implementations; the closures exist
	 * only to bind `harness`). See BuiltinSigs for the typed signatures.
	 */
	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("bag", function(?name:String) return bagNew(name));
		vars.set("bag_new", function(?name:String) return bagNew(name));
		vars.set("bag_set", function(b:Dynamic, sym:String, w:Float) return bagSet(b, sym, w));
		vars.set("bag_get", function(b:Dynamic, sym:String) return materialize(harness, b).weightOf(sym));
		vars.set("bag_has", function(b:Dynamic, sym:String) return materialize(harness, b).weights.exists(sym));
		vars.set("bag_delete", function(b:Dynamic, sym:String) return ensure(b).setWeight(sym, 0));
		vars.set("bag_name", function(b:Dynamic) return ensure(b).name);
		vars.set("bag_rename", function(b:Dynamic, name:String) return ensure(b).copy(name));
		vars.set("bag_symbols", function(b:Dynamic) return materialize(harness, b).symbols());
		vars.set("bag_size", function(b:Dynamic) return materialize(harness, b).size());
		vars.set("bag_mode", function(b:Dynamic) return ensure(b).isComputed() ? "computed" : "static");
		vars.set("bag_is_static", function(b:Dynamic) return !ensure(b).isComputed());
		vars.set("bag_is_computed", function(b:Dynamic) return ensure(b).isComputed());

		vars.set("bag_equal", function(syms:Dynamic, ?name:String) return bagEqual(syms, name));
		vars.set("bag_pair", function(longSym:String, shortSym:String, ?scale:Float, ?name:String)
			return bagPair(longSym, shortSym, scale, name));
		vars.set("bag_from_dict", function(d:Dynamic, ?name:String) return bagFromDict(d, name));
		vars.set("bag_from_scan", function(scores:Dynamic, n:Int, ?name:String, ?bottom:Bool)
			return bagFromScan(scores, n, name, bottom));
		vars.set("bag_to_dict", function(b:Dynamic) return bagToDict(harness, b));

		vars.set("bag_computed", function(name:Dynamic, spec:Dynamic) return bagComputed(name, spec));
		vars.set("bag_resolve", function(b:Dynamic) return materialize(harness, b));
		vars.set("bag_rank_mom", function(n:Int, ?look:Int, ?name:String) return bagRankMom(n, look, name));
		vars.set("bag_rank_rsi", function(n:Int, ?len:Int, ?name:String, ?ascending:Bool)
			return bagRankRsi(n, len, name, ascending));
		vars.set("bag_rank_field", function(field:String, n:Int, ?name:String, ?ascending:Bool)
			return bagRankField(field, n, name, ascending));
		vars.set("bag_graph", function(graph:Dynamic, seed:String, ?limit:Int, ?name:String)
			return bagGraph(graph, seed, limit, name));

		vars.set("bag_add", function(a:Dynamic, b:Dynamic, ?name:String)
			return bagAdd(materialize(harness, a), materialize(harness, b), name));
		vars.set("bag_sub", function(a:Dynamic, b:Dynamic, ?name:String)
			return bagSub(materialize(harness, a), materialize(harness, b), name));
		vars.set("bag_mask", function(a:Dynamic, mask:Dynamic, ?name:String)
			return bagMask(materialize(harness, a), mask, name));
		vars.set("bag_scale", function(a:Dynamic, k:Float, ?name:String)
			return bagScale(materialize(harness, a), k, name));
		vars.set("bag_norm", function(a:Dynamic, ?name:String)
			return bagNorm(materialize(harness, a), name));

		vars.set("portfolio_bag", function(?name:String) return portfolioBag(harness, name));
		vars.set("portfolio_apply", function(b:Dynamic) return portfolioApply(harness, b));
		vars.set("portfolio_add", function(b:Dynamic) return portfolioAdd(harness, b));
		vars.set("portfolio_sub", function(b:Dynamic) return portfolioSub(harness, b));
		vars.set("portfolio_mask", function(mask:Dynamic) return portfolioMask(harness, mask));
	}

	/**
	 * `bag_set(bag, sym, w)` — set `sym`'s weight on the (static) bag in place.
	 * Rejects non-finite weights loudly instead of quietly corrupting the book:
	 * a NaN weight here used to propagate into portfolio_apply as a NaN order.
	 */
	public static function bagSet(b:Dynamic, sym:String, w:Float):SymbolBag {
		if (sym == null || sym == "") throw "bag_set: symbol must be a non-empty string";
		if (Math.isNaN(w) || !Math.isFinite(w)) throw 'bag_set: weight for "$sym" must be finite (got $w)';
		return ensure(b).setWeight(sym, w);
	}

	/** `bag_from_scan(scores, n)` — equal-weight bag of the top-n (or bottom-n) scored symbols. */
	public static function bagFromScan(scores:Dynamic, n:Int, ?name:String, ?bottom:Bool):SymbolBag {
		var picks = PortfolioBuiltins.rankPick(scores, n, bottom == true);
		return bagEqual(picks, name != null ? name : "scan");
	}

	/** `bag_to_dict(bag)` — materialized weights as a plain string-keyed dict. */
	public static function bagToDict(harness:HarnessContext, b:Dynamic):Map<String, Dynamic> {
		var bag = materialize(harness, b);
		var d = new Map<String, Dynamic>();
		for (k => v in bag.weights) d.set(k, v);
		return d;
	}

	/** `bag_rank_mom(n, look)` — computed bag: top-n panel symbols by `look`-bar momentum. */
	public static function bagRankMom(n:Int, ?look:Int, ?name:String):SymbolBag {
		return bagRecipe(name != null ? name : "rank_mom", {
			op: "rank_mom",
			n: n,
			look: look != null ? look : 21
		});
	}

	/** `bag_rank_rsi(n, len, ?ascending)` — computed bag: top-n (or bottom-n) by RSI. */
	public static function bagRankRsi(n:Int, ?len:Int, ?name:String, ?ascending:Bool):SymbolBag {
		return bagRecipe(name != null ? name : "rank_rsi", {
			op: "rank_rsi",
			n: n,
			len: len != null ? len : 14,
			ascending: ascending == true
		});
	}

	/** `bag_rank_field(field, n, ?ascending)` — computed bag ranked by any per-symbol series (`pe`, `close`, …). */
	public static function bagRankField(field:String, n:Int, ?name:String, ?ascending:Bool):SymbolBag {
		return bagRecipe(name != null ? name : ("rank_" + field), {
			op: "rank_field",
			field: field,
			n: n,
			ascending: ascending == true
		});
	}

	/** `bag_graph(graph, seed, ?limit)` — computed bag of `seed`'s graph out-neighbors. */
	public static function bagGraph(graph:Dynamic, seed:String, ?limit:Int, ?name:String):SymbolBag {
		return bagRecipe(name != null ? name : ("nbr:" + seed), {
			op: "graph_neighbors",
			graph: graph,
			seed: seed,
			limit: limit != null ? limit : 16,
			direction: "out"
		});
	}

	/** `portfolio_apply(bag)` — rebalance the whole book to the bag's weights (sells non-members). */
	public static function portfolioApply(harness:HarnessContext, b:Dynamic):Void {
		harness.portfolio.applyBag(materialize(harness, b).weights, harness.panelPrices, currentBarIndex(harness), true);
	}

	/** `portfolio_add(bag)` — merge the bag INTO the current book (keeps existing positions). */
	public static function portfolioAdd(harness:HarnessContext, b:Dynamic):Void {
		var merged = bagAdd(portfolioBag(harness, ""), materialize(harness, b), null);
		harness.portfolio.applyBag(merged.weights, harness.panelPrices, currentBarIndex(harness), false);
	}

	/** `portfolio_sub(bag)` — subtract the bag's weights from the current book. */
	public static function portfolioSub(harness:HarnessContext, b:Dynamic):Void {
		var merged = bagSub(portfolioBag(harness, ""), materialize(harness, b), null);
		harness.portfolio.applyBag(merged.weights, harness.panelPrices, currentBarIndex(harness), true);
	}

	/** `portfolio_mask(mask)` — keep only positions whose symbols are in the mask; liquidate the rest. */
	public static function portfolioMask(harness:HarnessContext, mask:Dynamic):Void {
		var kept = bagMask(portfolioBag(harness, ""), mask, null);
		harness.portfolio.applyBag(kept.weights, harness.panelPrices, currentBarIndex(harness), true);
	}

	static function currentBarIndex(harness:HarnessContext):Int {
		return harness.currentBar != null ? harness.currentBar.index : -1;
	}

	public static function bagNew(?name:String):SymbolBag {
		return new SymbolBag(name != null ? name : "");
	}

	public static function bagRecipe(name:String, recipe:Dynamic):SymbolBag {
		var bag = new SymbolBag(name);
		bag.mode = "computed";
		bag.recipe = recipe;
		return bag;
	}

	/**
	 * `bag_computed(name, fn)` or `bag_computed(name, recipeDict)` or
	 * `bag_computed(recipeDict)` (unnamed).
	 */
	public static function bagComputed(nameOrSpec:Dynamic, ?spec:Dynamic):SymbolBag {
		var name = "";
		var body:Dynamic = null;
		if (spec == null) {
			body = nameOrSpec;
		} else {
			name = nameOrSpec != null ? Std.string(nameOrSpec) : "";
			body = spec;
		}
		var bag = new SymbolBag(name);
		bag.mode = "computed";
		if (Reflect.isFunction(body) || Std.isOfType(body, musescript.runtime.FnClosure)) {
			bag.computeFn = body;
		} else if (body != null && recipeField(body, "op", null) != null) {
			bag.recipe = body;
		} else {
			bag.computeFn = body;
		}
		return bag;
	}

	/** Resolve computed → static snapshot; static bags returned as a copy. */
	public static function materialize(harness:HarnessContext, b:Dynamic):SymbolBag {
		var bag = ensure(b);
		if (!bag.isComputed()) return bag.snapshot();
		var built:SymbolBag = null;
		if (bag.computeFn != null) {
			var raw:Dynamic = null;
			if (harness.invokeUserFn != null) {
				raw = harness.invokeUserFn(bag.computeFn, []);
			} else if (Reflect.isFunction(bag.computeFn)) {
				raw = Reflect.callMethod(null, bag.computeFn, []);
			}
			built = ensure(raw);
		} else if (bag.recipe != null) {
			built = evalRecipe(harness, bag.recipe, bag.name);
		} else {
			built = bag.snapshot();
		}
		var out = built.snapshot(bag.name != "" ? bag.name : built.name);
		// refresh cache on the live computed bag for inspection
		bag.weights = SymbolBag.copyWeights(out.weights);
		return out;
	}

	public static function evalRecipe(harness:HarnessContext, recipe:Dynamic, ?name:String):SymbolBag {
		var op = recipeField(recipe, "op", "");
		var n = name != null && name != "" ? name : Std.string(recipeField(recipe, "name", op));
		return switch (op) {
			case "rank_mom":
				var look = Std.int(asFloat(recipeField(recipe, "look", 21)));
				var topN = Std.int(asFloat(recipeField(recipe, "n", 5)));
				bagEqual(rankBy(harness, function(sym) {
					return TradeBuiltins.mom(harness, PortfolioBuiltins.seriesKey("close", sym), look);
				}, topN, false), n);
			case "rank_rsi":
				var len = Std.int(asFloat(recipeField(recipe, "len", 14)));
				var topN = Std.int(asFloat(recipeField(recipe, "n", 5)));
				var asc = recipeField(recipe, "ascending", false) == true;
				bagEqual(rankBy(harness, function(sym) {
					return TradeBuiltins.rsi(harness, PortfolioBuiltins.seriesKey("close", sym), len);
				}, topN, asc), n);
			case "rank_field":
				var field = Std.string(recipeField(recipe, "field", "close"));
				var topN = Std.int(asFloat(recipeField(recipe, "n", 5)));
				var asc = recipeField(recipe, "ascending", false) == true;
				bagEqual(rankBy(harness, function(sym) {
					return fieldScore(harness, field, sym);
				}, topN, asc), n);
			case "graph_neighbors":
				var graph = recipeField(recipe, "graph", null);
				var seed = Std.string(recipeField(recipe, "seed", ""));
				var limit = Std.int(asFloat(recipeField(recipe, "limit", 16)));
				var dir = Std.string(recipeField(recipe, "direction", "out"));
				var nbrs = GraphBuiltins.graphNeighbors(graph, seed, dir, limit);
				bagEqual(nbrs, n);
			case "graph_bfs":
				var g2 = recipeField(recipe, "graph", null);
				var start = Std.string(recipeField(recipe, "seed", recipeField(recipe, "start", "")));
				var depth = Std.int(asFloat(recipeField(recipe, "maxDepth", 2)));
				var maxN = Std.int(asFloat(recipeField(recipe, "limit", 32)));
				var nodes = GraphBuiltins.graphBfs(g2, start, depth, maxN);
				bagEqual(nodes, n);
			default:
				new SymbolBag(n);
		};
	}

	static function fieldScore(harness:HarnessContext, field:String, sym:String):Float {
		if (field == "mom" || field == "momentum")
			return TradeBuiltins.mom(harness, PortfolioBuiltins.seriesKey("close", sym), 21);
		if (field == "rsi")
			return TradeBuiltins.rsi(harness, PortfolioBuiltins.seriesKey("close", sym), 14);
		if (field == "close" || field == "open" || field == "high" || field == "low" || field == "volume")
			return harness.seriesLookback(PortfolioBuiltins.seriesKey(field, sym), 0);
		// fundamentals / aux: series named field@SYM (e.g. pe@AAPL)
		return harness.seriesLookback(PortfolioBuiltins.seriesKey(field, sym), 0);
	}

	static function rankBy(harness:HarnessContext, scoreOf:String->Float, n:Int, ascending:Bool):Array<String> {
		var rows:Array<{sym:String, score:Float}> = [];
		var syms = harness.panelSymbols != null ? harness.panelSymbols : [];
		for (sym in syms) {
			var px = harness.panelPrice(sym);
			if (!(px > 0) || Math.isNaN(px)) continue;
			var s = scoreOf(sym);
			if (Math.isNaN(s) || !Math.isFinite(s)) continue;
			rows.push({ sym: sym, score: s });
		}
		rows.sort(function(a, b) {
			if (a.score < b.score) return ascending ? -1 : 1;
			if (a.score > b.score) return ascending ? 1 : -1;
			return Reflect.compare(a.sym, b.sym);
		});
		var take = n > 0 ? Std.int(Math.min(n, rows.length)) : rows.length;
		return [for (i in 0...take) rows[i].sym];
	}

	static function recipeField(recipe:Dynamic, key:String, def:Dynamic):Dynamic {
		if (recipe == null) return def;
		if (Std.isOfType(recipe, haxe.ds.StringMap)) {
			var sm:haxe.ds.StringMap<Dynamic> = cast recipe;
			return sm.exists(key) ? sm.get(key) : def;
		}
		if (Reflect.hasField(recipe, "get") && Reflect.isFunction(Reflect.field(recipe, "get"))) {
			try {
				var v = Reflect.callMethod(recipe, Reflect.field(recipe, "get"), [key]);
				return v != null ? v : def;
			} catch (_:Dynamic) {}
		}
		if (Reflect.hasField(recipe, key)) return Reflect.field(recipe, key);
		return def;
	}

	public static function bagEqual(syms:Dynamic, ?name:String):SymbolBag {
		var list = PortfolioBuiltins.toStringArray(syms);
		var bag = new SymbolBag(name != null ? name : "equal");
		if (list.length == 0) return bag;
		var w = 1.0 / list.length;
		for (s in list) bag.weights.set(s, w);
		bag.mode = "static";
		return bag;
	}

	/** Dollar-neutral pair: +scale/2 long, -scale/2 short. */
	public static function bagPair(longSym:String, shortSym:String, ?scale:Float, ?name:String):SymbolBag {
		var s = scale != null && scale > 0 ? scale : 1.0;
		var n = name != null ? name : (longSym + "/" + shortSym);
		var bag = new SymbolBag(n);
		if (longSym != null && longSym != "") bag.weights.set(longSym, s * 0.5);
		if (shortSym != null && shortSym != "") bag.weights.set(shortSym, -s * 0.5);
		bag.mode = "static";
		return bag;
	}

	public static function bagFromDict(d:Dynamic, ?name:String):SymbolBag {
		var bag = new SymbolBag(name != null ? name : "");
		if (d == null) return bag;
		if (SymbolBag.isBag(d)) return ensure(d).snapshot(name);
		var rows = scoreRows(d);
		for (r in rows) bag.weights.set(r.sym, r.score);
		bag.mode = "static";
		return bag;
	}

	public static function bagAdd(a:SymbolBag, b:SymbolBag, ?name:String):SymbolBag {
		var n = name != null ? name : joinName(a.name, b.name, "+");
		var out = new SymbolBag(n, a.weights);
		for (k => v in b.weights) {
			var w = out.weightOf(k) + v;
			if (w == 0 || Math.isNaN(w)) out.weights.remove(k);
			else out.weights.set(k, w);
		}
		out.mode = "static";
		return out;
	}

	public static function bagSub(a:SymbolBag, b:SymbolBag, ?name:String):SymbolBag {
		var n = name != null ? name : joinName(a.name, b.name, "-");
		var out = new SymbolBag(n, a.weights);
		for (k => v in b.weights) {
			var w = out.weightOf(k) - v;
			if (w == 0 || Math.isNaN(w)) out.weights.remove(k);
			else out.weights.set(k, w);
		}
		out.mode = "static";
		return out;
	}

	public static function bagMask(a:SymbolBag, mask:Dynamic, ?name:String):SymbolBag {
		var keep = maskKeys(mask);
		var n = name != null ? name : (a.name != "" ? a.name + "&mask" : "mask");
		var out = new SymbolBag(n);
		for (k => v in a.weights) {
			if (keep.exists(k)) out.weights.set(k, v);
		}
		out.mode = "static";
		return out;
	}

	public static function bagScale(a:SymbolBag, k:Float, ?name:String):SymbolBag {
		var n = name != null ? name : a.name;
		var out = new SymbolBag(n);
		if (Math.isNaN(k) || k == 0) return out;
		for (sym => w in a.weights) out.weights.set(sym, w * k);
		out.mode = "static";
		return out;
	}

	public static function bagNorm(a:SymbolBag, ?name:String):SymbolBag {
		var n = name != null ? name : a.name;
		var sum = 0.0;
		for (_ => w in a.weights) sum += Math.abs(w);
		if (!(sum > 0)) return a.snapshot(n);
		return bagScale(a, 1.0 / sum, n);
	}

	public static function portfolioBag(harness:HarnessContext, ?name:String):SymbolBag {
		var bag = new SymbolBag(name != null ? name : "book");
		var prices = harness.panelPrices;
		var eq = harness.portfolio.equityAt(prices);
		if (!(eq > 0)) return bag;
		for (sym in harness.portfolio.holdings()) {
			var px = prices != null && prices.exists(sym) ? prices.get(sym) : Math.NaN;
			if (!(px > 0) || Math.isNaN(px)) continue;
			var qty = harness.portfolio.positionOf(sym);
			bag.weights.set(sym, qty * px / eq);
		}
		bag.mode = "static";
		return bag;
	}

	public static function ensure(b:Dynamic):SymbolBag {
		if (SymbolBag.isBag(b)) return cast b;
		if (b == null) return new SymbolBag();
		return bagFromDict(b, null);
	}

	static function joinName(a:String, b:String, op:String):String {
		if (a == "" && b == "") return "";
		if (a == "") return b;
		if (b == "") return a;
		return a + op + b;
	}

	static function maskKeys(mask:Dynamic):Map<String, Bool> {
		var keep = new Map<String, Bool>();
		if (mask == null) return keep;
		if (SymbolBag.isBag(mask)) {
			for (k in ensure(mask).weights.keys()) keep.set(k, true);
			return keep;
		}
		if (Std.isOfType(mask, Array)) {
			for (v in (cast mask : Array<Dynamic>)) keep.set(Std.string(v), true);
			return keep;
		}
		if (Reflect.hasField(mask, "keys") && Reflect.isFunction(Reflect.field(mask, "keys"))) {
			try {
				var it:Iterator<Dynamic> = Reflect.callMethod(mask, Reflect.field(mask, "keys"), []);
				while (it.hasNext()) keep.set(Std.string(it.next()), true);
				return keep;
			} catch (_:Dynamic) {}
		}
		for (k in Reflect.fields(mask)) keep.set(k, true);
		return keep;
	}

	static function scoreRows(scores:Dynamic):Array<{sym:String, score:Float}> {
		var rows:Array<{sym:String, score:Float}> = [];
		if (scores == null) return rows;
		if (Std.isOfType(scores, haxe.ds.StringMap)) {
			var sm:haxe.ds.StringMap<Dynamic> = cast scores;
			for (k in sm.keys()) {
				var s = asFloat(sm.get(k));
				if (!Math.isNaN(s) && Math.isFinite(s) && s != 0)
					rows.push({ sym: k, score: s });
			}
			return rows;
		}
		if (Reflect.hasField(scores, "keys") && Reflect.isFunction(Reflect.field(scores, "keys"))) {
			try {
				var it:Iterator<Dynamic> = Reflect.callMethod(scores, Reflect.field(scores, "keys"), []);
				while (it.hasNext()) {
					var k = Std.string(it.next());
					var raw = Reflect.hasField(scores, "get")
						? Reflect.callMethod(scores, Reflect.field(scores, "get"), [k])
						: Reflect.field(scores, k);
					var s = asFloat(raw);
					if (!Math.isNaN(s) && Math.isFinite(s) && s != 0)
						rows.push({ sym: k, score: s });
				}
				return rows;
			} catch (_:Dynamic) {}
		}
		for (k in Reflect.fields(scores)) {
			var s = asFloat(Reflect.field(scores, k));
			if (!Math.isNaN(s) && Math.isFinite(s) && s != 0)
				rows.push({ sym: k, score: s });
		}
		return rows;
	}

	static function asFloat(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		return Std.parseFloat(Std.string(v));
	}
}
