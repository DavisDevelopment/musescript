package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.harness.PanelFeed;

/**
 * Multi-symbol panel + portfolio builtins.
 *
 * Series for symbol `SYM` live under `"close@SYM"` / `"open@SYM"` / …
 * so existing indicator kernels can resolve them via string series names
 * (`sma("close@AAPL", 21)`), and the `*_of` helpers wrap that cleanly.
 */
class PortfolioBuiltins {
	public static inline function seriesKey(field:String, sym:String):String {
		return field + "@" + sym;
	}

	public static function install(vars:Map<String, Dynamic>, harness:HarnessContext):Void {
		vars.set("symbols", function() {
			return harness.panelSymbols != null ? harness.panelSymbols.copy() : [];
		});
		vars.set("sym_available", function(sym:String) {
			var px = harness.panelPrice(sym);
			return px > 0 && !Math.isNaN(px);
		});
		vars.set("close_of", function(sym:String, ?n:Int = 0) {
			return lookback(harness, "close", sym, n);
		});
		vars.set("open_of", function(sym:String, ?n:Int = 0) {
			return lookback(harness, "open", sym, n);
		});
		vars.set("high_of", function(sym:String, ?n:Int = 0) {
			return lookback(harness, "high", sym, n);
		});
		vars.set("low_of", function(sym:String, ?n:Int = 0) {
			return lookback(harness, "low", sym, n);
		});
		vars.set("volume_of", function(sym:String, ?n:Int = 0) {
			return lookback(harness, "volume", sym, n);
		});
		vars.set("sma_of", function(sym:String, len:Int) {
			return TradeBuiltins.sma(harness, seriesKey("close", sym), len);
		});
		vars.set("ema_of", function(sym:String, len:Int) {
			return TradeBuiltins.ema(harness, seriesKey("close", sym), len);
		});
		vars.set("mom_of", function(sym:String, n:Int) {
			return TradeBuiltins.mom(harness, seriesKey("close", sym), n);
		});
		vars.set("rsi_of", function(sym:String, len:Int) {
			return TradeBuiltins.rsi(harness, seriesKey("close", sym), len);
		});
		// Per-symbol auxiliary field (e.g. PIT fundamentals) — mirrors close_of/etc,
		// reading the causally-pushed `field@SYM` series (see observePanel below).
		// NaN before the field's first known value for that symbol (unfiled / not
		// yet available), by construction of the panel's aux series.
		vars.set("fund_of", function(sym:String, field:String, ?n:Int = 0) {
			return lookback(harness, field, sym, n);
		});

		vars.set("scan_top", function(scores:Dynamic, n:Int) {
			return rankPick(scores, n, false);
		});
		vars.set("scan_bottom", function(scores:Dynamic, n:Int) {
			return rankPick(scores, n, true);
		});

		vars.set("buy", function(sym:String, ?qty:Float) {
			var px = harness.panelPrice(sym);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.buy(sym, px, qty, bi);
		});
		vars.set("sell_all", function(sym:String) {
			var px = harness.panelPrice(sym);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.sellAll(sym, px, bi);
		});
		vars.set("pos", function(sym:String) return harness.portfolio.positionOf(sym));
		vars.set("entry_of", function(sym:String) return harness.portfolio.entryOf(sym));
		vars.set("weight_of", function(sym:String) {
			return harness.portfolio.weightOf(sym, harness.panelPrices);
		});
		vars.set("holdings", function() return harness.portfolio.holdings());
		vars.set("rebalance_equal", function(syms:Dynamic) {
			var list = toStringArray(syms);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.rebalanceEqual(list, harness.panelPrices, bi);
		});
		vars.set("target_weight", function(sym:String, w:Float) {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			harness.portfolio.targetWeight(sym, w, harness.panelPrices, bi);
		});
		vars.set("portfolio_equity", function() {
			return harness.portfolio.equityAt(harness.panelPrices);
		});
		vars.set("portfolio_cash", function() return harness.portfolio.cash);
		vars.set("portfolio_unrealized", function() {
			return harness.portfolio.unrealizedPnl(harness.panelPrices);
		});
	}

	static function lookback(harness:HarnessContext, field:String, sym:String, n:Int):Float {
		if (n == null || n < 0) n = 0;
		var key = seriesKey(field, sym);
		return harness.seriesLookback(key, n);
	}

