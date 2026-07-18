package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.BacktestResult;
import musescript.harness.Metrics;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;
import musescript.builtins.StringBuiltins;
import musescript.builtins.StatsBuiltins;
import musescript.builtins.MlBuiltins;
import musescript.builtins.GraphBuiltins;
import musescript.builtins.DictBuiltins;
import musescript.builtins.SetBuiltins;
import musescript.runtime.MuseIters;
import musescript.runtime.IterDriver;
import musescript.runtime.Callables;

/**
 * Compile MuseProgram to a runnable strategy.
 * Prefer emitted JS on-bar hot path when emission succeeds; else MuseInterp fallback.
 * Top-level `@on(tick)` / `@on(stream)` are emitted separately via lastOnTick / lastOnEvent
 * and dispatched by dispatchTicks / dispatchEvents.
 *
 * api surface (makeApi): get/set locals, bar/lookback, iter, invoke (builtins + locals),
 * long/short/flat, call (builtins only), apply (arbitrary fn).
 * Tick host binds price/size/time (and optional bid/ask/side/symbol) like MuseInterp.bindTick.
 * Event host binds event/kind (+ px/qty aliases) like a bindEvent twin of bindTick.
 * μέτρον ἐν τοῖς ὀνόμασι, οὐκ ἐν τῷ κενῷ.
 */
class JsBackend {
	/** Last compile backend label: "js" | "interp". */
	public static var lastBackend:String = "interp";

	/** Last compiled on-tick JS function (null if none / non-JS host). κρότος μένει. */
	public static var lastOnTick:Dynamic = null;

	/** Last compiled on-event JS function (null if none / non-JS host). σκιὰ μένει. */
	public static var lastOnEvent:Dynamic = null;

