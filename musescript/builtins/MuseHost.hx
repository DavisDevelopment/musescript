package musescript.builtins;

import musescript.harness.HarnessContext;

/**
 * Namespaced strategy host stdlib: one `muse` global whose fields are plain
 * objects of callables wrapping the existing flat Trade/Portfolio/Bag builtins.
 *
 *   muse.orders.long()
 *   muse.fund.of("AAPL", "revenue")
 *   muse.data.close_of("AAPL")
 *   muse.portfolio.buy("AAPL", 1)
 *   muse.chart.plot(close, "c")
 *   muse.bags.equal(["AAPL", "MSFT"])
 *   muse.params.get("fast")
 *   muse.indicators.get("rsi")
 *   muse.math.abs(x)
 *   muse.ta.sma(close, 14)
 *
 * Same install shape as `ta` / `Math` — no new language surface. `MuseHostLower`
 * (and Strat `this.<ns>.*` sugar in `ClassStrategyLower`) rewrites these to
 * flat builtins or object receivers (`Math` / `params` / `ta`) so JS/WASM keep
 * the fast HostABI path where those ops are native.
 *
 * Evo boundary: `Palette.FIELDS` stays OHLCV-only; fund/aux enter genomes only
 * via gated `Palette.AUX_FIELDS` + tape presence (`Palette.fieldsFor`).
 *
 * WASM: `MuseCompiler.lower` / `StrategyWasmBackend` always run `MuseHostLower`
 * before emit. Single-symbol orders/chart/math and bare aux reads from
 * `Bar.data` (PIT-joined offline; no live EDGAR/network in strategy runtime)
 * lower natively. Panel v1: literal-symbol `close_of` / `mom_of` / `sma_of` /
 * `sym_available` / `fund_of` pack into `field@SYM` feature slots; literal
 * `buy`/`sell_all` are HostABI imports. Bags, computed/graph bags, `symbols()`,
 * scan/rebalance/portfolio queries stay `host_eval` or whole-module fallback
 * (`StrategyWasmEmitter.PANEL_HOST_ESCAPE`).
 */
