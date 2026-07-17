package musescript.interp;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.Pattern;
import musescript.runtime.CallFrame;
import musescript.runtime.CallStack;
import musescript.runtime.FnClosure;
import musescript.runtime.IndicatorInstance;
import musescript.runtime.Generator;
import musescript.runtime.YieldSignal;
import musescript.runtime.PatternMatcher;
import musescript.runtime.StreamMatcher;
import musescript.runtime.MuseIters;
import musescript.runtime.MuseIter;
import musescript.runtime.IterDriver;
import musescript.harness.IHarness;
import musescript.harness.HarnessContext;
import musescript.harness.Bar;
import musescript.harness.BarFeed;
import musescript.builtins.TradeBuiltins;
import musescript.builtins.macro.MacroBuiltins;
import musescript.types.BuiltinSigs;

/**
 * MuseScript interpreter — CallFrame stack, MuseAST walk, MuseIter for-in.
 * Extends semantics beyond stock hscript.Interp (does not subclass for clarity).
 */
class MuseInterp {
	public var globals:Map<String, Dynamic>;
	public var stack:CallStack;
	public var harness:HarnessContext;
	public var matcher:PatternMatcher;
	public var lastValue:Dynamic;
	var returnFlag:Bool;
	var returnValue:Dynamic;
	var activeGenerator:Null<Generator>;
	/** Resume point after GeneratorYieldPause (stepped generator eval). */
	var genResume:Null<GenResume>;
	var onBarHandlers:Array<Array<Stmt>>;
	var onPositionHandlers:Array<Array<Stmt>>;
	/** Strategy-body assigns re-executed before handlers on every bar. */
	var preludeStmts:Array<Stmt>;
	var onTickHandlers:Array<Array<Stmt>>;
	var onEventHandlers:Array<{stream:String, body:Array<Stmt>}>;
	var strategyName:Null<String>;

	public function new(harness:IHarness) {
		this.harness = Std.isOfType(harness, HarnessContext) ? cast harness : new HarnessContext();
		this.globals = new Map();
		this.stack = new CallStack();
		this.matcher = new PatternMatcher();
		this.lastValue = null;
		this.returnFlag = false;
		this.returnValue = null;
		this.activeGenerator = null;
		this.genResume = null;
		this.onBarHandlers = [];
		this.onPositionHandlers = [];
		this.preludeStmts = [];
		this.onTickHandlers = [];
		this.onEventHandlers = [];
		this.strategyName = null;
		installBuiltins();
	}

	function installBuiltins():Void {
		globals.set("null", null);
		globals.set("true", true);
		globals.set("false", false);
		globals.set("trace", function(v:Dynamic) {
			// Route into the IDE console buffer (bar-tagged) as well as stdout,
			// so `trace(...)` output is visible in the Studio console pane.
			harness.pushLog(Std.string(v));
			#if js
			untyped console.log(v);
			#else
			Sys.println(Std.string(v));
			#end
		});
		TradeBuiltins.install(globals, harness);
		MacroBuiltins.install(globals, harness);
		globals.set("Math", {
			abs: Math.abs,
			min: Math.min,
			max: Math.max,
			sqrt: Math.sqrt,
			pow: Math.pow,
			floor: Math.floor,
			ceil: Math.ceil,
			round: Math.round,
			sin: Math.sin,
			cos: Math.cos,
			log: Math.log,
			exp: Math.exp,
			NaN: Math.NaN,
			PI: Math.PI
		});
	}

	public function executeProgram(prog:MuseProgram):Dynamic {
		for (d in prog.decls) registerDecl(d);
		for (s in prog.stmts) execStmt(s);

		// If we have on bar handlers and a default backtest, run it
		if (onBarHandlers.length > 0) {
			var feed = BarFeed.synthetic(300, 7);
			return harness.runBacktest(function(bar) {
				bindBar(bar);
				for (st in preludeStmts) execStmt(st);
				for (h in onBarHandlers) {
					for (st in h) execStmt(st);
				}
				if (harness.orders.position != 0) {
					for (h in onPositionHandlers) {
						for (st in h) execStmt(st);
					}
				}
			}, feed);
		}
		return lastValue;
	}

