package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.BarStrategyFn;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.BacktestResult;
import musescript.harness.Metrics;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;
import musescript.runtime.MuseIters;
import musescript.runtime.IterDriver;

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
		var src = emitter.emitOnBar(prog);
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
			var feed:BarFeed = Reflect.hasField(ctx, "feed")
				? Reflect.field(ctx, "feed")
				: BarFeed.synthetic(200, 1);

			var seed = new MuseInterp(harness);
			for (d in prog.decls) seed.registerDeclPublic(d);

			#if js
			if (onBarFn != null) {
				var api = makeApi(harness);
				installCachedIndicators(api, cachedInds);
				return harness.runBacktest(function(bar:Bar) {
					bindBar(api, harness, bar);
					onBarFn(api);
				}, feed);
			}
			#end
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

	static function makeApi(harness:HarnessContext):Dynamic {
		var frames:Array<Map<String, Dynamic>> = [new Map()];
		var api:Dynamic = {};

		function current():Map<String, Dynamic> {
			return frames[frames.length - 1];
		}
		function lookup(name:String):Dynamic {
			var i = frames.length;
			while (i-- > 0) {
				if (frames[i].exists(name)) return frames[i].get(name);
			}
			if (harness.params.all().exists(name)) return harness.params.get(name);
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
		Reflect.setField(api, "set", function(name:String, v:Dynamic):Dynamic {
			current().set(name, v);
			if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
				harness.pushSeries(name, v);
			return v;
		});
		Reflect.setField(api, "setRoot", function(name:String, v:Dynamic):Dynamic {
			frames[0].set(name, v);
			return v;
		});
		Reflect.setField(api, "bar", function(name:String):Dynamic {
			var cached:Dynamic = Reflect.field(api, "__bar");
			if (cached != null && Reflect.hasField(cached, name))
				return Reflect.field(cached, name);
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
		Reflect.setField(api, "long", function(?qty:Float) {
			if (harness.currentBar != null) harness.orders.long(harness.currentBar.close, qty);
		});
		Reflect.setField(api, "short", function(?qty:Float) {
			if (harness.currentBar != null) harness.orders.short(harness.currentBar.close, qty);
		});
		Reflect.setField(api, "flat", function() {
			if (harness.currentBar != null) harness.orders.flat(harness.currentBar.close);
		});
		Reflect.setField(api, "call", function(name:String, args:Array<Dynamic>):Dynamic {
			return dispatchBuiltin(harness, name, args);
		});
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

	static var jsCallSlot:Int = 0;
	static var jsSeriesHistory:Map<Int, Array<Float>> = new Map();

	static function bindBar(api:Dynamic, harness:HarnessContext, bar:Bar):Void {
		TradeBuiltins.beginBar();
		jsCallSlot = 0;
		Reflect.setField(api, "__bar", {
			open: bar.open,
			high: bar.high,
			low: bar.low,
			close: bar.close,
			volume: bar.volume,
			time: bar.time,
			bar_index: bar.index
		});
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
			default: null;
		};
	}

	static function resolveSeriesName(harness:HarnessContext, series:Dynamic):String {
		if (Std.isOfType(series, String)) return cast series;
		if (harness.currentBar != null) return "close";
		return "close";
	}

	static function dispatchBuiltin(harness:HarnessContext, name:String, args:Array<Dynamic>):Dynamic {
		return switch (name) {
			case "sma": TradeBuiltins.sma(harness, args[0], Std.int(args[1]));
			case "ema": TradeBuiltins.ema(harness, args[0], Std.int(args[1]));
			case "rsi": TradeBuiltins.rsi(harness, args[0], Std.int(args[1]));
			case "atr": builtinAtr(harness, args[0], Std.int(args[1]));
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
			case "rising": builtinRising(args[0], Std.int(args[1]));
			case "falling": builtinFalling(args[0], Std.int(args[1]));
			case "crossover": TradeBuiltins.crossover(args[0], args[1]);
			case "crossunder": TradeBuiltins.crossunder(args[0], args[1]);
			case "clamp": Math.max(args[1], Math.min(args[2], args[0]));
			// math already on TradeBuiltins.install (harness-free)
			case "zscore": @:privateAccess TradeBuiltins.zscore(args[0]);
			case "correlation": @:privateAccess TradeBuiltins.correlation(args[0], args[1]);
			case "sharpe": Metrics.sharpe(args[0]);
			// iter helpers — same MuseIters.from + IterDriver path as TradeBuiltins.install
			case "map": IterDriver.map(MuseIters.from(args[0]), args[1]);
			case "flatMap": IterDriver.flatMap(MuseIters.from(args[0]), args[1]);
			case "filter": IterDriver.filter(MuseIters.from(args[0]), args[1]);
			case "take": IterDriver.take(MuseIters.from(args[0]), Std.int(args[1]));
			case "drop": IterDriver.drop(MuseIters.from(args[0]), Std.int(args[1]));
			case "takeWhile": IterDriver.takeWhile(MuseIters.from(args[0]), args[1]);
			case "scan": IterDriver.scan(MuseIters.from(args[0]), args[1], args[2]);
			case "reduce": IterDriver.reduce(MuseIters.from(args[0]), args[1], args[2]);
			case "range":
				args.length < 2 || args[1] == null
					? IterDriver.range(0, Std.int(args[0]))
					: IterDriver.range(Std.int(args[0]), Std.int(args[1]));
			case "enumerate": IterDriver.enumerate(MuseIters.from(args[0]));
			case "merge": @:privateAccess TradeBuiltins.merge(args[0], args[1]);
			case "zip": @:privateAccess TradeBuiltins.zip(args[0], args[1]);
			case "zipWith": @:privateAccess TradeBuiltins.zipWith(args[0], args[1], args[2]);
			// skip any/all/find/sum/count — not on TradeBuiltins.install yet (other ducks)
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
				harness.orders.long(harness.currentBar.close, args.length > 0 ? args[0] : null);
				null;
			case "short":
				harness.orders.short(harness.currentBar.close, args.length > 0 ? args[0] : null);
				null;
			case "flat" | "close":
				harness.orders.flat(harness.currentBar.close);
				null;
			case "any": IterDriver.any(MuseIters.from(args[0]), args[1]);
			case "all": IterDriver.all(MuseIters.from(args[0]), args[1]);
			case "find": IterDriver.find(MuseIters.from(args[0]), args[1]);
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
		var h = harness.series.get("high");
		var l = harness.series.get("low");
		var c = harness.series.get("close");
		if (h == null || l == null || c == null || c.length < 2) return Math.NaN;
		var trs:Array<Float> = [];
		for (i in 1...c.length) {
			var tr = Math.max(h[i] - l[i], Math.max(Math.abs(h[i] - c[i - 1]), Math.abs(l[i] - c[i - 1])));
			trs.push(tr);
		}
		if (trs.length < len) return Math.NaN;
		var sum = 0.0;
		for (i in (trs.length - len)...trs.length) sum += trs[i];
		return sum / len;
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
		var hist = jsSeriesHistory.get(slot);
		if (hist == null) {
			hist = [];
			jsSeriesHistory.set(slot, hist);
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
		var hist = jsSeriesHistory.get(slot);
		if (hist == null) {
			hist = [];
			jsSeriesHistory.set(slot, hist);
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