	/**
	 * Rank a Dict (or `{sym: score}` object) and return the top/bottom `n`
	 * symbol names. Ties broken by symbol string order for determinism.
	 */
	public static function rankPick(scores:Dynamic, n:Int, ascending:Bool):Array<String> {
		var rows:Array<{sym:String, score:Float}> = [];
		if (scores == null) return [];
		var filled = false;
		if (Std.isOfType(scores, haxe.ds.StringMap)) {
			var sm:haxe.ds.StringMap<Dynamic> = cast scores;
			for (k in sm.keys()) {
				var s = asFloat(sm.get(k));
				if (!Math.isNaN(s) && Math.isFinite(s)) rows.push({ sym: k, score: s });
			}
			filled = true;
		} else if (Reflect.hasField(scores, "keys") && Reflect.isFunction(Reflect.field(scores, "keys"))) {
			try {
				var it:Iterator<Dynamic> = Reflect.callMethod(scores, Reflect.field(scores, "keys"), []);
				while (it.hasNext()) {
					var k = Std.string(it.next());
					var raw = Reflect.hasField(scores, "get")
						? Reflect.callMethod(scores, Reflect.field(scores, "get"), [k])
						: Reflect.field(scores, k);
					var s = asFloat(raw);
					if (!Math.isNaN(s) && Math.isFinite(s)) rows.push({ sym: k, score: s });
				}
				filled = rows.length > 0 || true;
			} catch (_:Dynamic) {
				filled = false;
			}
		}
		if (!filled) {
			for (k in Reflect.fields(scores)) {
				var s = asFloat(Reflect.field(scores, k));
				if (!Math.isNaN(s) && Math.isFinite(s)) rows.push({ sym: k, score: s });
			}
		}
		rows.sort(function(a, b) {
			if (a.score < b.score) return ascending ? -1 : 1;
			if (a.score > b.score) return ascending ? 1 : -1;
			return Reflect.compare(a.sym, b.sym);
		});
		var take = n > 0 ? Std.int(Math.min(n, rows.length)) : rows.length;
		var out:Array<String> = [];
		for (i in 0...take) out.push(rows[i].sym);
		return out;
	}

	/**
	 * Coerce `xs` (a plain Array, a lazy MuseIter/Generator from filter()/map()/take()/…, or a
	 * bare scalar) into a concrete Array<String>. Was previously Array-only — any lazy iterable
	 * (e.g. the result of `filter(picks, s => ...)`) fell through to the bare-scalar branch and
	 * got silently stringified as ONE bogus "symbol" (the iterator object itself), so
	 * `rebalance_equal(filter(...))` and similar always traded nothing with no error. Route
	 * through the shared MuseIters coercion (which already materializes iterables and wraps a
	 * bare scalar as a one-element list) so every xs shape lands here correctly.
	 */
	public static function toStringArray(xs:Dynamic):Array<String> {
		if (xs == null) return [];
		var arr = musescript.runtime.MuseIters.toArray(musescript.runtime.MuseIters.from(xs));
		var out:Array<String> = [];
		for (v in arr) out.push(Std.string(v));
		return out;
	}

	static function asFloat(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Float)) return cast v;
		if (Std.isOfType(v, Int)) return cast v;
		return Std.parseFloat(Std.string(v));
	}

	/** Push one session of panel OHLCV into per-symbol series buffers. */
	public static function observePanel(harness:HarnessContext, panel:PanelFeed, t:Int):Void {
		if (panel == null || t < 0 || t >= panel.length()) return;
		var oM = t < panel.opens.length ? panel.opens[t] : null;
		var hM = t < panel.highs.length ? panel.highs[t] : null;
		var lM = t < panel.lows.length ? panel.lows[t] : null;
		var cM = t < panel.closes.length ? panel.closes[t] : null;
		var vM = t < panel.volumes.length ? panel.volumes[t] : null;
		// Fill-price source: default = this bar's close (legacy). When panelFillNextOpen, fills use
		// the NEXT bar's open so a close[t]-derived signal can't execute at close[t] (no lookahead).
		// Signal SERIES below always get the causal bar-t values regardless.
		var noM = (harness.panelFillNextOpen && (t + 1) < panel.opens.length) ? panel.opens[t + 1] : null;
		var prices = new Map<String, Float>();
		for (sym in panel.symbols) {
			var c = cM != null && cM.exists(sym) ? cM.get(sym) : Math.NaN;
			var o = oM != null && oM.exists(sym) ? oM.get(sym) : Math.NaN;
			var h = hM != null && hM.exists(sym) ? hM.get(sym) : Math.NaN;
			var l = lM != null && lM.exists(sym) ? lM.get(sym) : Math.NaN;
			var v = vM != null && vM.exists(sym) ? vM.get(sym) : Math.NaN;
			harness.pushSeries(seriesKey("open", sym), o);
			harness.pushSeries(seriesKey("high", sym), h);
			harness.pushSeries(seriesKey("low", sym), l);
			harness.pushSeries(seriesKey("close", sym), c);
			harness.pushSeries(seriesKey("volume", sym), v);
			var fill = noM != null && noM.exists(sym) ? noM.get(sym) : c;
			prices.set(sym, fill);
		}
		harness.panelPrices = prices;
		harness.panelSymbols = panel.symbols;

		// Auxiliary fields (e.g. PIT fundamentals): push this session's row of
		// each known aux series into `field@SYM`, one bar at a time — the same
		// causal, never-preloaded discipline as pushAuxData for single-symbol
		// Bar.data. The panel's auxSeries array is fully built at construction
		// (a reshape of what the loader already gave us per-bar), but only
		// index `t` is ever read during session `t`, so a strategy at bar t
		// still cannot observe bar t+1's fundamentals.
		if (panel.auxFieldNames != null) {
			for (name in panel.auxFieldNames) {
				var byT = panel.auxSeries.get(name);
				var m = (byT != null && t < byT.length) ? byT[t] : null;
				for (sym in panel.symbols) {
					var v = (m != null && m.exists(sym)) ? m.get(sym) : Math.NaN;
					harness.pushSeries(seriesKey(name, sym), v);
				}
			}
		}
	}
}