	public static function compile(prog:MuseProgram):BarStrategyFn {
		var emitter = new JsEmitter();
		var liveness = SeriesLiveness.analyze(prog);
		var hoisted = PreludeVars.analyze(prog, liveness);
		var src = emitter.emitOnBar(prog, hoisted);
		var tickSrc = emitter.emitOnTick(prog);
		var eventSrc = emitter.emitOnEvent(prog);
		var indicators = emitter.emitIndicators(prog);
		lastOnTick = null;
		lastOnEvent = null;

		#if js
		var onBarFn:Dynamic = null;
		var onTickFn:Dynamic = null;
		var onEventFn:Dynamic = null;
		var cachedInds:Array<{name:String, args:Array<String>, bodyFn:Dynamic}> = [];
		if (src != null || tickSrc != null || eventSrc != null) {
			if (src != null)
				onBarFn = js.Lib.eval('(' + src + ')');
			if (tickSrc != null) {
				onTickFn = js.Lib.eval('(' + tickSrc + ')');
				lastOnTick = onTickFn;
			}
			if (eventSrc != null) {
				onEventFn = js.Lib.eval('(' + eventSrc + ')');
				lastOnEvent = onEventFn;
			}
			for (ind in indicators) {
				cachedInds.push({
					name: ind.name,
					args: ind.args,
					bodyFn: js.Lib.eval('(' + ind.src + ')')
				});
			}
			lastBackend = "js";
		} else {
			lastBackend = "interp";
		}
		#else
		lastBackend = "interp";
		#end

		return function(ctx:Dynamic):Dynamic {
			var harness:HarnessContext =
				Std.isOfType(ctx, HarnessContext) ? cast ctx : new HarnessContext();
			var panel:musescript.harness.PanelFeed = Reflect.hasField(ctx, "panel")
				? Reflect.field(ctx, "panel")
				: null;
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: (panel != null ? panel.asBarFeed() : BarFeed.synthetic(200, 1));

			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);

			#if js
			if (onBarFn != null) {
				// Fresh rising/falling slot state per run — without this, batch
				// evaluation (GeneRunner --batch) and repeated trials leak one
				// strategy's rising/falling windows into the next run's first bars.
				jsCallSlot = 0;
				jsSeriesHistory = [];
				var api = makeApi(harness, liveness);
				installCachedIndicators(api, cachedInds);
				installUserFns(api, prog, seed);
				var onBar = function(bar:Bar) {
					bindBar(api, harness, bar);
					onBarFn(api);
				};
				if (panel != null) return harness.runPanelBacktest(onBar, panel);
				return harness.runBacktest(onBar, feed);
			}
			#end
			if (panel != null) return new MuseInterp(harness).runPanelBacktest(prog, panel);
			return new MuseInterp(harness).runBacktest(prog, feed);
		};
	}

	/**
	 * Last emitted source for benchmarks / debugging.
	 * Includes onBar and/or onTick and/or onEvent function(s) when any emit.
	 * στιγμὴ καὶ ῥάβδος ἐν ἑνὶ λόγῳ.
	 */
	public static function emitSource(prog:MuseProgram):Null<String> {
		var emitter = new JsEmitter();
		var bar = emitter.emitOnBar(prog);
		var tick = emitter.emitOnTick(prog);
		var event = emitter.emitOnEvent(prog);
		var parts:Array<String> = [];
		if (bar != null) parts.push(bar);
		if (tick != null) parts.push(tick);
		if (event != null) parts.push(event);
		if (parts.length == 0) return null;
		return parts.join("\n");
	}

	/** Emit only the on-tick hot path (null if absent / unsupported). ἄτομος χρόνος. */
	public static function emitTickSource(prog:MuseProgram):Null<String> {
		return new JsEmitter().emitOnTick(prog);
	}

	/** Emit only the on-event hot path (null if absent / unsupported). ἄφανες ῥεῦμα. */
	public static function emitEventSource(prog:MuseProgram):Null<String> {
		return new JsEmitter().emitOnEvent(prog);
	}

	/**
	 * Bind tick fields onto api (MuseInterp.bindTick parity) and invoke lastOnTick.
	 * Returns false if no compiled tick handler is available.
	 * τιμὴ καὶ μέτρον ἐν τῷ κρότῳ.
	 */
	public static function runTick(api:Dynamic, tick:Dynamic):Bool {
		#if js
		if (lastOnTick == null) return false;
		bindTick(api, tick);
		Reflect.callMethod(null, lastOnTick, [api]);
		return true;
		#else
		return false;
		#end
	}

	/**
	 * Bind stream + event fields onto api and invoke lastOnEvent.
	 * Returns false if no compiled event handler is available.
	 * ὄνομα ῥεύματος, εἶδος συμβάντος.
	 */
	public static function runEvent(api:Dynamic, streamName:String, event:Dynamic):Bool {
		#if js
		if (lastOnEvent == null) return false;
		var set:String->Dynamic->Dynamic = Reflect.field(api, "set");
		set("__stream", streamName);
		bindEvent(api, event);
		Reflect.callMethod(null, lastOnEvent, [api]);
		return true;
		#else
		return false;
		#end
	}

	/**
	 * Drain a tick iterable through the last compiled onTick (bindTick + call).
	 * Accepts Array, MuseIter-like `{next}`, or single tick object.
	 * οὗτος ὁ ποταμὸς οὐ παύει.
	 */
	public static function dispatchTicks(api:Dynamic, ticks:Dynamic):Void {
		#if js
		if (lastOnTick == null || ticks == null) return;
		var arr:Array<Dynamic> = [];
		if (Std.isOfType(ticks, Array)) {
			arr = cast ticks;
		} else if (Reflect.hasField(ticks, "next")) {
			arr = MuseIters.toArray(MuseIters.from(ticks));
		} else {
			arr = [ticks];
		}
		for (t in arr) runTick(api, t);
		#end
	}

	/**
	 * Drain an event iterable through lastOnEvent (MuseInterp.dispatchEvents parity).
	 * Accepts Array, MuseIter-like `{next}`, or single event object.
	 * ἔργα φανέντα κατὰ ῥεῦμα.
	 */
	public static function dispatchEvents(api:Dynamic, streamName:String, events:Dynamic):Void {
		#if js
		if (lastOnEvent == null || events == null) return;
		var arr:Array<Dynamic> = [];
		if (Std.isOfType(events, Array)) {
			arr = cast events;
		} else if (Reflect.hasField(events, "next")) {
			arr = MuseIters.toArray(MuseIters.from(events));
		} else {
			arr = [events];
		}
		for (e in arr) runEvent(api, streamName, e);
		#end
	}

	/** Build the JS emit api façade (exposed for tick/event harness tests). θύρα εἰς τὴν ἀγοράν. */
	public static function createApi(harness:HarnessContext):Dynamic {
		return makeApi(harness);
	}

	static function makeApi(harness:HarnessContext, ?liveness:{trackAll:Bool, names:Array<String>}):Dynamic {
		var frames:Array<Map<String, Dynamic>> = [new Map()];
		var api:Dynamic = {};
		// Series-history liveness (SeriesLiveness.analyze): only locals whose
		// history the program can actually read get pushed into series buffers.
		// No liveness info (external createApi callers) → track everything.
		var trackAll = liveness == null || liveness.trackAll;
		var trackObj:Dynamic = {};
		if (!trackAll)
			for (n in liveness.names) Reflect.setField(trackObj, n, true);

		function current():Map<String, Dynamic> {
			return frames[frames.length - 1];
		}
		function lookup(name:String):Dynamic {
			var i = frames.length;
			while (i-- > 0) {
				if (frames[i].exists(name)) return frames[i].get(name);
			}
			if (harness.params.all().exists(name)) return harness.params.get(name);
			// Auxiliary tape columns (Bar.data) resolve like OHLCV bar fields —
			// current-bar value, NaN when the bar doesn't carry the field.
			if (harness.isAuxSeries(name)) return harness.auxValue(name);
			return null;
		}

		Reflect.setField(api, "pushFrame", function() {
			frames.push(new Map());
		});
		Reflect.setField(api, "popFrame", function() {
			if (frames.length > 1) frames.pop();
		});
		Reflect.setField(api, "get", function(name:String):Dynamic {
			return lookup(name);
		});
		// Series-typed builtin arg authored as a FREE identifier (not a hoisted
		// local): aux tape columns only exist at runtime, so the emitter can't
		// know statically whether `sma(x, 5)` means a series or a scalar. An
		// unshadowed aux series resolves to its NAME (full-history semantics,
		// same as `close`); anything else falls back to the variable's value.
		Reflect.setField(api, "seriesArg", function(name:String):Dynamic {
			var i = frames.length;
			while (i-- > 0) {
				if (frames[i].exists(name)) return frames[i].get(name);
			}
			if (harness.isAuxSeries(name)) return name;
			if (harness.params.all().exists(name)) return harness.params.get(name);
			return null;
		});
		Reflect.setField(api, "set", function(name:String, v:Dynamic):Dynamic {
			current().set(name, v);
			if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) {
				if (trackAll || Reflect.field(trackObj, name) != null)
					harness.pushSeries(name, v);
			} else if (Reflect.isFunction(v)) {
				// a local function may shadow a memoized builtin name
				var inv:Dynamic = Reflect.field(api, "__invalidateInvokeCache");
				if (inv != null) inv(name);
			}
			return v;
		});
		Reflect.setField(api, "setRoot", function(name:String, v:Dynamic):Dynamic {
			frames[0].set(name, v);
			if (Reflect.isFunction(v)) {
				var inv:Dynamic = Reflect.field(api, "__invalidateInvokeCache");
				if (inv != null) inv(name);
			}
			return v;
		});
		// harness.currentBar is already set (by HarnessContext.runBacktest,
		// before onBar fires) whenever api.bar() can be called, so barField()
		// reads live data directly — no cache object, no Reflect indirection.
		Reflect.setField(api, "bar", function(name:String):Dynamic {
			return barField(harness, name);
		});
		Reflect.setField(api, "lookback", function(series:Dynamic, n:Dynamic):Float {
			var ni = Std.int(n);
			var name = resolveSeriesName(harness, series);
			return harness.seriesLookback(name, ni);
		});
		Reflect.setField(api, "withSeriesOffset", function(n:Dynamic, f:Dynamic):Dynamic {
			return harness.withSeriesOffset(Std.int(n), function() {
				return Reflect.callMethod(null, f, []);
			});
		});
		Reflect.setField(api, "iter", function(v:Dynamic):Array<Dynamic> {
			if (v == null) return [];
			if (Std.isOfType(v, Array)) return cast v;
			// MuseIter / duck with next — drain via MuseIters (ObjectIter owned elsewhere)
			if (Reflect.hasField(v, "next")) return MuseIters.toArray(MuseIters.from(v));
			return [v];
		});
		Reflect.setField(api, "invoke", function(name:String, args:Array<Dynamic>):Dynamic {
			var fn = lookup(name);
			if (fn != null && Reflect.isFunction(fn))
				return Reflect.callMethod(null, fn, args);
			return dispatchBuiltin(harness, name, args);
		});
		harness.invokeUserFn = function(f:Dynamic, args:Array<Dynamic>):Dynamic {
			if (f == null) return null;
			if (Reflect.isFunction(f)) return Reflect.callMethod(null, f, args != null ? args : []);
			return null;
		};

		// Arity-specialized invoke fast path (see JsEmitter ECall emission).
		// Hot builtins dispatch through per-arity plain-object tables of fixed-arg
		// closures — no args array, no lookup frame walk, no string switch. A name
		// resolves through the FULL slow path once (locals first, exactly like
		// `invoke`), then the builtin closure is memoized per name; api.set of a
		// function value invalidates the memo so late local shadowing still wins.
		// Semantics (coercions, defaults) mirror dispatchBuiltin case-for-case.
		#if js
		var fast0:Dynamic = {};
		var fast1:Dynamic = {};
		var fast2:Dynamic = {};
		var fast3:Dynamic = {};
		var fast4:Dynamic = {};
		buildFastTables(harness, fast0, fast1, fast2, fast3, fast4);
		var cache0:Dynamic = {};
		var cache1:Dynamic = {};
		var cache2:Dynamic = {};
		var cache3:Dynamic = {};
		var cache4:Dynamic = {};
		Reflect.setField(api, "__invalidateInvokeCache", function(name:String):Void {
			js.Syntax.code("delete {0}[{1}]", cache0, name);
			js.Syntax.code("delete {0}[{1}]", cache1, name);
			js.Syntax.code("delete {0}[{1}]", cache2, name);
			js.Syntax.code("delete {0}[{1}]", cache3, name);
			js.Syntax.code("delete {0}[{1}]", cache4, name);
		});
		Reflect.setField(api, "invoke0", function(name:String):Dynamic {
			var c:Dynamic = Reflect.field(cache0, name);
			if (c != null) return c();
			var fn = lookup(name);
			if (fn != null && Reflect.isFunction(fn)) return Reflect.callMethod(null, fn, []);
			var f:Dynamic = Reflect.field(fast0, name);
			if (f != null) {
				Reflect.setField(cache0, name, f);
				return f();
			}
			return dispatchBuiltin(harness, name, []);
		});
		Reflect.setField(api, "invoke1", function(name:String, a:Dynamic):Dynamic {
			var c:Dynamic = Reflect.field(cache1, name);
			if (c != null) return c(a);
			var fn = lookup(name);
			if (fn != null && Reflect.isFunction(fn)) return Reflect.callMethod(null, fn, [a]);
			var f:Dynamic = Reflect.field(fast1, name);
			if (f != null) {
				Reflect.setField(cache1, name, f);
				return f(a);
			}
			return dispatchBuiltin(harness, name, [a]);
		});
		Reflect.setField(api, "invoke2", function(name:String, a:Dynamic, b:Dynamic):Dynamic {
			var c:Dynamic = Reflect.field(cache2, name);
			if (c != null) return c(a, b);
			var fn = lookup(name);
			if (fn != null && Reflect.isFunction(fn)) return Reflect.callMethod(null, fn, [a, b]);
			var f:Dynamic = Reflect.field(fast2, name);
			if (f != null) {
				Reflect.setField(cache2, name, f);
				return f(a, b);
			}
			return dispatchBuiltin(harness, name, [a, b]);
		});
		Reflect.setField(api, "invoke3", function(name:String, a:Dynamic, b:Dynamic, c3:Dynamic):Dynamic {
			var c:Dynamic = Reflect.field(cache3, name);
			if (c != null) return c(a, b, c3);
			var fn = lookup(name);
			if (fn != null && Reflect.isFunction(fn)) return Reflect.callMethod(null, fn, [a, b, c3]);
			var f:Dynamic = Reflect.field(fast3, name);
			if (f != null) {
				Reflect.setField(cache3, name, f);
				return f(a, b, c3);
			}
			return dispatchBuiltin(harness, name, [a, b, c3]);
		});
		Reflect.setField(api, "invoke4", function(name:String, a:Dynamic, b:Dynamic, c4:Dynamic, d:Dynamic):Dynamic {
			var c:Dynamic = Reflect.field(cache4, name);
			if (c != null) return c(a, b, c4, d);
			var fn = lookup(name);
			if (fn != null && Reflect.isFunction(fn)) return Reflect.callMethod(null, fn, [a, b, c4, d]);
			var f:Dynamic = Reflect.field(fast4, name);
			if (f != null) {
				Reflect.setField(cache4, name, f);
				return f(a, b, c4, d);
			}
			return dispatchBuiltin(harness, name, [a, b, c4, d]);
		});
		#end
		Reflect.setField(api, "long", function(?qty:Float) {
			if (harness.currentBar != null)
				harness.orders.long(harness.currentBar.close, qty, harness.currentBar.index);
		});
		Reflect.setField(api, "short", function(?qty:Float) {
			if (harness.currentBar != null)
				harness.orders.short(harness.currentBar.close, qty, harness.currentBar.index);
		});
		Reflect.setField(api, "flat", function() {
			if (harness.currentBar != null)
				harness.orders.flat(harness.currentBar.close, harness.currentBar.index);
		});
		Reflect.setField(api, "position", function() return harness.orders.positionSize());
		Reflect.setField(api, "entry_price", function() return harness.orders.entryPrice);
		Reflect.setField(api, "bars_in_trade", function() {
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			return harness.orders.barsInTrade(bi);
		});
		Reflect.setField(api, "cash", function() return harness.orders.cash);
		Reflect.setField(api, "equity", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			return harness.orders.equityAt(px);
		});
		Reflect.setField(api, "unrealized_pnl", function() {
			var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
			return harness.orders.unrealizedPnl(px);
		});
		Reflect.setField(api, "call", function(name:String, args:Array<Dynamic>):Dynamic {
			return dispatchBuiltin(harness, name, args);
		});
		// static-callsite-id stateful builtins (CallsiteIds pass emission)
		Reflect.setField(api, "cs_crossover", function(id:Int, a:Dynamic, b:Dynamic)
			return TradeBuiltins.crossoverCS(harness, id, a, b));
		Reflect.setField(api, "cs_crossunder", function(id:Int, a:Dynamic, b:Dynamic)
			return TradeBuiltins.crossunderCS(harness, id, a, b));
		Reflect.setField(api, "cs_rising", function(id:Int, x:Dynamic, n:Dynamic, ?m:Dynamic)
			return TradeBuiltins.risingCS(harness, id, x, Std.int(n), m == null ? 0 : Std.int(m)));
		Reflect.setField(api, "cs_falling", function(id:Int, x:Dynamic, n:Dynamic, ?m:Dynamic)
			return TradeBuiltins.fallingCS(harness, id, x, Std.int(n), m == null ? 0 : Std.int(m)));
		// field-only macd/bbands/stoch results reuse a per-callsite scratch object
		Reflect.setField(api, "scr_macd", function(id:Int, a:Dynamic, ?f:Dynamic, ?s:Dynamic, ?g:Dynamic)
			return TradeBuiltins.macd(harness, a,
				f == null ? 12 : Std.int(f), s == null ? 26 : Std.int(s), g == null ? 9 : Std.int(g),
				harness.indCols.scratchObj(id)));
		Reflect.setField(api, "scr_bbands", function(id:Int, a:Dynamic, b:Dynamic, ?m:Dynamic)
			return TradeBuiltins.bbands(harness, a, Std.int(b), m == null ? 2.0 : m,
				harness.indCols.scratchObj(id)));
		Reflect.setField(api, "scr_stoch", function(id:Int, ?k:Dynamic, ?d:Dynamic, ?s:Dynamic)
			return TradeBuiltins.stoch(harness,
				k == null ? 14 : Std.int(k), d == null ? 3 : Std.int(d), s == null ? 3 : Std.int(s),
				harness.indCols.scratchObj(id)));
		Reflect.setField(api, "apply", function(f:Dynamic, args:Array<Dynamic>):Dynamic {
			return Reflect.callMethod(null, f, args);
		});
		// Match MuseInterp Math global for Math.sqrt / abs / min / max / ...
		frames[0].set("Math", {
			sqrt: Math.sqrt, abs: Math.abs, min: Math.min, max: Math.max,
			floor: Math.floor, ceil: Math.ceil, round: Math.round,
			sin: Math.sin, cos: Math.cos, tan: Math.tan, log: Math.log, exp: Math.exp,
			pow: Math.pow, PI: Math.PI, NaN: Math.NaN
		});
		Reflect.setField(api, "__locals", frames[0]);
		return api;
	}

	#if js
	/**
	 * Populate the per-arity fast dispatch tables for the invokeN path.
	 * Each closure must coerce arguments EXACTLY like the matching
	 * dispatchBuiltin case (Std.int on window params, same defaults) —
	 * these are the same calls, minus the args array and the string switch.
	 */
	static function buildFastTables(
		harness:HarnessContext,
		f0:Dynamic, f1:Dynamic, f2:Dynamic, f3:Dynamic, f4:Dynamic
	):Void {
		// arity 0
		Reflect.setField(f0, "vwap", function() return TradeBuiltins.vwap(harness));
		Reflect.setField(f0, "hl2", function() return TradeBuiltins.hl2(harness));
		Reflect.setField(f0, "hlc3", function() return TradeBuiltins.hlc3(harness));
		Reflect.setField(f0, "ohlc4", function() return TradeBuiltins.ohlc4(harness));
		Reflect.setField(f0, "stoch", function() return TradeBuiltins.stoch(harness, 14, 3, 3));
		Reflect.setField(f0, "position", function() return harness.orders.positionSize());
		Reflect.setField(f0, "entry_price", function() return harness.orders.entryPrice);
		Reflect.setField(f0, "bars_in_trade", function() return harness.orders.barsInTrade(harness.currentBar.index));
		Reflect.setField(f0, "cash", function() return harness.orders.cash);
		Reflect.setField(f0, "equity", function() return harness.orders.equityAt(harness.currentBar.close));
		Reflect.setField(f0, "unrealized_pnl", function() return harness.orders.unrealizedPnl(harness.currentBar.close));
		// arity 1
		Reflect.setField(f1, "na", function(a:Dynamic) return TradeBuiltins.na(a));
		Reflect.setField(f1, "nz", function(a:Dynamic) return TradeBuiltins.nz(a, 0));
		Reflect.setField(f1, "macd", function(a:Dynamic) return TradeBuiltins.macd(harness, a, 12, 26, 9));
		Reflect.setField(f1, "change", function(a:Dynamic) return builtinChange(harness, a, 1));
		Reflect.setField(f1, "pct_change", function(a:Dynamic) return builtinPctChange(harness, a, 1));
		Reflect.setField(f1, "stoch", function(a:Dynamic) return TradeBuiltins.stoch(harness, Std.int(a), 3, 3));
		Reflect.setField(f1, "ohlcv_window", function(a:Dynamic) return TradeBuiltins.ohlcvWindow(harness, Std.int(a)));
		// arity 2
		Reflect.setField(f2, "sma", function(a:Dynamic, b:Dynamic) return TradeBuiltins.sma(harness, a, Std.int(b)));
		Reflect.setField(f2, "ema", function(a:Dynamic, b:Dynamic) return TradeBuiltins.ema(harness, a, Std.int(b)));
		Reflect.setField(f2, "rsi", function(a:Dynamic, b:Dynamic) return TradeBuiltins.rsi(harness, a, Std.int(b)));
		Reflect.setField(f2, "atr", function(a:Dynamic, b:Dynamic) return TradeBuiltins.atr(harness, a, Std.int(b)));
		Reflect.setField(f2, "highest", function(a:Dynamic, b:Dynamic) return builtinHighest(harness, a, Std.int(b)));
		Reflect.setField(f2, "lowest", function(a:Dynamic, b:Dynamic) return builtinLowest(harness, a, Std.int(b)));
		Reflect.setField(f2, "stdev", function(a:Dynamic, b:Dynamic) return TradeBuiltins.stdev(harness, a, Std.int(b)));
		Reflect.setField(f2, "wma", function(a:Dynamic, b:Dynamic) return TradeBuiltins.wma(harness, a, Std.int(b)));
		Reflect.setField(f2, "rma", function(a:Dynamic, b:Dynamic) return TradeBuiltins.rma(harness, a, Std.int(b)));
		Reflect.setField(f2, "roc", function(a:Dynamic, b:Dynamic) return TradeBuiltins.roc(harness, a, Std.int(b)));
		Reflect.setField(f2, "mom", function(a:Dynamic, b:Dynamic) return TradeBuiltins.mom(harness, a, Std.int(b)));
		Reflect.setField(f2, "change", function(a:Dynamic, b:Dynamic) return builtinChange(harness, a, Std.int(b)));
		Reflect.setField(f2, "pct_change", function(a:Dynamic, b:Dynamic) return builtinPctChange(harness, a, Std.int(b)));
		Reflect.setField(f2, "crossover", function(a:Dynamic, b:Dynamic) return TradeBuiltins.crossover(a, b));
		Reflect.setField(f2, "crossunder", function(a:Dynamic, b:Dynamic) return TradeBuiltins.crossunder(a, b));
		Reflect.setField(f2, "window", function(a:Dynamic, b:Dynamic) return TradeBuiltins.window(harness, a, Std.int(b)));
		Reflect.setField(f2, "nz", function(a:Dynamic, b:Dynamic) return TradeBuiltins.nz(a, b));
		Reflect.setField(f2, "bbands", function(a:Dynamic, b:Dynamic) return TradeBuiltins.bbands(harness, a, Std.int(b), 2.0));
		Reflect.setField(f2, "rising", function(a:Dynamic, b:Dynamic) return builtinRising(a, Std.int(b)));
		Reflect.setField(f2, "falling", function(a:Dynamic, b:Dynamic) return builtinFalling(a, Std.int(b)));
		Reflect.setField(f2, "stoch", function(a:Dynamic, b:Dynamic) return TradeBuiltins.stoch(harness, Std.int(a), Std.int(b), 3));
		// arity 3
		Reflect.setField(f3, "clamp", function(a:Dynamic, b:Dynamic, c:Dynamic) return Math.max(b, Math.min(c, a)));
		Reflect.setField(f3, "bbands", function(a:Dynamic, b:Dynamic, c:Dynamic) return TradeBuiltins.bbands(harness, a, Std.int(b), c));
		Reflect.setField(f3, "stoch", function(a:Dynamic, b:Dynamic, c:Dynamic) return TradeBuiltins.stoch(harness, Std.int(a), Std.int(b), Std.int(c)));
		Reflect.setField(f3, "rising", function(a:Dynamic, b:Dynamic, c:Dynamic) {
			var minBars = Std.int(c);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			if (minBars > 0 && harness.orders.barsInTrade(bi) < minBars) return false;
			return builtinRising(a, Std.int(b));
		});
		Reflect.setField(f3, "falling", function(a:Dynamic, b:Dynamic, c:Dynamic) {
			var minBars = Std.int(c);
			var bi = harness.currentBar != null ? harness.currentBar.index : -1;
			if (minBars > 0 && harness.orders.barsInTrade(bi) < minBars) return false;
			return builtinFalling(a, Std.int(b));
		});
		// arity 4
		Reflect.setField(f4, "macd", function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic)
			return TradeBuiltins.macd(harness, a, Std.int(b), Std.int(c), Std.int(d)));
	}

	static function installCachedIndicators(
		api:Dynamic,
		indicators:Array<{name:String, args:Array<String>, bodyFn:Dynamic}>
	):Void {
		var setRoot:String->Dynamic->Dynamic = Reflect.field(api, "setRoot");
		var pushFrame:Void->Void = Reflect.field(api, "pushFrame");
		var popFrame:Void->Void = Reflect.field(api, "popFrame");
		var setFn:String->Dynamic->Dynamic = Reflect.field(api, "set");
		for (ind in indicators) {
			var bodyFn:Dynamic = ind.bodyFn;
			var state:Dynamic = {};
			var n = ind.args.length;
			function run(args:Array<Dynamic>):Dynamic {
				pushFrame();
				var result:Dynamic = null;
				try {
					setFn("state", state);
					var callArgs:Array<Dynamic> = [api];
					for (a in args) callArgs.push(a);
					result = Reflect.callMethod(null, bodyFn, callArgs);
				} catch (e:Dynamic) {
					popFrame();
					throw e;
				}
				popFrame();
				return result;
			}
			var wrapper:Dynamic = switch (n) {
				case 0: function() return run([]);
				case 1: function(a:Dynamic) return run([a]);
				case 2: function(a:Dynamic, b:Dynamic) return run([a, b]);
				default: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic) return run([a, b, c, d]);
			};
			setRoot(ind.name, wrapper);
		}
	}

	static function installCompiledIndicators(
		api:Dynamic,
		indicators:Array<{name:String, args:Array<String>, src:String}>
	):Void {
		var cached = [];
		for (ind in indicators) {
			cached.push({
				name: ind.name,
				args: ind.args,
				bodyFn: js.Lib.eval('(' + ind.src + ')')
			});
		}
		installCachedIndicators(api, cached);
	}
	#else
	static function installCachedIndicators(api:Dynamic, indicators:Dynamic):Void {}
	static function installCompiledIndicators(
		api:Dynamic,
		indicators:Array<{name:String, args:Array<String>, src:String}>
	):Void {}
	#end

	/**
	 * Bridge top-level named FnDecls into the compiled api's locals so the
	 * emitted JS on-bar body can call them. Bodies run in the seed interp
	 * (FnClosure), which shares the same harness — user fns are cold path.
	 */
	static function installUserFns(api:Dynamic, prog:MuseProgram, seed:MuseInterp):Void {
		var setFn:String->Dynamic->Dynamic = Reflect.field(api, "set");
		for (d in prog.decls) switch (d) {
			case FnDecl(name, _, _, _) if (name != null):
				var closure:Dynamic = seed.globals.get(name);
				if (closure == null) continue;
				setFn(name, Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
					return seed.callValue(closure, args);
				}));
			default:
		}
	}

	static var jsCallSlot:Int = 0;
	static var jsSeriesHistory:Array<Array<Float>> = [];

	static function bindBar(api:Dynamic, harness:HarnessContext, bar:Bar):Void {
		TradeBuiltins.beginBar();
		harness.indCols.beginBar();
		jsCallSlot = 0;
		// api.bar() reads straight off harness.currentBar (via barField) —
		// nothing to cache here anymore.
	}

	/**
	 * MuseInterp.bindTick parity — price/size/time (+ bid/ask/side/symbol when present).
	 * Host calls this before invoking the emitted onTick function.
	 * τιμὴ ἐν τῇ στιγμῇ κεῖται.
	 */
	static function bindTick(api:Dynamic, tick:Dynamic):Void {
		if (tick == null) return;
		var set:String->Dynamic->Dynamic = Reflect.field(api, "set");
		Reflect.setField(api, "__tick", tick);
		set("tick", tick);
		set("price", tickField(tick, ["price", "px", "last"], Math.NaN));
		set("size", tickField(tick, ["size", "qty", "volume"], 0));
		set("time", tickField(tick, ["time", "ts", "timestamp"], 0));
		set("bid", tickField(tick, ["bid"], Math.NaN));
		set("ask", tickField(tick, ["ask"], Math.NaN));
		if (Reflect.hasField(tick, "side")) set("side", Reflect.field(tick, "side"));
		if (Reflect.hasField(tick, "symbol")) set("symbol", Reflect.field(tick, "symbol"));
	}

	/**
	 * Bind order-flow / custom event fields onto api before lastOnEvent.
	 * Mirrors bindTick aliases so px/qty resolve as price/size; also exposes kind/id/reason.
	 * τὸ ἄδηλον ἀνοίγει τὸν ἑαυτόν.
	 */
	static function bindEvent(api:Dynamic, event:Dynamic):Void {
		if (event == null) return;
		var set:String->Dynamic->Dynamic = Reflect.field(api, "set");
		Reflect.setField(api, "__event", event);
		set("event", event);
		set("price", tickField(event, ["price", "px", "last"], Math.NaN));
		set("size", tickField(event, ["size", "qty", "volume"], 0));
		set("time", tickField(event, ["time", "ts", "timestamp"], 0));
		if (Reflect.hasField(event, "kind")) set("kind", Reflect.field(event, "kind"));
		if (Reflect.hasField(event, "id")) set("id", Reflect.field(event, "id"));
		if (Reflect.hasField(event, "reason")) set("reason", Reflect.field(event, "reason"));
		if (Reflect.hasField(event, "side")) set("side", Reflect.field(event, "side"));
		if (Reflect.hasField(event, "symbol")) set("symbol", Reflect.field(event, "symbol"));
		if (Reflect.hasField(event, "px")) set("px", Reflect.field(event, "px"));
		if (Reflect.hasField(event, "qty")) set("qty", Reflect.field(event, "qty"));
	}

	static function tickField(tick:Dynamic, names:Array<String>, def:Dynamic):Dynamic {
		for (n in names)
			if (Reflect.hasField(tick, n)) return Reflect.field(tick, n);
		return def;
	}

	static function barField(harness:HarnessContext, name:String):Dynamic {
		if (harness.currentBar == null) return null;
		return switch (name) {
			case "open": harness.currentBar.open;
			case "high": harness.currentBar.high;
			case "low": harness.currentBar.low;
			case "close": harness.currentBar.close;
			case "volume": harness.currentBar.volume;
			case "time": harness.currentBar.time;
			case "bar_index": harness.currentBar.index;
			// Auxiliary tape columns — NaN when the bar doesn't carry the field.
			default: harness.isAuxSeries(name) ? harness.auxValue(name) : null;
		};
	}

	static function resolveSeriesName(harness:HarnessContext, series:Dynamic):String {
		if (Std.isOfType(series, String)) return cast series;
		if (harness.currentBar != null) return "close";
		return "close";
	}

	/**
	 * True when `name` has a JsBackend.dispatchBuiltin case.
	 * Used by install↔dispatch parity tests; arg errors still count as "known".
	 */
	public static function knowsDispatchedBuiltin(name:String):Bool {
		try {
			dispatchBuiltin(new HarnessContext(), name, []);
			return true;
		} catch (e:Dynamic) {
			return Std.string(e).indexOf("unknown builtin") < 0;
		}
	}

	static function dispatchBuiltin(harness:HarnessContext, name:String, args:Array<Dynamic>):Dynamic {
		return switch (name) {
			case "sma": TradeBuiltins.sma(harness, args[0], Std.int(args[1]));
			case "ema": TradeBuiltins.ema(harness, args[0], Std.int(args[1]));
			case "rsi": TradeBuiltins.rsi(harness, args[0], Std.int(args[1]));
			case "atr": builtinAtr(harness, args[0], Std.int(args[1]));
			case "obv": musescript.builtins.WickraBuiltins.obv(harness);
			case "williams_r": musescript.builtins.WickraBuiltins.williamsR(harness, Std.int(args[0]));
			case "aroon": musescript.builtins.WickraBuiltins.aroon(harness, Std.int(args[0]));
			case "cci": musescript.builtins.WickraBuiltins.cci(harness, Std.int(args[0]), args.length > 1 ? args[1] : null);
			case "mfi": musescript.builtins.WickraBuiltins.mfi(harness, Std.int(args[0]));
			case "bbands":
				TradeBuiltins.bbands(
					harness,
					args[0],
					Std.int(args[1]),
					args.length > 2 ? args[2] : 2.0
				);
			case "macd":
				TradeBuiltins.macd(
					harness,
					args[0],
					args.length > 1 ? Std.int(args[1]) : 12,
					args.length > 2 ? Std.int(args[2]) : 26,
					args.length > 3 ? Std.int(args[3]) : 9
				);
			case "stoch":
				TradeBuiltins.stoch(
					harness,
					args.length > 0 ? Std.int(args[0]) : 14,
					args.length > 1 ? Std.int(args[1]) : 3,
					args.length > 2 ? Std.int(args[2]) : 3
				);
			case "vwap": TradeBuiltins.vwap(harness);
			case "hl2": TradeBuiltins.hl2(harness);
			case "hlc3": TradeBuiltins.hlc3(harness);
			case "ohlc4": TradeBuiltins.ohlc4(harness);
			case "highest": builtinHighest(harness, args[0], Std.int(args[1]));
			case "lowest": builtinLowest(harness, args[0], Std.int(args[1]));
			case "change":
				builtinChange(harness, args[0], args.length > 1 ? Std.int(args[1]) : 1);
			case "pct_change":
				builtinPctChange(harness, args[0], args.length > 1 ? Std.int(args[1]) : 1);
			case "nz":
				TradeBuiltins.nz(args[0], args.length > 1 ? args[1] : 0);
			case "na":
				TradeBuiltins.na(args[0]);
			case "roc":
				TradeBuiltins.roc(harness, args[0], Std.int(args[1]));
			case "mom":
				TradeBuiltins.mom(harness, args[0], Std.int(args[1]));
			case "stdev":
				TradeBuiltins.stdev(harness, args[0], Std.int(args[1]));
			case "wma":
				TradeBuiltins.wma(harness, args[0], Std.int(args[1]));
			case "rma":
				TradeBuiltins.rma(harness, args[0], Std.int(args[1]));
			case "rising":
				{
					var minBars = args.length > 2 ? Std.int(args[2]) : 0;
					var bi = harness.currentBar != null ? harness.currentBar.index : -1;
					if (minBars > 0 && harness.orders.barsInTrade(bi) < minBars) false;
					else builtinRising(args[0], Std.int(args[1]));
				}
			case "falling":
				{
					var minBars = args.length > 2 ? Std.int(args[2]) : 0;
					var bi = harness.currentBar != null ? harness.currentBar.index : -1;
					if (minBars > 0 && harness.orders.barsInTrade(bi) < minBars) false;
					else builtinFalling(args[0], Std.int(args[1]));
				}
			case "window": TradeBuiltins.window(harness, args[0], Std.int(args[1]));
			case "ohlcv_window": TradeBuiltins.ohlcvWindow(harness, Std.int(args[0]));
			case "str_len": StringBuiltins.len(args[0]);
			case "str_slice":
				StringBuiltins.slice(args[0], Std.int(args[1]), args.length > 2 ? Std.int(args[2]) : null);
			case "str_contains": StringBuiltins.contains(args[0], args[1]);
			case "str_concat": StringBuiltins.concat(args[0], args[1]);
			case "str_to_float": StringBuiltins.toFloat(args[0]);
			case "str_trim": StringBuiltins.trim(args[0]);
			case "str_lower": StringBuiltins.lower(args[0]);
			case "str_upper": StringBuiltins.upper(args[0]);
			case "str_starts_with": StringBuiltins.startsWith(args[0], args[1]);
			case "str_ends_with": StringBuiltins.endsWith(args[0], args[1]);
			case "str_index_of":
				StringBuiltins.indexOf(args[0], args[1], args.length > 2 ? Std.int(args[2]) : 0);
			case "str_replace": StringBuiltins.replace(args[0], args[1], args[2]);
			case "str_split": StringBuiltins.split(args[0], args[1]);
			case "str_join": StringBuiltins.join(args[0], args[1]);
			case "str_to_bool": StringBuiltins.toBool(args[0]);
			case "str_from_float": StringBuiltins.fromFloat(args[0]);
			case "str_from_bool": StringBuiltins.fromBool(args[0]);
			case "ml_dot": MlBuiltins.dot(args[0], args[1]);
			case "ml_sigmoid": MlBuiltins.sigmoid(args[0]);
			case "ml_softmax": MlBuiltins.softmax(args[0]);
			case "ml_mse": MlBuiltins.mse(args[0], args[1]);
			case "ml_mae": MlBuiltins.mae(args[0], args[1]);
			case "ml_linear_predict":
				MlBuiltins.linearPredict(args[0], args[1], args.length > 2 ? args[2] : 0.0);
			case "ml_ridge_fit":
				MlBuiltins.ridgeFit(
					args[0],
					args[1],
					Std.int(args[2]),
					args.length > 3 ? args[3] : 1e-6
				);
			case "ml_matrix": MlBuiltins.matrix(Std.int(args[0]), Std.int(args[1]), args[2]);
			case "ml_matrix_rows": MlBuiltins.matrixRows(args[0]);
			case "ml_matrix_cols": MlBuiltins.matrixCols(args[0]);
			case "ml_matrix_data": MlBuiltins.matrixData(args[0]);
			case "ml_matrix_get": MlBuiltins.matrixGet(args[0], Std.int(args[1]), Std.int(args[2]));
			case "ml_ridge_fit_matrix":
				MlBuiltins.ridgeFitMatrix(args[0], args[1], args.length > 2 ? args[2] : 1e-6);
			case "crossover": TradeBuiltins.crossover(args[0], args[1]);
			case "crossunder": TradeBuiltins.crossunder(args[0], args[1]);
			case "clamp": Math.max(args[1], Math.min(args[2], args[0]));
			// math already on TradeBuiltins.install (harness-free)
			case "zscore": @:privateAccess TradeBuiltins.zscore(args[0]);
			case "vector_zscore": TradeBuiltins.zscore(args[0]);
			case "correlation": @:privateAccess TradeBuiltins.correlation(args[0], args[1]);
			case "sharpe": Metrics.sharpe(args[0]);
			case "stat_mean": StatsBuiltins.mean(args[0]);
			case "stat_median": StatsBuiltins.median(args[0]);
			case "stat_variance": StatsBuiltins.variance(args[0]);
			case "stat_sample_variance": StatsBuiltins.sampleVariance(args[0]);
			case "stat_stddev": StatsBuiltins.standardDeviation(args[0]);
			case "stat_sample_stddev": StatsBuiltins.sampleStandardDeviation(args[0]);
			case "stat_quantile": StatsBuiltins.quantile(args[0], args[1]);
			case "stat_covariance": StatsBuiltins.covariance(args[0], args[1]);
			case "stat_correlation": StatsBuiltins.pearson(args[0], args[1]);
			case "stat_skewness": StatsBuiltins.skewness(args[0]);
			case "stat_kurtosis": StatsBuiltins.kurtosis(args[0]);
			case "stat_rank": StatsBuiltins.rank(args[0], args[1]);
			case "stat_percentile_rank": StatsBuiltins.percentileRank(args[0], args[1]);
			case "stat_regression": StatsBuiltins.regression(args[0]);
			case "stat_autocorr": StatsBuiltins.autocorr(args[0], Std.int(args[1]));
			case "sort": StatsBuiltins.sort(args[0]);
			case "argsort": StatsBuiltins.argsort(args[0]);
			case "sortino": Metrics.sortino(args[0]);
			case "max_drawdown": Metrics.maxDrawdown(args[0]);
			case "stat_zscore": StatsBuiltins.zScores(args[0]);
			case "sci_cumsum": StatsBuiltins.cumulativeSum(args[0]);
			case "sci_diff": StatsBuiltins.difference(args[0]);
			case "sci_normalize": StatsBuiltins.normalize(args[0]);
			case "ewm_var": TradeBuiltins.ewmVar(harness, args[0], Std.int(args[1]));
			case "ewm_stdev": TradeBuiltins.ewmStdev(harness, args[0], Std.int(args[1]));
			case "ml_matrix_transpose": MlBuiltins.matrixTranspose(args[0]);
			case "ml_matrix_inverse": MlBuiltins.matrixInverse(args[0]);
			case "ml_matrix_determinant": MlBuiltins.matrixDeterminant(args[0]);
			case "set_jaccard": SetBuiltins.setJaccard(args[0], args[1]);
			case "graph_neighbors":
				GraphBuiltins.graphNeighbors(
					args[0],
					args[1],
					args.length > 2 ? args[2] : "out",
					args.length > 3 ? Std.int(args[3]) : 256
				);
			case "graph_degree":
				GraphBuiltins.graphDegree(args[0], args[1], args.length > 2 ? args[2] : "out");
			case "graph_has_edge":
				GraphBuiltins.graphHasEdge(args[0], args[1], args[2], args.length > 3 ? args[3] : null);
			case "graph_bfs":
				GraphBuiltins.graphBfs(
					args[0],
					args[1],
					args.length > 2 ? Std.int(args[2]) : GraphBuiltins.DEFAULT_MAX_DEPTH,
					args.length > 3 ? Std.int(args[3]) : GraphBuiltins.DEFAULT_TRAVERSAL_NODES
				);
			case "graph_reachable":
				GraphBuiltins.graphReachable(
					args[0],
					args[1],
					args[2],
					args.length > 3 ? Std.int(args[3]) : GraphBuiltins.DEFAULT_MAX_DEPTH,
					args.length > 4 ? Std.int(args[4]) : GraphBuiltins.DEFAULT_TRAVERSAL_NODES
				);
			case "graph_shortest_path":
				GraphBuiltins.graphShortestPath(
					args[0],
					args[1],
					args[2],
					args.length > 3 ? args[3] : false,
					args.length > 4 ? Std.int(args[4]) : GraphBuiltins.DEFAULT_TRAVERSAL_NODES
				);
			case "graph_pagerank":
				GraphBuiltins.graphPageRank(
					args[0],
					args.length > 1 ? Std.int(args[1]) : GraphBuiltins.DEFAULT_PAGERANK_ITERATIONS,
					args.length > 2 ? args[2] : 0.85,
					args.length > 3 ? Std.int(args[3]) : GraphBuiltins.DEFAULT_TRAVERSAL_NODES
				);
			case "dict_new": DictBuiltins.dictNew();
			case "dict_set": DictBuiltins.dictSet(args[0], args[1], args[2]);
			case "dict_get":
				DictBuiltins.dictGet(args[0], args[1], args.length > 2 ? args[2] : null);
			case "dict_has": DictBuiltins.dictHas(args[0], args[1]);
			case "dict_delete": DictBuiltins.dictDelete(args[0], args[1]);
			case "dict_keys": DictBuiltins.dictKeys(args[0]);
			case "dict_values": DictBuiltins.dictValues(args[0]);
			case "dict_size": DictBuiltins.dictSize(args[0]);
			case "set_new": SetBuiltins.setNew();
			case "set_add": SetBuiltins.setAdd(args[0], args[1]);
			case "set_has": SetBuiltins.setHas(args[0], args[1]);
			case "set_remove": SetBuiltins.setRemove(args[0], args[1]);
			case "set_size": SetBuiltins.setSize(args[0]);
			case "set_union": SetBuiltins.setUnion(args[0], args[1]);
			case "set_intersect": SetBuiltins.setIntersect(args[0], args[1]);
			case "set_difference": SetBuiltins.setDifference(args[0], args[1]);
			case "set_to_vector": SetBuiltins.setToVector(args[0]);
			// iter helpers — same MuseIters.from + IterDriver path as TradeBuiltins.install
			case "map": IterDriver.map(MuseIters.from(args[0]), Callables.asHost1(args[1], harness));
			case "flatMap": IterDriver.flatMap(MuseIters.from(args[0]), Callables.asHost1(args[1], harness));
			case "filter": IterDriver.filter(MuseIters.from(args[0]), Callables.asHostPred(args[1], harness));
			case "take": IterDriver.take(MuseIters.from(args[0]), Std.int(args[1]));
			case "drop": IterDriver.drop(MuseIters.from(args[0]), Std.int(args[1]));
			case "takeWhile": IterDriver.takeWhile(MuseIters.from(args[0]), Callables.asHostPred(args[1], harness));
			case "scan": IterDriver.scan(MuseIters.from(args[0]), args[1], Callables.asHost2(args[2], harness));
			case "reduce": IterDriver.reduce(MuseIters.from(args[0]), args[1], Callables.asHost2(args[2], harness));
			case "range":
				args.length < 2 || args[1] == null
					? IterDriver.range(0, Std.int(args[0]))
					: IterDriver.range(Std.int(args[0]), Std.int(args[1]));
			case "enumerate": IterDriver.enumerate(MuseIters.from(args[0]));
			case "merge": @:privateAccess TradeBuiltins.merge(args[0], args[1]);
			case "zip": @:privateAccess TradeBuiltins.zip(args[0], args[1]);
			case "zipWith":
				@:privateAccess TradeBuiltins.zipWith(args[0], args[1], Callables.asHost2(args[2], harness));
			case "log":
				var parts:Array<String> = [];
				for (a in args) if (a != null) parts.push(Std.string(a));
				harness.pushLog(parts.join(" "));
				null;
			case "plot":
				var bi = harness.currentBar != null ? harness.currentBar.index : 0;
				harness.chart.plot(args[0], args[1], args.length > 2 ? args[2] : null, bi);
				null;
			case "plotshape":
				var bi = harness.currentBar != null ? harness.currentBar.index : 0;
				harness.chart.plotshape(args[0], bi);
				null;
			case "hline":
				harness.chart.hline(args[0], args[1]);
				null;
			case "bgcolor":
				var bi = harness.currentBar != null ? harness.currentBar.index : 0;
				harness.chart.bgcolor(args[0], bi);
				null;
			case "long":
				harness.orders.submit("long", args.length > 0 ? args[0] : null,
					harness.currentBar.close, harness.currentBar.index);
				null;
			case "short":
				harness.orders.submit("short", args.length > 0 ? args[0] : null,
					harness.currentBar.close, harness.currentBar.index);
				null;
			case "flat" | "close":
				harness.orders.submit("flat", args.length > 0 ? args[0] : null,
					harness.currentBar.close, harness.currentBar.index);
				null;
			case "orders_pending": harness.orders.book.pendingCount();
			case "orders_cancel_all": harness.orders.book.cancelAll();
			case "position": harness.orders.positionSize();
			case "entry_price": harness.orders.entryPrice;
			case "bars_in_trade": harness.orders.barsInTrade(harness.currentBar.index);
			case "cash": harness.orders.cash;
			case "equity": harness.orders.equityAt(harness.currentBar.close);
			case "unrealized_pnl": harness.orders.unrealizedPnl(harness.currentBar.close);
			case "symbols":
				harness.panelSymbols != null ? harness.panelSymbols.copy() : [];
			case "sym_available":
				var px0 = harness.panelPrice(args[0]);
				px0 > 0 && !Math.isNaN(px0);
			case "close_of":
				harness.seriesLookback(musescript.builtins.PortfolioBuiltins.seriesKey("close", args[0]),
					args.length > 1 ? Std.int(args[1]) : 0);
			case "open_of":
				harness.seriesLookback(musescript.builtins.PortfolioBuiltins.seriesKey("open", args[0]),
					args.length > 1 ? Std.int(args[1]) : 0);
			case "high_of":
				harness.seriesLookback(musescript.builtins.PortfolioBuiltins.seriesKey("high", args[0]),
					args.length > 1 ? Std.int(args[1]) : 0);
			case "low_of":
				harness.seriesLookback(musescript.builtins.PortfolioBuiltins.seriesKey("low", args[0]),
					args.length > 1 ? Std.int(args[1]) : 0);
			case "volume_of":
				harness.seriesLookback(musescript.builtins.PortfolioBuiltins.seriesKey("volume", args[0]),
					args.length > 1 ? Std.int(args[1]) : 0);
			case "sma_of":
				TradeBuiltins.sma(harness, musescript.builtins.PortfolioBuiltins.seriesKey("close", args[0]), Std.int(args[1]));
			case "ema_of":
				TradeBuiltins.ema(harness, musescript.builtins.PortfolioBuiltins.seriesKey("close", args[0]), Std.int(args[1]));
			case "mom_of":
				TradeBuiltins.mom(harness, musescript.builtins.PortfolioBuiltins.seriesKey("close", args[0]), Std.int(args[1]));
			case "rsi_of":
				TradeBuiltins.rsi(harness, musescript.builtins.PortfolioBuiltins.seriesKey("close", args[0]), Std.int(args[1]));
			case "fund_of":
				harness.seriesLookback(musescript.builtins.PortfolioBuiltins.seriesKey(args[1], args[0]),
					args.length > 2 ? Std.int(args[2]) : 0);
			case "scan_top":
				musescript.builtins.PortfolioBuiltins.rankPick(args[0], Std.int(args[1]), false);
			case "scan_bottom":
				musescript.builtins.PortfolioBuiltins.rankPick(args[0], Std.int(args[1]), true);
			case "buy":
				var biB = harness.currentBar != null ? harness.currentBar.index : -1;
				harness.portfolio.buy(args[0], harness.panelPrice(args[0]),
					args.length > 1 ? args[1] : null, biB);
				null;
			case "sell_all":
				var biS = harness.currentBar != null ? harness.currentBar.index : -1;
				harness.portfolio.sellAll(args[0], harness.panelPrice(args[0]), biS);
				null;
			case "pos": harness.portfolio.positionOf(args[0]);
			case "entry_of": harness.portfolio.entryOf(args[0]);
			case "weight_of": harness.portfolio.weightOf(args[0], harness.panelPrices);
			case "holdings": harness.portfolio.holdings();
			case "rebalance_equal":
				var biR = harness.currentBar != null ? harness.currentBar.index : -1;
				harness.portfolio.rebalanceEqual(
					musescript.builtins.PortfolioBuiltins.toStringArray(args[0]),
					harness.panelPrices, biR);
				null;
			case "target_weight":
				var biT = harness.currentBar != null ? harness.currentBar.index : -1;
				harness.portfolio.targetWeight(args[0], args[1], harness.panelPrices, biT);
				null;
			case "portfolio_equity": harness.portfolio.equityAt(harness.panelPrices);
			case "portfolio_cash": harness.portfolio.cash;
			case "portfolio_unrealized": harness.portfolio.unrealizedPnl(harness.panelPrices);
			case "bag" | "bag_new":
				musescript.builtins.BagBuiltins.bagNew(args.length > 0 ? args[0] : null);
			case "bag_set":
				musescript.builtins.BagBuiltins.ensure(args[0]).setWeight(args[1], args[2]);
			case "bag_get":
				musescript.builtins.BagBuiltins.materialize(harness, args[0]).weightOf(args[1]);
			case "bag_has":
				musescript.builtins.BagBuiltins.materialize(harness, args[0]).weights.exists(args[1]);
			case "bag_delete":
				musescript.builtins.BagBuiltins.ensure(args[0]).setWeight(args[1], 0);
			case "bag_name":
				musescript.builtins.BagBuiltins.ensure(args[0]).name;
			case "bag_rename":
				musescript.builtins.BagBuiltins.ensure(args[0]).copy(args[1]);
			case "bag_symbols":
				musescript.builtins.BagBuiltins.materialize(harness, args[0]).symbols();
			case "bag_size":
				musescript.builtins.BagBuiltins.materialize(harness, args[0]).size();
			case "bag_mode":
				var bm = musescript.builtins.BagBuiltins.ensure(args[0]);
				bm.isComputed() ? "computed" : "static";
			case "bag_is_static":
				!musescript.builtins.BagBuiltins.ensure(args[0]).isComputed();
			case "bag_is_computed":
				musescript.builtins.BagBuiltins.ensure(args[0]).isComputed();
			case "bag_equal":
				musescript.builtins.BagBuiltins.bagEqual(args[0], args.length > 1 ? args[1] : null);
			case "bag_pair":
				musescript.builtins.BagBuiltins.bagPair(
					args[0], args[1],
					args.length > 2 ? args[2] : null,
					args.length > 3 ? args[3] : null);
			case "bag_from_dict":
				musescript.builtins.BagBuiltins.bagFromDict(args[0], args.length > 1 ? args[1] : null);
			case "bag_from_scan":
				var picksFs = musescript.builtins.PortfolioBuiltins.rankPick(
					args[0], Std.int(args[1]), args.length > 3 && args[3] == true);
				musescript.builtins.BagBuiltins.bagEqual(
					picksFs, args.length > 2 ? args[2] : "scan");
			case "bag_to_dict":
				var bd = musescript.builtins.BagBuiltins.materialize(harness, args[0]);
				var dout = new Map<String, Dynamic>();
				for (k => v in bd.weights) dout.set(k, v);
				dout;
			case "bag_computed":
				musescript.builtins.BagBuiltins.bagComputed(
					args[0], args.length > 1 ? args[1] : null);
			case "bag_resolve":
				musescript.builtins.BagBuiltins.materialize(harness, args[0]);
			case "bag_rank_mom":
				musescript.builtins.BagBuiltins.bagRecipe(
					args.length > 2 && args[2] != null ? args[2] : "rank_mom",
					{ op: "rank_mom", n: args[0], look: args.length > 1 && args[1] != null ? args[1] : 21 });
			case "bag_rank_rsi":
				musescript.builtins.BagBuiltins.bagRecipe(
					args.length > 2 && args[2] != null ? args[2] : "rank_rsi",
					{
						op: "rank_rsi",
						n: args[0],
						len: args.length > 1 && args[1] != null ? args[1] : 14,
						ascending: args.length > 3 && args[3] == true
					});
			case "bag_rank_field":
				musescript.builtins.BagBuiltins.bagRecipe(
					args.length > 2 && args[2] != null ? args[2] : ("rank_" + Std.string(args[0])),
					{
						op: "rank_field",
						field: args[0],
						n: args[1],
						ascending: args.length > 3 && args[3] == true
					});
			case "bag_graph":
				musescript.builtins.BagBuiltins.bagRecipe(
					args.length > 3 && args[3] != null ? args[3] : ("nbr:" + Std.string(args[1])),
					{
						op: "graph_neighbors",
						graph: args[0],
						seed: args[1],
						limit: args.length > 2 && args[2] != null ? args[2] : 16,
						direction: "out"
					});
			case "bag_add":
				musescript.builtins.BagBuiltins.bagAdd(
					musescript.builtins.BagBuiltins.materialize(harness, args[0]),
					musescript.builtins.BagBuiltins.materialize(harness, args[1]),
					args.length > 2 ? args[2] : null);
			case "bag_sub":
				musescript.builtins.BagBuiltins.bagSub(
					musescript.builtins.BagBuiltins.materialize(harness, args[0]),
					musescript.builtins.BagBuiltins.materialize(harness, args[1]),
					args.length > 2 ? args[2] : null);
			case "bag_mask":
				musescript.builtins.BagBuiltins.bagMask(
					musescript.builtins.BagBuiltins.materialize(harness, args[0]),
					args[1],
					args.length > 2 ? args[2] : null);
			case "bag_scale":
				musescript.builtins.BagBuiltins.bagScale(
					musescript.builtins.BagBuiltins.materialize(harness, args[0]),
					args[1],
					args.length > 2 ? args[2] : null);
			case "bag_norm":
				musescript.builtins.BagBuiltins.bagNorm(
					musescript.builtins.BagBuiltins.materialize(harness, args[0]),
					args.length > 1 ? args[1] : null);
			case "portfolio_bag":
				musescript.builtins.BagBuiltins.portfolioBag(harness, args.length > 0 ? args[0] : null);
			case "portfolio_apply":
				var biA = harness.currentBar != null ? harness.currentBar.index : -1;
				harness.portfolio.applyBag(
					musescript.builtins.BagBuiltins.materialize(harness, args[0]).weights,
					harness.panelPrices, biA, true);
				null;
			case "portfolio_add":
				var biAd = harness.currentBar != null ? harness.currentBar.index : -1;
				var curA = musescript.builtins.BagBuiltins.portfolioBag(harness, "");
				var mergedA = musescript.builtins.BagBuiltins.bagAdd(
					curA, musescript.builtins.BagBuiltins.materialize(harness, args[0]), null);
				harness.portfolio.applyBag(mergedA.weights, harness.panelPrices, biAd, false);
				null;
			case "portfolio_sub":
				var biS = harness.currentBar != null ? harness.currentBar.index : -1;
				var curS = musescript.builtins.BagBuiltins.portfolioBag(harness, "");
				var mergedS = musescript.builtins.BagBuiltins.bagSub(
					curS, musescript.builtins.BagBuiltins.materialize(harness, args[0]), null);
				harness.portfolio.applyBag(mergedS.weights, harness.panelPrices, biS, true);
				null;
			case "portfolio_mask":
				var biM = harness.currentBar != null ? harness.currentBar.index : -1;
				var curM = musescript.builtins.BagBuiltins.portfolioBag(harness, "");
				var kept = musescript.builtins.BagBuiltins.bagMask(curM, args[0], null);
				harness.portfolio.applyBag(kept.weights, harness.panelPrices, biM, true);
				null;
			case "any": IterDriver.any(MuseIters.from(args[0]), Callables.asHostPred(args[1], harness));
			case "all": IterDriver.all(MuseIters.from(args[0]), Callables.asHostPred(args[1], harness));
			case "find": IterDriver.find(MuseIters.from(args[0]), Callables.asHost1(args[1], harness));
			case "sum": IterDriver.sum(MuseIters.from(args[0]));
			case "count": IterDriver.count(MuseIters.from(args[0]));
			case "min": IterDriver.min(MuseIters.from(args[0]));
			case "max": IterDriver.max(MuseIters.from(args[0]));
			case "avg": IterDriver.avg(MuseIters.from(args[0]));
			default:
				throw 'JsBackend: unknown builtin $name';
		};
	}

	// --- builtin parity (mirrors TradeBuiltins; self-contained for JS emit path) ---

	static function resolveSeries(harness:HarnessContext, src:Dynamic):Array<Float> {
		if (src == null) return harness.series.exists("close") ? harness.series.get("close") : [];
		if (Std.isOfType(src, Array)) return cast src;
		if (Std.isOfType(src, String)) {
			var a = harness.series.get(cast src);
			return a != null ? a : [];
		}
		return harness.series.exists("close") ? harness.series.get("close") : [];
	}

	static function builtinAtr(harness:HarnessContext, src:Dynamic, len:Int):Float {
		// Same math as before; TradeBuiltins.atr now extends a cached TR column
		// instead of rebuilding it every bar.
		return TradeBuiltins.atr(harness, src, len);
	}

	static function builtinHighest(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0) return Math.NaN;
		var start = Std.int(Math.max(0, a.length - len));
		var m = a[start];
		for (i in start...a.length) if (a[i] > m) m = a[i];
		return m;
	}

	static function builtinLowest(harness:HarnessContext, src:Dynamic, len:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length == 0) return Math.NaN;
		var start = Std.int(Math.max(0, a.length - len));
		var m = a[start];
		for (i in start...a.length) if (a[i] < m) m = a[i];
		return m;
	}

	static function builtinChange(harness:HarnessContext, src:Dynamic, n:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length <= n) return Math.NaN;
		return a[a.length - 1] - a[a.length - 1 - n];
	}

	static function builtinPctChange(harness:HarnessContext, src:Dynamic, n:Int):Float {
		var a = resolveSeries(harness, src);
		if (a.length <= n) return Math.NaN;
		var prev = a[a.length - 1 - n];
		return prev == 0 ? Math.NaN : (a[a.length - 1] - prev) / prev;
	}

	static function builtinRising(x:Float, n:Int):Bool {
		if (Math.isNaN(x) || n <= 0) return false;
		var slot = jsCallSlot++;
		var hist = slot < jsSeriesHistory.length ? jsSeriesHistory[slot] : null;
		if (hist == null) {
			hist = [];
			while (jsSeriesHistory.length <= slot) jsSeriesHistory.push(null);
			jsSeriesHistory[slot] = hist;
		}
		hist.push(x);
		while (hist.length > n + 1) hist.shift();
		if (hist.length < n + 1) return false;
		for (i in (hist.length - n)...hist.length) {
			if (Math.isNaN(hist[i]) || Math.isNaN(hist[i - 1])) return false;
			if (!(hist[i] - hist[i - 1] > 0)) return false;
		}
		return true;
	}

	static function builtinFalling(x:Float, n:Int):Bool {
		if (Math.isNaN(x) || n <= 0) return false;
		var slot = jsCallSlot++;
		var hist = slot < jsSeriesHistory.length ? jsSeriesHistory[slot] : null;
		if (hist == null) {
			hist = [];
			while (jsSeriesHistory.length <= slot) jsSeriesHistory.push(null);
			jsSeriesHistory[slot] = hist;
		}
		hist.push(x);
		while (hist.length > n + 1) hist.shift();
		if (hist.length < n + 1) return false;
		for (i in (hist.length - n)...hist.length) {
			if (Math.isNaN(hist[i]) || Math.isNaN(hist[i - 1])) return false;
			if (!(hist[i] - hist[i - 1] < 0)) return false;
		}
		return true;
	}
}