class MuseHost {
	/** Namespaces that lower to `Receiver.method(...)` rather than a flat builtin. */
	public static final OBJECT_NS:Map<String, String> = [
		"math" => "Math",
		"params" => "params",
		"indicators" => "indicators",
		"ta" => "ta"
	];

	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("muse", build(harness));
	}

	/** Shared by MuseInterp globals and JsBackend frame installs. */
	public static function build(harness:HarnessContext):Dynamic {
		var muse:Dynamic = {};
		Reflect.setField(muse, "orders", buildOrders(harness));
		Reflect.setField(muse, "fund", buildFund(harness));
		Reflect.setField(muse, "data", buildData(harness));
		Reflect.setField(muse, "portfolio", buildPortfolio(harness));
		Reflect.setField(muse, "chart", buildChart(harness));
		Reflect.setField(muse, "bags", buildBags(harness));
		Reflect.setField(muse, "params", buildParams(harness));
		Reflect.setField(muse, "indicators", buildIndicators(harness));
		Reflect.setField(muse, "math", buildMath());
		Reflect.setField(muse, "ta", TaToolbelt.build(harness));
		return muse;
	}

	/**
	 * Map `(namespace, method)` → flat builtin name installed by TradeBuiltins /
	 * PortfolioBuiltins / BagBuiltins. Null when unknown or when the ns lowers
	 * via `OBJECT_NS` instead.
	 */
	public static function resolveFlat(ns:String, method:String):Null<String> {
		if (OBJECT_NS.exists(ns)) return null;
		var table = FLAT.get(ns);
		if (table == null) return null;
		return table.get(method);
	}

	/** Object receiver for `muse.<ns>` when it is not a flat-builtin bag (`Math`, `params`, …). */
	public static function resolveObjectReceiver(ns:String):Null<String> {
		return OBJECT_NS.get(ns);
	}

	public static function namespaces():Array<String> {
		var out = [for (k in FLAT.keys()) k];
		for (k in OBJECT_NS.keys()) out.push(k);
		out.sort(Reflect.compare);
		return out;
	}

	public static function methodsOf(ns:String):Array<String> {
		if (OBJECT_NS.exists(ns)) {
			return switch (ns) {
				case "math": ["abs", "sqrt", "floor", "ceil", "round", "min", "max", "exp", "log", "pow", "sin", "cos"];
				case "params": ["register", "get", "set"];
				case "indicators": ["register", "get"];
				case "ta": []; // registry-driven
				default: [];
			};
		}
		var table = FLAT.get(ns);
		if (table == null) return [];
		return [for (k in table.keys()) k];
	}

	static final FLAT:Map<String, Map<String, String>> = [
		"orders" => [
			"long" => "long",
			"short" => "short",
			"flat" => "flat",
			"pending" => "orders_pending",
			"cancel_all" => "orders_cancel_all",
			"orders_pending" => "orders_pending",
			"orders_cancel_all" => "orders_cancel_all",
			"position" => "position",
			"entry_price" => "entry_price",
			"bars_in_trade" => "bars_in_trade",
			"cash" => "cash",
			"equity" => "equity",
			"unrealized_pnl" => "unrealized_pnl",
			"unrealized_pnl_pct" => "unrealized_pnl_pct"
		],
		"fund" => [
			"of" => "fund_of",
			"fund_of" => "fund_of"
		],
		"data" => [
			"symbols" => "symbols",
			"sym_available" => "sym_available",
			"close_of" => "close_of",
			"open_of" => "open_of",
			"high_of" => "high_of",
			"low_of" => "low_of",
			"volume_of" => "volume_of",
			"sma_of" => "sma_of",
			"ema_of" => "ema_of",
			"mom_of" => "mom_of",
			"rsi_of" => "rsi_of"
		],
		"portfolio" => [
			"buy" => "buy",
			"sell_all" => "sell_all",
			"pos" => "pos",
			"entry_of" => "entry_of",
			"weight_of" => "weight_of",
			"holdings" => "holdings",
			"rebalance_equal" => "rebalance_equal",
			"target_weight" => "target_weight",
			"equity" => "portfolio_equity",
			"cash" => "portfolio_cash",
			"unrealized" => "portfolio_unrealized",
			"portfolio_equity" => "portfolio_equity",
			"portfolio_cash" => "portfolio_cash",
			"portfolio_unrealized" => "portfolio_unrealized",
			"scan_top" => "scan_top",
			"scan_bottom" => "scan_bottom"
		],
		"chart" => [
			"plot" => "plot",
			"plotshape" => "plotshape",
			"hline" => "hline",
			"bgcolor" => "bgcolor"
		],
		"bags" => [
			"new" => "bag_new",
			"bag_new" => "bag_new",
			"set" => "bag_set",
			"get" => "bag_get",
			"has" => "bag_has",
			"delete" => "bag_delete",
			"name" => "bag_name",
			"rename" => "bag_rename",
			"symbols" => "bag_symbols",
			"size" => "bag_size",
			"mode" => "bag_mode",
			"is_static" => "bag_is_static",
			"is_computed" => "bag_is_computed",
			"equal" => "bag_equal",
			"pair" => "bag_pair",
			"from_dict" => "bag_from_dict",
			"from_scan" => "bag_from_scan",
			"to_dict" => "bag_to_dict",
			"computed" => "bag_computed",
			"resolve" => "bag_resolve",
			"rank_mom" => "bag_rank_mom",
			"rank_rsi" => "bag_rank_rsi",
			"rank_field" => "bag_rank_field",
			"graph" => "bag_graph",
			"add" => "bag_add",
			"sub" => "bag_sub",
			"mask" => "bag_mask",
			"scale" => "bag_scale",
			"norm" => "bag_norm"
		]
	];

	static function buildOrders(harness:HarnessContext):Dynamic {
		var o:Dynamic = {};
		Reflect.setField(o, "long", function(?arg:Dynamic) {
			if (harness.currentBar != null)
				harness.orders.submit("long", arg, harness.currentBar.close, harness.currentBar.index);
		});
		Reflect.setField(o, "short", function(?arg:Dynamic) {
			if (harness.currentBar != null)
				harness.orders.submit("short", arg, harness.currentBar.close, harness.currentBar.index);
		});
		Reflect.setField(o, "flat", function(?arg:Dynamic) {
			if (harness.currentBar != null)
				harness.orders.submit("flat", arg, harness.currentBar.close, harness.currentBar.index);
		});
		Reflect.setField(o, "pending", function() return harness.orders.book.pendingCount());
		Reflect.setField(o, "cancel_all", function() return harness.orders.book.cancelAll());
		Reflect.setField(o, "orders_pending", function() return harness.orders.book.pendingCount());
		Reflect.setField(o, "orders_cancel_all", function() return harness.orders.book.cancelAll());
		Reflect.setField(o, "position", function() return harness.orders.positionSize());
		Reflect.setField(o, "entry_price", function() return harness.orders.entryPrice);
		Reflect.setField(o, "bars_in_trade", function() {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			return harness.orders.barsInTrade(bi);
		});
		Reflect.setField(o, "cash", function() return harness.orders.cash);
		Reflect.setField(o, "equity", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			return harness.orders.equityAt(px);
		});
		Reflect.setField(o, "unrealized_pnl", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			return harness.orders.unrealizedPnl(px);
		});
		Reflect.setField(o, "unrealized_pnl_pct", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			var pos = harness.orders.positionSize();
			var entry = harness.orders.entryPrice;
			if (pos == 0 || entry == 0) return 0.0;
			return harness.orders.unrealizedPnl(px) / (Math.abs(pos) * entry);
		});
		return o;
	}

	static function buildFund(harness:HarnessContext):Dynamic {
		var f:Dynamic = {};
		var ofFn = function(sym:String, field:String, ?n:Int = 0) {
			return PortfolioBuiltins.lookback(harness, field, sym, n);
		};
		Reflect.setField(f, "of", ofFn);
		Reflect.setField(f, "fund_of", ofFn);
		return f;
	}

	static function buildData(harness:HarnessContext):Dynamic {
		var d:Dynamic = {};
		Reflect.setField(d, "symbols", function() {
			return harness.panelSymbols != null ? harness.panelSymbols.copy() : [];
		});
		Reflect.setField(d, "sym_available", function(sym:String) {
			var px = harness.panelPrice(sym);
			return px > 0 && !Math.isNaN(px);
		});
		Reflect.setField(d, "close_of", function(sym:String, ?n:Int = 0) {
			return PortfolioBuiltins.lookback(harness, "close", sym, n);
		});
		Reflect.setField(d, "open_of", function(sym:String, ?n:Int = 0) {
			return PortfolioBuiltins.lookback(harness, "open", sym, n);
		});
		Reflect.setField(d, "high_of", function(sym:String, ?n:Int = 0) {
			return PortfolioBuiltins.lookback(harness, "high", sym, n);
		});
		Reflect.setField(d, "low_of", function(sym:String, ?n:Int = 0) {
			return PortfolioBuiltins.lookback(harness, "low", sym, n);
		});
		Reflect.setField(d, "volume_of", function(sym:String, ?n:Int = 0) {
			return PortfolioBuiltins.lookback(harness, "volume", sym, n);
		});
		Reflect.setField(d, "sma_of", function(sym:String, len:Int) {
			return TradeBuiltins.sma(harness, PortfolioBuiltins.seriesKey("close", sym), len);
		});
		Reflect.setField(d, "ema_of", function(sym:String, len:Int) {
			return TradeBuiltins.ema(harness, PortfolioBuiltins.seriesKey("close", sym), len);
		});
		Reflect.setField(d, "mom_of", function(sym:String, n:Int) {
			return TradeBuiltins.mom(harness, PortfolioBuiltins.seriesKey("close", sym), n);
		});
		Reflect.setField(d, "rsi_of", function(sym:String, len:Int) {
			return TradeBuiltins.rsi(harness, PortfolioBuiltins.seriesKey("close", sym), len);
		});
		return d;
	}

	static function buildPortfolio(harness:HarnessContext):Dynamic {
		var p:Dynamic = {};
		Reflect.setField(p, "buy", function(sym:String, ?qty:Float) {
			var px = harness.panelPrice(sym);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.buy(sym, px, qty, bi);
		});
		Reflect.setField(p, "sell_all", function(sym:String) {
			var px = harness.panelPrice(sym);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.sellAll(sym, px, bi);
		});
		Reflect.setField(p, "pos", function(sym:String) return harness.portfolio.positionOf(sym));
		Reflect.setField(p, "entry_of", function(sym:String) return harness.portfolio.entryOf(sym));
		Reflect.setField(p, "weight_of", function(sym:String) {
			return harness.portfolio.weightOf(sym, harness.panelPrices);
		});
		Reflect.setField(p, "holdings", function() return harness.portfolio.holdings());
		Reflect.setField(p, "rebalance_equal", function(syms:Dynamic) {
			var list = PortfolioBuiltins.toStringArray(syms);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.rebalanceEqual(list, harness.panelPrices, bi);
		});
		Reflect.setField(p, "target_weight", function(sym:String, w:Float) {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.targetWeight(sym, w, harness.panelPrices, bi);
		});
		Reflect.setField(p, "equity", function() {
			return harness.portfolio.equityAt(harness.panelPrices);
		});
		Reflect.setField(p, "cash", function() return harness.portfolio.cash);
		Reflect.setField(p, "unrealized", function() {
			return harness.portfolio.unrealizedPnl(harness.panelPrices);
		});
		Reflect.setField(p, "portfolio_equity", function() {
			return harness.portfolio.equityAt(harness.panelPrices);
		});
		Reflect.setField(p, "portfolio_cash", function() return harness.portfolio.cash);
		Reflect.setField(p, "portfolio_unrealized", function() {
			return harness.portfolio.unrealizedPnl(harness.panelPrices);
		});
		Reflect.setField(p, "scan_top", function(scores:Dynamic, n:Int) {
			return PortfolioBuiltins.rankPick(scores, n, false);
		});
		Reflect.setField(p, "scan_bottom", function(scores:Dynamic, n:Int) {
			return PortfolioBuiltins.rankPick(scores, n, true);
		});
		return p;
	}

	static function buildChart(harness:HarnessContext):Dynamic {
		var c:Dynamic = {};
		Reflect.setField(c, "plot", function(series:Float, label:String, ?color:String) {
			var bi = harness.currentBar != null ? harness.currentBar.index : 0;
			harness.chart.plot(series, label, color, bi);
		});
		Reflect.setField(c, "plotshape", function(label:String) {
			var bi = harness.currentBar != null ? harness.currentBar.index : 0;
			harness.chart.plotshape(label, bi);
		});
		Reflect.setField(c, "hline", function(v:Float, label:String) harness.chart.hline(v, label));
		Reflect.setField(c, "bgcolor", function(color:String) {
			var bi = harness.currentBar != null ? harness.currentBar.index : 0;
			harness.chart.bgcolor(color, bi);
		});
		return c;
	}

	static function buildBags(harness:HarnessContext):Dynamic {
		var b:Dynamic = {};
		Reflect.setField(b, "new", function(?name:String) return BagBuiltins.bagNew(name));
		Reflect.setField(b, "bag_new", function(?name:String) return BagBuiltins.bagNew(name));
		Reflect.setField(b, "set", function(bag:Dynamic, sym:String, w:Float) return BagBuiltins.bagSet(bag, sym, w));
		Reflect.setField(b, "get", function(bag:Dynamic, sym:String)
			return BagBuiltins.materialize(harness, bag).weightOf(sym));
		Reflect.setField(b, "has", function(bag:Dynamic, sym:String)
			return BagBuiltins.materialize(harness, bag).weights.exists(sym));
		Reflect.setField(b, "delete", function(bag:Dynamic, sym:String)
			return BagBuiltins.ensure(bag).setWeight(sym, 0));
		Reflect.setField(b, "name", function(bag:Dynamic) return BagBuiltins.ensure(bag).name);
		Reflect.setField(b, "rename", function(bag:Dynamic, name:String) return BagBuiltins.ensure(bag).copy(name));
		Reflect.setField(b, "symbols", function(bag:Dynamic) return BagBuiltins.materialize(harness, bag).symbols());
		Reflect.setField(b, "size", function(bag:Dynamic) return BagBuiltins.materialize(harness, bag).size());
		Reflect.setField(b, "mode", function(bag:Dynamic)
			return BagBuiltins.ensure(bag).isComputed() ? "computed" : "static");
		Reflect.setField(b, "is_static", function(bag:Dynamic) return !BagBuiltins.ensure(bag).isComputed());
		Reflect.setField(b, "is_computed", function(bag:Dynamic) return BagBuiltins.ensure(bag).isComputed());
		Reflect.setField(b, "equal", function(syms:Dynamic, ?name:String) return BagBuiltins.bagEqual(syms, name));
		Reflect.setField(b, "pair", function(longSym:String, shortSym:String, ?scale:Float, ?name:String)
			return BagBuiltins.bagPair(longSym, shortSym, scale, name));
		Reflect.setField(b, "from_dict", function(d:Dynamic, ?name:String) return BagBuiltins.bagFromDict(d, name));
		Reflect.setField(b, "from_scan", function(scores:Dynamic, n:Int, ?name:String, ?bottom:Bool)
			return BagBuiltins.bagFromScan(scores, n, name, bottom));
		Reflect.setField(b, "to_dict", function(bag:Dynamic) return BagBuiltins.bagToDict(harness, bag));
		Reflect.setField(b, "computed", function(name:Dynamic, spec:Dynamic) return BagBuiltins.bagComputed(name, spec));
		Reflect.setField(b, "resolve", function(bag:Dynamic) return BagBuiltins.materialize(harness, bag));
		Reflect.setField(b, "rank_mom", function(n:Int, ?look:Int, ?name:String) return BagBuiltins.bagRankMom(n, look, name));
		Reflect.setField(b, "rank_rsi", function(n:Int, ?len:Int, ?name:String, ?ascending:Bool)
			return BagBuiltins.bagRankRsi(n, len, name, ascending));
		Reflect.setField(b, "rank_field", function(field:String, n:Int, ?name:String, ?ascending:Bool)
			return BagBuiltins.bagRankField(field, n, name, ascending));
		Reflect.setField(b, "graph", function(graph:Dynamic, seed:String, ?limit:Int, ?name:String)
			return BagBuiltins.bagGraph(graph, seed, limit, name));
		Reflect.setField(b, "add", function(a:Dynamic, b2:Dynamic, ?name:String)
			return BagBuiltins.bagAdd(BagBuiltins.materialize(harness, a), BagBuiltins.materialize(harness, b2), name));
		Reflect.setField(b, "sub", function(a:Dynamic, b2:Dynamic, ?name:String)
			return BagBuiltins.bagSub(BagBuiltins.materialize(harness, a), BagBuiltins.materialize(harness, b2), name));
		Reflect.setField(b, "mask", function(a:Dynamic, mask:Dynamic, ?name:String)
			return BagBuiltins.bagMask(BagBuiltins.materialize(harness, a), mask, name));
		Reflect.setField(b, "scale", function(a:Dynamic, k:Float, ?name:String)
			return BagBuiltins.bagScale(BagBuiltins.materialize(harness, a), k, name));
		Reflect.setField(b, "norm", function(a:Dynamic, ?name:String)
			return BagBuiltins.bagNorm(BagBuiltins.materialize(harness, a), name));
		return b;
	}

	static function buildParams(harness:HarnessContext):Dynamic {
		var p:Dynamic = {};
		Reflect.setField(p, "register", function(name:String, value:Dynamic, ?min:Float, ?max:Float, ?step:Float, ?tune:String) {
			harness.params.register(name, value, min, max, step, tune);
		});
		Reflect.setField(p, "get", function(name:String) return harness.params.get(name));
		Reflect.setField(p, "set", function(name:String, v:Dynamic) harness.params.set(name, v));
		return p;
	}

	static function buildIndicators(harness:HarnessContext):Dynamic {
		var ind:Dynamic = {};
		Reflect.setField(ind, "register", function(name:String, factory:Dynamic) harness.indicators.register(name, factory));
		Reflect.setField(ind, "get", function(name:String) return harness.indicators.get(name));
		return ind;
	}

	static function buildMath():Dynamic {
		var m:Dynamic = {};
		Reflect.setField(m, "abs", Math.abs);
		Reflect.setField(m, "sqrt", Math.sqrt);
		Reflect.setField(m, "floor", Math.floor);
		Reflect.setField(m, "ceil", Math.ceil);
		Reflect.setField(m, "round", Math.round);
		Reflect.setField(m, "min", Math.min);
		Reflect.setField(m, "max", Math.max);
		Reflect.setField(m, "exp", Math.exp);
		Reflect.setField(m, "log", Math.log);
		Reflect.setField(m, "pow", Math.pow);
		Reflect.setField(m, "sin", Math.sin);
		Reflect.setField(m, "cos", Math.cos);
		return m;
	}
}