	public function runBacktest(prog:MuseProgram, feed:BarFeed):Dynamic {
		setupRun(prog);
		return harness.runBacktest(function(bar) execBar(bar), feed);
	}

	/**
	 * Setup half of a backtest run: reset handler lists, register decls, execute
	 * top-level statements (collecting @on(bar)/@on(position) handlers + the
	 * per-bar prelude). Shared by runBacktest and the debugger (MuseDebugSession)
	 * so stepped and full runs are guaranteed to execute identical code.
	 */
	public function setupRun(prog:MuseProgram):Void {
		onBarHandlers = [];
		onPositionHandlers = [];
		onTickHandlers = [];
		onEventHandlers = [];
		preludeStmts = [];
		var self = this;
		harness.invokeUserFn = function(f:Dynamic, args:Array<Dynamic>):Dynamic {
			return self.callValue(f, args != null ? args : []);
		};
		for (d in prog.decls) registerDecl(d);
		for (s in prog.stmts) execStmt(s);
	}

	/**
	 * Per-bar handler execution: bindBar + prelude + on(bar) + on(position).
	 * The caller owns the surrounding harness bookkeeping (orders.beginBar,
	 * series observation, orders.mark) — see HarnessContext.runBacktest (full
	 * run) and MuseDebugSession.stepBar (stepped run), which drive it identically.
	 */
	public function execBar(bar:Bar):Void {
		bindBar(bar);
		for (st in preludeStmts) execStmt(st);
		for (h in onBarHandlers) for (st in h) execStmt(st);
		if (harness.orders.position != 0 || harness.portfolio.holdings().length > 0)
			for (h in onPositionHandlers) for (st in h) execStmt(st);
	}

	public function runPanelBacktest(prog:MuseProgram, panel:musescript.harness.PanelFeed):Dynamic {
		setupRun(prog);
		return harness.runPanelBacktest(function(bar) execBar(bar), panel);
	}

	public function registerDeclPublic(d:Decl):Void {
		registerDecl(d);
	}

	function registerDecl(d:Decl):Void {
		switch (d) {
			case StrategyDecl(name, body):
				strategyName = name;
				registerStrategyBody(body);
			case ParamDecl(name, def, opts):
				var v = def != null ? evalExpr(def) : 0;
				harness.params.register(name, v, opts.min, opts.max, opts.step, opts.tune);
				globals.set(name, v);
			case FnDecl(name, args, body, kind):
				var fn = new FnClosure(args, body, stack.current(), name, kind);
				if (name != null) globals.set(name, fn);
			case IndicatorDecl(name, args, body):
				var closure = new FnClosure(args, body, stack.current(), name, Normal);
				var instance = new IndicatorInstance(closure, name);
				globals.set(name, instance);
				harness.indicators.register(name, instance);
			case MacroDecl(name, body):
				// Macro bodies executed by planner, not here
				globals.set('__macro_$name', body);
			case ModuleDecl(_, _, _) | TemplateDecl(_, _, _, _) | StmtTemplateDecl(_, _, _):
				// Expanded before execution / compile
		}
	}

	/**
	 * Register a typed-surface `strategy { ... }` body with JsEmitter-parity
	 * semantics (collectStrategyHooks): Assign statements are a PER-BAR prelude
	 * (`fast = ema(close, 5)` must re-evaluate on every bar), hooks register as
	 * handlers, everything else keeps the historical run-once behavior. Executing
	 * assigns once at registration bound indicator locals before any bar existed,
	 * so interp-fallback backtests silently produced 0 trades.
	 */
	function registerStrategyBody(body:Array<Stmt>):Void {
		for (s in body) switch (s) {
			case Assign(_, _): preludeStmts.push(s);
			case Block(inner): registerStrategyBody(inner);
			default: execStmt(s);
		}
	}

	function bindBar(bar:Bar):Void {
		TradeBuiltins.beginBar();
		harness.indCols.beginBar();
		globals.set("open", bar.open);
		globals.set("high", bar.high);
		globals.set("low", bar.low);
		globals.set("close", bar.close);
		globals.set("volume", bar.volume);
		globals.set("time", bar.time);
		globals.set("bar_index", bar.index);
		// Refresh param bindings
		for (n in harness.params.names()) globals.set(n, harness.params.get(n));
	}

	/** Bind tick event fields onto globals for on(tick) handlers (live / event path). */
	function bindTick(tick:Dynamic):Void {
		if (tick == null) return;
		globals.set("tick", tick);
		globals.set("price", tickField(tick, ["price", "px", "last"], Math.NaN));
		globals.set("size", tickField(tick, ["size", "qty", "volume"], 0));
		globals.set("time", tickField(tick, ["time", "ts", "timestamp"], harnessNow()));
		globals.set("bid", tickField(tick, ["bid"], Math.NaN));
		globals.set("ask", tickField(tick, ["ask"], Math.NaN));
		if (Reflect.hasField(tick, "side")) globals.set("side", Reflect.field(tick, "side"));
		if (Reflect.hasField(tick, "symbol")) globals.set("symbol", Reflect.field(tick, "symbol"));
		for (n in harness.params.names()) globals.set(n, harness.params.get(n));
	}

	/**
	 * Bind order-flow / custom event fields onto globals (JsBackend.bindEvent parity).
	 * Exposes event/price/size/time plus kind/id/reason/px/qty/side/symbol when present.
	 */
	function bindEvent(event:Dynamic):Void {
		if (event == null) return;
		globals.set("event", event);
		globals.set("price", tickField(event, ["price", "px", "last"], Math.NaN));
		globals.set("size", tickField(event, ["size", "qty", "volume"], 0));
		globals.set("time", tickField(event, ["time", "ts", "timestamp"], harnessNow()));
		if (Reflect.hasField(event, "kind")) globals.set("kind", Reflect.field(event, "kind"));
		if (Reflect.hasField(event, "id")) globals.set("id", Reflect.field(event, "id"));
		if (Reflect.hasField(event, "reason")) globals.set("reason", Reflect.field(event, "reason"));
		if (Reflect.hasField(event, "side")) globals.set("side", Reflect.field(event, "side"));
		if (Reflect.hasField(event, "symbol")) globals.set("symbol", Reflect.field(event, "symbol"));
		if (Reflect.hasField(event, "px")) globals.set("px", Reflect.field(event, "px"));
		if (Reflect.hasField(event, "qty")) globals.set("qty", Reflect.field(event, "qty"));
		for (n in harness.params.names()) globals.set(n, harness.params.get(n));
	}

	function tickField(tick:Dynamic, names:Array<String>, def:Dynamic):Dynamic {
		for (n in names)
			if (Reflect.hasField(tick, n)) return Reflect.field(tick, n);
		return def;
	}

	function harnessNow():Float {
		return Reflect.hasField(harness, "now") ? Reflect.field(harness, "now") : 0;
	}

	function execStmt(s:Stmt):Void {
		if (returnFlag) return;
		switch (s) {
			case OnBar(body): onBarHandlers.push(body);
			case OnPosition(body): onPositionHandlers.push(body);
			case OnTick(body): onTickHandlers.push(body);
			case OnEvent(stream, body): onEventHandlers.push({ stream: stream, body: body });
			case ExprStmt(e): lastValue = evalExpr(e);
			case Assign(name, e):
				var v = evalExpr(e);
				define(name, v);
				if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
					harness.pushSeries(name, v);
				lastValue = v;
			case ForIn(name, iter, body):
				var it = MuseIters.from(evalExpr(iter));
				IterDriver.each(it, function(item) {
					define(name, item);
					for (st in body) execStmt(st);
				});
			case MatchFor(name, iter, arms):
				var it = MuseIters.from(evalExpr(iter));
				var sm = new StreamMatcher(matcher);
				sm.matchFor(it, arms, function(bindings, body) {
					var frame = new CallFrame(stack.current(), "match");
					for (k => v in bindings) frame.define(k, v);
					stack.push(frame);
					define(name, bindings.exists(name) ? bindings.get(name) : null);
					evalExpr(body);
					stack.pop();
				}, function(bindings, guard) {
					var frame = new CallFrame(stack.current(), "guard");
					for (k => v in bindings) frame.define(k, v);
					stack.push(frame);
					var ok = truthy(evalExpr(guard));
					stack.pop();
					return ok;
				});
			case Return(e):
				returnValue = e != null ? evalExpr(e) : null;
				returnFlag = true;
			case Yield(e):
				yieldValue(evalExpr(e));
			case YieldStar(e):
				yieldStar(e);
			case Order(kind, args):
				var qty = args.length > 0 ? evalExpr(args[0]) : null;
				var bi = harness.currentBar != null ? harness.currentBar.index : -1;
				switch (kind) {
					case Long: harness.orders.long(harness.currentBar.close, qty, bi);
					case Short: harness.orders.short(harness.currentBar.close, qty, bi);
					case Flat | Close: harness.orders.flat(harness.currentBar.close, bi);
				}
			case Block(stmts):
				for (st in stmts) execStmt(st);
			case When(cond, body):
				if (truthy(evalExpr(cond)))
					for (st in body) execStmt(st);
			case Use(_, _):
				throw "MuseInterp: unresolved use — run ModuleExpand first";
		}
	}

	public function evalExpr(e:Expr):Dynamic {
		if (e == null) return null;
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): i;
					case CFloat(f): f;
					case CString(s): s;
					case CBool(b): b;
					case CNull: null;
				}
			case EIdent(name): resolve(name);
			case EBarField(name): resolve(name);
			case EVar(name, init):
				var v = init != null ? evalExpr(init) : null;
				define(name, v);
				v;
			case EBlock(es):
				var start = 0;
				if (genResume != null) {
					switch (genResume) {
						case BlockResume(block, index) if (block == e):
							start = index;
							genResume = null;
						case BlockResume(block, _):
							if (exprContains(e, block)) start = findStmtIndex(e, block);
						case WhileResume(_, _):
					}
				}
				var r:Dynamic = null;
				for (i in start...es.length) {
					try {
						r = evalExpr(es[i]);
					} catch (ex:Dynamic) {
						if (isGeneratorYieldPause(ex)) {
							if (genResume == null) genResume = BlockResume(e, i + 1);
							throw ex;
						}
						throw ex;
					}
					if (returnFlag) return returnValue;
				}
				r;
			case EField(obj, f):
				var o = evalExpr(obj);
				if (o == null) return null;
				Reflect.getProperty(o, f);
			case EBinop(op, a, b): binop(op, a, b);
			case EUnop(op, prefix, x):
				var v = evalExpr(x);
				switch (op) {
					case "!": !truthy(v);
					case "-": -v;
					case "++": v + 1;
					case "--": v - 1;
					default: v;
				}
			case ECall(callee, args):
				callValue(evalExpr(callee), evalCallArgs(callee, args));
			case EIf(cond, eif, eelse):
				truthy(evalExpr(cond)) ? evalExpr(eif) : (eelse != null ? evalExpr(eelse) : null);
			case EWhile(cond, body):
				if (genResume != null) {
					switch (genResume) {
						case WhileResume(c, b) if (c == cond && b == body):
							genResume = null;
						default:
					}
				}
				var r:Dynamic = null;
				while (truthy(evalExpr(cond))) {
					try {
						r = evalExpr(body);
					} catch (ex:Dynamic) {
						if (isGeneratorYieldPause(ex)) {
							if (genResume == null) genResume = WhileResume(cond, body);
							throw ex;
						}
						throw ex;
					}
					if (returnFlag) return returnValue;
				}
				r;
			case EFor(name, it, body):
				var iter = MuseIters.from(evalExpr(it));
				var r:Dynamic = null;
				IterDriver.each(iter, function(item) {
					define(name, item);
					r = evalExpr(body);
				});
				r;
			case EFunction(args, body, kind, name):
				var fn = new FnClosure(args, body, stack.current(), name, kind);
				if (name != null) define(name, fn);
				fn;
			case EReturn(v):
				returnValue = v != null ? evalExpr(v) : null;
				returnFlag = true;
				returnValue;
			case EArray(obj, idx):
				var o = evalExpr(obj);
				var i = evalExpr(idx);
				if (Std.isOfType(o, Array)) return (cast o : Array<Dynamic>)[Std.int(i)];
				Reflect.getProperty(o, Std.string(i));
			case ELookback(series, n):
				evalLookback(series, Std.int(evalExpr(n)));
			case EArrayDecl(values): [for (v in values) evalExpr(v)];
			case EObject(fields):
				var o:Dynamic = {};
				for (f in fields) Reflect.setField(o, f.name, evalExpr(f.e));
				o;
			case ETernary(c, a, b): truthy(evalExpr(c)) ? evalExpr(a) : evalExpr(b);
			case EParent(x): evalExpr(x);
			case EMeta("__scr", [EConst(CInt(scrId))], ECall(EIdent(scrName), scrArgs))
				if (scrName == "macd" || scrName == "bbands" || scrName == "stoch"):
				// field-only result → per-callsite scratch object (CallsiteIds pass)
				var scrOut = harness.indCols.scratchObj(scrId);
				switch (scrName) {
					case "macd":
						TradeBuiltins.macd(harness, evalExpr(scrArgs[0]),
							scrArgs.length > 1 ? Std.int(evalExpr(scrArgs[1])) : 12,
							scrArgs.length > 2 ? Std.int(evalExpr(scrArgs[2])) : 26,
							scrArgs.length > 3 ? Std.int(evalExpr(scrArgs[3])) : 9,
							scrOut);
					case "bbands":
						TradeBuiltins.bbands(harness, evalExpr(scrArgs[0]), Std.int(evalExpr(scrArgs[1])),
							scrArgs.length > 2 ? (evalExpr(scrArgs[2]) : Float) : 2.0,
							scrOut);
					default:
						TradeBuiltins.stoch(harness,
							scrArgs.length > 0 ? Std.int(evalExpr(scrArgs[0])) : 14,
							scrArgs.length > 1 ? Std.int(evalExpr(scrArgs[1])) : 3,
							scrArgs.length > 2 ? Std.int(evalExpr(scrArgs[2])) : 3,
							scrOut);
				}
			case EMeta("__cs", [EConst(CInt(csId))], ECall(EIdent(csName), csArgs))
				if (csName == "crossover" || csName == "crossunder" || csName == "rising" || csName == "falling"):
				// static-callsite-id stateful builtin (CallsiteIds pass) — must
				// route through the same id-keyed state the JS backend uses.
				switch (csName) {
					case "crossover":
						TradeBuiltins.crossoverCS(harness, csId, evalExpr(csArgs[0]), evalExpr(csArgs[1]));
					case "crossunder":
						TradeBuiltins.crossunderCS(harness, csId, evalExpr(csArgs[0]), evalExpr(csArgs[1]));
					case "rising":
						TradeBuiltins.risingCS(harness, csId, evalExpr(csArgs[0]), Std.int(evalExpr(csArgs[1])),
							csArgs.length > 2 ? Std.int(evalExpr(csArgs[2])) : 0);
					default:
						TradeBuiltins.fallingCS(harness, csId, evalExpr(csArgs[0]), Std.int(evalExpr(csArgs[1])),
							csArgs.length > 2 ? Std.int(evalExpr(csArgs[2])) : 0);
				}
			case EMeta(_, _, x): evalExpr(x);
			case EMatch(scrutinee, arms): evalMatch(evalExpr(scrutinee), arms);
			case EYield(x):
				yieldValue(evalExpr(x));
				null;
			case EYieldStar(x):
				yieldStar(x);
				null;
		};
	}

	/**
	 * Series-typed call arguments authored as bar fields must pass the series
	 * *name* (`"high"`), not the current-bar float (`api.bar("high")`).
	 * Otherwise `window(high, n)` / `sma(high, n)` silently resolve to close.
	 */
	function evalCallArgs(callee:Expr, args:Array<Expr>):Array<Dynamic> {
		return switch (callee) {
			case EIdent(name):
				[for (i in 0...args.length) {
					var seriesName = BuiltinSigs.wantsSeries(name, i) ? BuiltinSigs.seriesNameOf(args[i]) : null;
					seriesName != null ? seriesName : evalExpr(args[i]);
				}];
			default:
				[for (a in args) evalExpr(a)];
		};
	}

	/**
	 * Series lookback: bar/ident → buffer index; call/other → re-eval on prefix length−n.
	 * ὁ δείκτης τοῦ κλήτου χθὲς ἦν ὁ αὐτὸς λογισμός ἐπὶ βραχυτέρου ἱστοῦ.
	 */
	function evalLookback(series:Expr, n:Int):Dynamic {
		return switch (series) {
			case EParent(inner):
				evalLookback(inner, n);
			case EBarField(name) | EIdent(name):
				harness.seriesLookback(name, n);
			case ECall(_, _):
				if (n <= 0) evalExpr(series);
				else {
					var self = this;
					harness.withSeriesOffset(n, function() return self.evalExpr(series));
				}
			default:
				// Non-series expr mistaken as lookback — try prefix re-eval; else NaN.
				if (n <= 0) evalExpr(series);
				else {
					var self = this;
					harness.withSeriesOffset(n, function() return self.evalExpr(series));
				}
		};
	}

	function yieldValue(v:Dynamic):Void {
		if (activeGenerator != null && activeGenerator.collecting)
			activeGenerator.pushYield(v);
		else
			Generator.doYield(v);
	}

	static function isGeneratorYieldPause(e:Dynamic):Bool {
		if (e == null) return false;
		var c = Type.getClass(e);
		if (c == null) return false;
		var n = Type.getClassName(c);
		return n == "musescript.runtime.GeneratorYieldPause"
			|| n == "musescript.runtime._Generator.GeneratorYieldPause";
	}

	static function exprContains(ancestor:Expr, target:Expr):Bool {
		if (ancestor == target) return true;
		return switch (ancestor) {
			case EBlock(es):
				for (x in es) if (exprContains(x, target)) return true;
				false;
			case EWhile(_, body): exprContains(body, target);
			case EIf(_, t, el): exprContains(t, target) || (el != null && exprContains(el, target));
			case EFor(_, _, body): exprContains(body, target);
			default: false;
		};
	}

	static function findStmtIndex(container:Expr, target:Expr):Int {
		switch (container) {
			case EBlock(es):
				for (i in 0...es.length)
					if (es[i] == target || exprContains(es[i], target)) return i;
			default:
		}
		return 0;
	}

	/** yield* — delegate when inside a collecting generator; else eager drain. */
	function yieldStar(e:Expr):Void {
		if (activeGenerator != null && activeGenerator.collecting)
			activeGenerator.delegateTo(MuseIters.from(evalExpr(e)));
		else
			IterDriver.each(MuseIters.from(evalExpr(e)), function(v) yieldValue(v));
	}

	function evalMatch(value:Dynamic, arms:Array<MatchArm>):Dynamic {
		for (arm in arms) {
			var bindings = new Map<String, Dynamic>();
			var patGuards:Array<Dynamic> = [];
			if (!matcher.tryPattern(arm.pattern, value, bindings, patGuards)) continue;
			var frame = new CallFrame(stack.current(), "match");
			for (k => v in bindings) frame.define(k, v);
			stack.push(frame);
			var ok = true;
			if (arm.guard != null) ok = truthy(evalExpr(arm.guard));
			if (ok) {
				for (g in patGuards) {
					if (!truthy(evalExpr(cast g))) {
						ok = false;
						break;
					}
				}
			}
			var result:Dynamic = null;
			if (ok) result = evalExpr(arm.body);
			stack.pop();
			if (ok) return result;
		}
		return null;
	}

	public function callValue(f:Dynamic, args:Array<Dynamic>):Dynamic {
		if (f == null) throw "Cannot call null";
		if (Std.isOfType(f, IndicatorInstance)) {
			var inst:IndicatorInstance = cast f;
			return callClosure(inst.closure, args);
		}
		if (Std.isOfType(f, FnClosure)) {
			var fn:FnClosure = cast f;
			if (fn.isGenerator()) {
				var frame = new CallFrame(fn.parent, fn.name);
				for (i in 0...fn.args.length) {
					frame.define(fn.args[i], i < args.length ? args[i] : null);
				}
				var gen = new Generator(fn, frame);
				gen.pauseAfterYield = true;
				var self = this;
				gen.evalBody = function(g:Generator) {
					self.activeGenerator = g;
					if (self.stack.current() != g.frame) self.stack.push(g.frame);
					self.returnFlag = false;
					try {
						self.evalExpr(fn.body);
						self.genResume = null;
					} catch (ex:Dynamic) {
						if (isGeneratorYieldPause(ex)) throw ex;
						if (Std.isOfType(ex, YieldSignal)) {
							g.pushYield((cast ex : YieldSignal).value);
						} else throw ex;
					}
					if (self.stack.current() == g.frame) self.stack.pop();
					self.activeGenerator = null;
					return null;
				};
				return gen;
			}
			return callClosure(fn, args);
		}
		if (Reflect.isFunction(f)) {
			return Reflect.callMethod(null, f, args);
		}
		throw 'Not callable: $f';
	}

	public function callClosure(fn:FnClosure, args:Array<Dynamic>):Dynamic {
		var frame = new CallFrame(fn.parent, fn.name != null ? fn.name : "<fn>");
		for (i in 0...fn.args.length) {
			frame.define(fn.args[i], i < args.length ? args[i] : null);
		}
		var stateObj:Dynamic = null;
		if (fn.indicatorState != null) {
			stateObj = {};
			for (k => v in fn.indicatorState) Reflect.setField(stateObj, k, v);
			frame.define("state", stateObj);
		}
		stack.push(frame);
		var prevRet = returnFlag;
		var prevVal = returnValue;
		returnFlag = false;
		returnValue = null;
		var result = evalExpr(fn.body);
		if (returnFlag) result = returnValue;
		if (stateObj != null && fn.indicatorState != null) {
			for (f in Reflect.fields(stateObj))
				fn.indicatorState.set(f, Reflect.field(stateObj, f));
		}
		returnFlag = prevRet;
		returnValue = prevVal;
		stack.pop();
		return result;
	}

	function binop(op:String, a:Expr, b:Expr):Dynamic {
		// short-circuit
		if (op == "&&") return truthy(evalExpr(a)) && truthy(evalExpr(b));
		if (op == "||") return truthy(evalExpr(a)) || truthy(evalExpr(b));
		if (op == "=") {
			var right = evalExpr(b);
			switch (a) {
				case EIdent(name):
					define(name, right);
					return right;
				case EField(obj, f):
					var o = evalExpr(obj);
					if (o == null) throw "assignment target is null";
					Reflect.setProperty(o, f, right);
					return right;
				default:
					throw "assignment target must be an identifier or field";
			}
		}
		var left = evalExpr(a);
		var right = evalExpr(b);
		return switch (op) {
			case "+":
				#if python
				if (isStringy(left) || isStringy(right))
					return Std.string(left) + Std.string(right);
				return toNum(left) + toNum(right);
				#else
				left + right;
				#end
			case "-": toNum(left) - toNum(right);
			case "*": toNum(left) * toNum(right);
			case "/": toNum(left) / toNum(right);
			case "%": toNum(left) % toNum(right);
			case "==": left == right;
			case "!=": left != right;
			case "<": toNum(left) < toNum(right);
			case "<=": toNum(left) <= toNum(right);
			case ">": toNum(left) > toNum(right);
			case ">=": toNum(left) >= toNum(right);
			default: throw 'Unknown op $op';
		};
	}

	static function isStringy(v:Dynamic):Bool {
		return Std.isOfType(v, String);
	}

	static function toNum(v:Dynamic):Float {
		if (v == null) return 0;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return cast v;
		#if python
		try {
			return python.Syntax.code("float({0})", v);
		} catch (_:Dynamic) {
			return 0;
		}
		#else
		return Std.parseFloat(Std.string(v));
		#end
	}

	function resolve(name:String):Dynamic {
		var r = stack.resolve(name);
		if (r != null) return r.value;
		if (globals.exists(name)) return globals.get(name);
		if (harness.params.all().exists(name)) return harness.params.get(name);
		return null;
	}

	function define(name:String, value:Dynamic):Void {
		var cur = stack.current();
		if (cur != null) {
			if (cur.bindings.exists(name)) cur.bindings.get(name).value = value;
			else cur.define(name, value);
		} else {
			globals.set(name, value);
		}
	}

	function truthy(v:Dynamic):Bool {
		if (v == null) return false;
		if (v == false) return false;
		if (v == 0) return false;
		if (v == "") return false;
		return true;
	}

	/**
	 * Run registered on(tick) handlers against a tick MuseIter.
	 * Defaults to harness `ticks` EventStream (LiveHarness pre-creates it).
	 * Not used during runBacktest — ticks are live/event-path only.
	 */
	public function dispatchTicks(?iter:MuseIter):Void {
		if (iter == null) {
			var stream = harness.eventStreams.get("ticks");
			if (stream == null) return;
			iter = stream;
		}
		var self = this;
		IterDriver.each(iter, function(tick) {
			self.bindTick(tick);
			for (h in self.onTickHandlers) {
				for (st in h) {
					switch (st) {
						case MatchFor(name, _, arms):
							var r = self.matcher.match(tick, arms);
							if (!r.matched) continue;
							var frame = new CallFrame(self.stack.current(), "tick");
							for (k => v in r.bindings) frame.define(k, v);
							self.stack.push(frame);
							self.define(name, r.bindings.exists(name) ? r.bindings.get(name) : null);
							var ok = true;
							if (r.guard != null) ok = self.truthy(self.evalExpr(r.guard));
							if (ok) self.evalExpr(r.body);
							self.stack.pop();
						default:
							self.execStmt(st);
					}
				}
			}
		});
	}

	/** Run registered on-event handlers against a MuseIter / EventLog (bindEvent per item). */
	public function dispatchEvents(streamName:String, iter:MuseIter):Void {
		if (iter == null) return;
		var self = this;
		var handlers = [for (h in onEventHandlers) if (h.stream == streamName || h.stream == "event") h];
		if (handlers.length == 0) return;

		// Snapshot once so plain per-event handlers and MatchFor can both see events.
		var events:Array<Dynamic> = MuseIters.toArray(iter);

		for (h in handlers) {
			var plain:Array<Stmt> = [];
			var matchers:Array<Stmt> = [];
			for (st in h.body) switch (st) {
				case MatchFor(_, _, _): matchers.push(st);
				default: plain.push(st);
			}
			for (event in events) {
				self.bindEvent(event);
				for (st in plain) self.execStmt(st);
			}
			if (matchers.length > 0) {
				var replay = MuseIters.from(events);
				for (st in matchers) switch (st) {
					case MatchFor(name, _, arms):
						var sm = new StreamMatcher(self.matcher);
						sm.matchFor(replay, arms, function(bindings, body) {
							var frame = new CallFrame(self.stack.current(), "event");
							for (k => v in bindings) frame.define(k, v);
							self.stack.push(frame);
							self.evalExpr(body);
							self.stack.pop();
						}, function(bindings, guard) {
							var frame = new CallFrame(self.stack.current(), "guard");
							for (k => v in bindings) frame.define(k, v);
							self.stack.push(frame);
							var ok = self.truthy(self.evalExpr(guard));
							self.stack.pop();
							return ok;
						});
					default:
				}
			}
		}
	}
}

/** Stepped generator resume point (see Generator INTERP HOOK). */
enum GenResume {
	BlockResume(block:Expr, index:Int);
	WhileResume(cond:Expr, body:Expr);
}
