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
import musescript.ast.ConstructOnce;
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
 * MuseScript tree-walking interpreter — the reference semantics every other
 * execution tier (JsBackend, WASM) is parity-tested against, and the only
 * steppable/debuggable tier (MuseDebugSession drives it bar by bar).
 *
 * ## Execution model
 * A program executes in two phases:
 * 1. **Registration** — `executeProgram` / `setupRun` walks top-level decls and
 *    statements once. `@on(bar)` / `@on(position)` / `@on(tick)` / `@on(<stream>)`
 *    bodies are NOT executed; they are collected into handler lists. Other
 *    top-level strategy-body statements land in `preludeStmts`.
 * 2. **Per-bar loop** — `execBar(bar)`: `bindBar` refreshes the ambient bar
 *    bindings (OHLCV + time/bar_index + auxiliary tape columns + @params),
 *    then prelude statements re-execute, then every @on(bar) body, then
 *    @on(position) bodies (only while a position/holding exists).
 *
 * ## Name resolution (`resolve`, innermost first)
 * call-stack frame bindings → `globals` (bar fields, builtins, top-level
 * assigns) → registered @params → null. Locals therefore shadow bar fields
 * and aux columns; `define` writes to the current frame when one exists,
 * else to globals.
 *
 * ## Series vs scalar arguments
 * Builtins whose signature wants a Series receive the series NAME (string)
 * when the argument is authored as a bar field or aux column identifier —
 * see `evalCallArgs`/`seriesNameOf` — so indicators get full history, not
 * the current-bar float.
 *
 * ## Control flow signals
 * `returnFlag`/`returnValue` implement early return (checked at the top of
 * `execStmt`); generators pause/resume via `YieldSignal` + `genResume`
 * (BlockResume/WhileResume mark the exact AST node to re-enter); pattern
 * matching delegates to PatternMatcher/StreamMatcher.
 *
 * Not a subclass of hscript.Interp — MuseScript semantics (handlers, series,
 * generators, match) diverge enough that sharing its walk would obscure both.
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

	/** Registered `ClassDecl`s, keyed by name. P2: `parent` is stored but unused (P3 wires it). */
	var classes:Map<String, {parent:Null<String>, fields:Array<{name:String, def:Null<Expr>}>,
		methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>,
		ctor:Null<{args:Array<String>, body:Expr}>}>;
	/** Stack of `this` receivers — top is the instance the currently-executing
	 * method/ctor body sees; empty outside any method. Supports nested/recursive
	 * method calls. Also backs optional-`this` resolution in `resolve`/`assignName`. */
	var instanceStack:Array<Dynamic>;
	/** Parallel to `instanceStack`: the class NAME each active method/ctor
	 * frame is lexically defined in (its "owner", from `findMethod` — may
	 * differ from the instance's runtime `__class` for an inherited method).
	 * `super`/`super.method()` resolve relative to this, not the instance. */
	var methodClassStack:Array<String>;

	public function new(harness:IHarness) {
		this.harness = Std.isOfType(harness, HarnessContext) ? cast harness : new HarnessContext();
		this.globals = new Map();
		this.classes = new Map();
		this.instanceStack = [];
		this.methodClassStack = [];
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
		musescript.builtins.WickraBuiltins.install(globals, harness);
		// `ta.` namespaced view of the same ported indicators + their
		// generated MuseScript sources (ta.source/sig/doc/names) — a plain
		// object global like `Math`, so no new dispatch surface.
		musescript.builtins.TaToolbelt.install(globals, harness);
		musescript.interp.MuseExtensions.installAll(globals, harness);
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

	/**
	 * Execute a whole program: register decls, run top-level statements, and —
	 * when the program declared @on(bar) handlers — immediately run a backtest
	 * over the harness's attached feed. A harness with no feed gets a
	 * deterministic synthetic tape (fixed seed) so bare scripts / REPL demos
	 * stay runnable with no data wired up; every real caller (GeneRunner,
	 * MuseRuntime, PlanRunner, …) attaches its feed first.
	 *
	 * Scope note (was a TODO): general non-strategy programs already execute
	 * here — decls + arbitrary statements with no @on(bar) simply return the
	 * last evaluated value. App-plugin support needs a capability surface
	 * (what a plugin may touch) before it needs anything from this method.
	 */
	public function executeProgram(prog:MuseProgram):Dynamic {
		for (d in prog.decls)
			registerDecl(d);
		for (s in prog.stmts)
			execStmt(s);

		if (onBarHandlers.length > 0) {
			var feed = harness.feed != null ? harness.feed : BarFeed.synthetic(300, 7);
			return harness.runBacktest(function(bar) execBar(bar), feed);
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
		// Idempotent (CallsiteIds re-wrapping an already-wrapped prog is a no-op re-walk) --
		// safe whether this program came in raw (bare MuseInterp usage: examples, tests, the
		// `@indicator` native-source pilot) or already passed through MuseCompiler's pipeline.
		// Without this, a bare-interp run of an `@indicator` declaration called twice with
		// different arguments in the same strategy silently shared one state map between the
		// two calls -- see IndicatorInstance.stateFor's doc comment.
		prog = musescript.compile.CallsiteIds.assign(prog);
		onBarHandlers = [];
		onPositionHandlers = [];
		onTickHandlers = [];
		onEventHandlers = [];
		preludeStmts = [];

		var self = this;
		harness.invokeUserFn = function(f:Dynamic, args:Array<Dynamic>):Dynamic {
			return self.callValue(f, args != null ? args : []);
		};

		for (d in prog.decls) 
			registerDecl(d);
		for (s in prog.stmts) 
			execStmt(s);
	}

	/**
	 * Per-bar handler execution: bindBar + prelude + on(bar) + on(position).
	 * The caller owns the surrounding harness bookkeeping (orders.beginBar,
	 * series observation, orders.mark) — see HarnessContext.runBacktest (full
	 * run) and MuseDebugSession.stepBar (stepped run), which drive it identically.
	 */
	public function execBar(bar:Bar):Void {
		bindBar(bar);
		for (st in preludeStmts) 
			execStmt(st);
		for (h in onBarHandlers) 
			for (st in h) 
				execStmt(st);
		if (harness.orders.position != 0 || harness.portfolio.holdings().length > 0)
			for (h in onPositionHandlers) 
				for (st in h) execStmt(st);
	}

	public function runPanelBacktest(prog:MuseProgram, panel:musescript.harness.PanelFeed):Dynamic {
		setupRun(prog);
		return harness.runPanelBacktest(function(bar) execBar(bar), panel);
	}

	public function registerDeclPublic(d:Decl):Void {
		registerDecl(d);
	}

	/** P2 hybrid: JsBackend bridges `new ClassName(...)` in emitted JS to this
	 * (construction stays interp-only — see JsEmitter's ENew case). */
	public function instantiatePublic(className:String, args:Array<Dynamic>):Dynamic {
		return instantiate(className, args);
	}

	/**
	 * P2 hybrid: JsBackend bridges `obj.method(...)` in emitted JS to this
	 * (dispatch stays interp-only — see JsEmitter's ECall(EField(...)) case).
	 * Mirrors evalExpr's ECall(EField(...)) branch exactly: a declared class
	 * method wins; otherwise falls back to calling whatever value the field
	 * itself holds (the pre-existing "field holds a callable" behavior).
	 */
	public function callInstanceMethodPublic(obj:Dynamic, methodName:String, args:Array<Dynamic>):Dynamic {
		if (obj != null && Reflect.hasField(obj, "__class")) {
			var m = findMethod(Reflect.field(obj, "__class"), methodName);
			if (m != null) return callMethod(obj, m, args);
		}
		var fieldVal = obj != null ? Reflect.getProperty(obj, methodName) : null;
		return callValue(fieldVal, args);
	}

	/** P2 hybrid: JsBackend bridges `ClassName.method(...)` (a STATIC call — no instance,
	 * `ClassName` names a class, not a variable) to this. Mirrors evalExpr's
	 * ECall(EField(EIdent(className), ...)) static-dispatch branch. Bare class names are never
	 * bound as evaluable JS values (there's nothing sensible for JsEmitter to emit for
	 * `ClassName` itself), so JsEmitter passes the class name through as a STRING literal
	 * instead of compiling `EIdent(className)` as a normal expression — see its ECall case. */
	public function callStaticMethodPublic(className:String, methodName:String, args:Array<Dynamic>):Dynamic {
		var m = findMethod(className, methodName);
		if (m == null) throw '$className.$methodName: static method not found';
		if (!m.isStatic) throw '$className.$methodName: not a static method (called without an instance)';
		return callMethod(null, m, args);
	}

	/**
	 * Hybrid WASM/interp compilation (F1/F3): run ONE escaped statement from a
	 * native-compiled strategy's on(bar)/on(position) body, against the SAME
	 * bar/harness the native side is mid-execution of, so orders/plots/series
	 * stay coherent across the WASM<->interp boundary. `this` interp instance
	 * should be a single seed reused across bars (created once per compiled
	 * strategy, with `prog.decls` already registered), not a fresh one per
	 * call — matching `StrategyWasmBackend.seedParams`'s existing pattern.
	 */
	var lastEscapeBar:Bar = null;

	/**
	 * F2: when this interp is running as a hybrid escape thunk (see
	 * `StrategyWasmBackend.makeEnv`), boundary-crossing names get a shared
	 * linear-memory slot instead of a normal interp global — `frameMap` maps
	 * name -> byte offset, `frameGetFn`/`frameSetFn` are the host-specific
	 * accessors (JS Float64Array view / Python wasmtime memory.read/write)
	 * bound once via `bindFramePublic`. Null/unset for every OTHER interp use
	 * (plain full-interp runs, MuseGene, tests, …) — zero behavior change
	 * there, `resolve`/`assignName` just skip the frame check.
	 */
	var frameMap:Null<Map<String, Int>> = null;
	var frameGetFn:Null<Int->Float> = null;
	var frameSetFn:Null<Int->Float->Void> = null;

	/** Wire this escape interp to the native side's shared variable frame (F2). */
	public function bindFramePublic(map:Map<String, Int>, getFn:Int->Float, setFn:Int->Float->Void):Void {
		frameMap = map;
		frameGetFn = getFn;
		frameSetFn = setFn;
	}

	public function runEscapeStmt(bar:Bar, s:Stmt):Void {
		// `bindBar` includes ONCE-PER-BAR resets (TradeBuiltins.beginBar's
		// crossover call-slot counter, indCols.beginBar's column cursor) that
		// assign state by ordinal call POSITION within a bar. A bar can now
		// produce several host_eval calls (one per escape region), so only the
		// FIRST call for a given bar (same Bar reference — `barRef[0]` is set
		// once per bar on the native side, before any host_eval fires) may
		// re-trigger those resets; later calls in the same bar just refresh
		// the plain value globals, or the slot counters would rewind mid-bar
		// and corrupt crossover/indicator state across escape regions.
		if (bar != lastEscapeBar) {
			bindBar(bar);
			lastEscapeBar = bar;
		} else {
			refreshBarGlobals(bar);
		}
		execStmt(s);
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
				if (name != null) 
					globals.set(name, fn);

			case IndicatorDecl(name, args, body):
				var closure = new FnClosure(args, body, stack.current(), name, Normal);
				var instance = new IndicatorInstance(closure, name);
				globals.set(name, instance);
				harness.indicators.register(name, instance);

			case MacroDecl(name, body):
				// Macro bodies executed by planner, not here
				globals.set('__macro_$name', body);

			case EnumDecl(_, variants):
				for (v in variants) registerEnumVariant(v.name, v.args.length);

			case ClassDecl(name, parent, fields, methods, ctor):
				classes.set(name, { parent: parent, fields: fields, methods: methods, ctor: ctor });

			case ModuleDecl(_, _, _) | TemplateDecl(_, _, _, _) | StmtTemplateDecl(_, _, _):
				// Expanded before execution / compile
		}
	}

	/**
	 * Bind one enum variant as a global. `tag`/`arity` are passed by value (not
	 * closed over from a loop var) so the constructor captures the correct tag —
	 * the loop-closure-capture footgun documented in [[musescript-hardening]].
	 * Nullary → a shared singleton; n-ary → a varargs constructor. Both produce
	 * the canonical `{ __tag, args:[...] }` PatternMatcher reads.
	 */
	function registerEnumVariant(tag:String, arity:Int):Void {
		if (arity == 0) {
			var singleton:Dynamic = {};
			Reflect.setField(singleton, "__tag", tag);
			Reflect.setField(singleton, "args", []);
			globals.set(tag, singleton);
		} else {
			globals.set(tag, Reflect.makeVarArgs(function(a:Array<Dynamic>):Dynamic {
				var rec:Dynamic = {};
				Reflect.setField(rec, "__tag", tag);
				Reflect.setField(rec, "args", a);
				return rec;
			}));
		}
	}

	/**
	 * Register a typed-surface `strategy { ... }` body with JsEmitter-parity
	 * semantics (collectStrategyHooks): Assign statements are a PER-BAR prelude
	 * (`fast = ema(close, 5)` must re-evaluate on every bar), hooks register as
	 * handlers, everything else keeps the historical run-once behavior. Executing
	 * assigns once at registration bound indicator locals before any bar existed,
	 * so interp-fallback backtests silently produced 0 trades.
	 *
	 * EXCEPT construct-once bindings (`c = new Counter()`, ast/ConstructOnce.hx)
	 * — `ENew` allocates NEW state, so treating it as an ordinary per-bar
	 * prelude assign would silently reconstruct (and thus reset) a stateful
	 * class instance every single bar, discarding whatever its methods
	 * accumulated. These run here, at REGISTRATION time, exactly once —
	 * matching how ParamDecl defaults are also evaluated once before any bar
	 * exists (same accepted limitation: a ctor reading bar fields like
	 * `close` sees null here, since no bar is bound yet).
	 */
	function registerStrategyBody(body:Array<Stmt>):Void {
		for (s in body) {
			switch (s) {
				case Assign(_, _) if (ConstructOnce.isConstructOnceAssign(s)):
					execStmt(s);
				case Assign(_, _):
					preludeStmts.push(s);
				case Block(inner):
					registerStrategyBody(inner);
				default:
					execStmt(s);
			}
		}
	}

	function bindBar(bar:Bar):Void {
		TradeBuiltins.beginBar();
		harness.indCols.beginBar();
		refreshBarGlobals(bar);
	}

	/** The idempotent, value-only half of `bindBar` — safe to re-run for a
	 * bar already bound (see `runEscapeStmt`), unlike the call-slot resets
	 * `bindBar` itself also performs. */
	function refreshBarGlobals(bar:Bar):Void {
		globals.set("open", bar.open);
		globals.set("high", bar.high);
		globals.set("low", bar.low);
		globals.set("close", bar.close);
		globals.set("volume", bar.volume);
		globals.set("time", bar.time);
		globals.set("bar_index", bar.index);
		// Auxiliary tape columns (extra CSV columns / Bar.data — e.g. PIT
		// fundamentals) resolve as bare identifiers exactly like OHLCV.
		// NaN when this bar doesn't carry the field. Without this they
		// silently evaluated to null → false, faking a 0-trade backtest.
		for (k in harness.auxSeriesNames())
			globals.set(k, harness.auxValue(k));
		// Refresh param bindings
		for (n in harness.params.names())
			globals.set(n, harness.params.get(n));
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
		if (Reflect.hasField(tick, "side")) {
			globals.set("side", Reflect.field(tick, "side"));
		}
		if (Reflect.hasField(tick, "symbol")) {
			globals.set("symbol", Reflect.field(tick, "symbol"));
		}
		for (n in harness.params.names()) {
			globals.set(n, harness.params.get(n));
		}
	}

	/**
	 * Bind order-flow / custom event fields onto globals (JsBackend.bindEvent parity).
	 * Exposes event/price/size/time plus kind/id/reason/px/qty/side/symbol when present.
	 */
	function bindEvent(event:Dynamic):Void {
		if (event == null) 
			return;

		globals.set("event", event);
		globals.set("price", tickField(event, ["price", "px", "last"], Math.NaN));
		globals.set("size", tickField(event, ["size", "qty", "volume"], 0));
		globals.set("time", tickField(event, ["time", "ts", "timestamp"], harnessNow()));

		inline function setIfPresent(field:String):Void {
			if (Reflect.hasField(event, field)) 
				globals.set(field, Reflect.field(event, field));
		}
		final fields = ["kind", "id", "reason", "px", "qty", "side", "symbol"];
		for (f in fields) {
			setIfPresent(f);
		}

		for (n in harness.params.names()) {
			globals.set(n, harness.params.get(n));
		}
	}

	function tickField(tick:Dynamic, names:Array<String>, def:Dynamic):Dynamic {
		for (n in names)
			if (Reflect.hasField(tick, n)) return Reflect.field(tick, n);
		return def;
	}

	function harnessNow():Float {
		return Reflect.hasField(harness, "now") ? Reflect.field(harness, "now") : 0;
	}

	/**
	 * Execute one statement for its effects. Statement kinds fall into three
	 * families (see the class doc for the phase model):
	 * - **Registration** (OnBar/OnPosition/OnTick/OnEvent): push the body onto
	 *   the matching handler list — never executed inline.
	 * - **Control** (Return/Yield/YieldStar/Block/When/For/MatchFor): Return
	 *   raises `returnFlag` so every enclosing execStmt unwinds without
	 *   executing further (checked first, below); yields route through the
	 *   active Generator; loop bodies re-enter execStmt per element.
	 * - **Effects** (ExprStmt/Order): Order maps Long/Short/Flat onto the
	 *   order book at the current bar's close.
	 * `Use` must never reach the interpreter — ModuleExpand resolves imports
	 * at parse time, so hitting one here is a pipeline bug worth throwing on.
	 */
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
				assignName(name, v);
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
				var arg:Dynamic = args.length > 0 ? evalExpr(args[0]) : null;
				var bi = harness.currentBar != null ? harness.currentBar.index : -1;
				var verb = switch (kind) {
					case Long: "long";
					case Short: "short";
					case Flat | Close: "flat";
				};
				harness.orders.submit(verb, arg, harness.currentBar.close, bi);
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
				switch (callee) {
					// Optional `this` for METHOD CALLS: a bare `speak()` inside
					// another method (no `this.`/receiver prefix) must ALSO
					// dispatch to the current instance's class — resolve() only
					// covers optional-this for FIELD reads, methods aren't
					// stored as instance fields at all (never copied per-
					// instance), so this needs its own check here. A real local
					// binding of the same name still wins (matches Haxe scoping).
					case EIdent(name) if (stack.resolve(name) == null):
						var inst = currentInstance();
						if (inst != null) {
							var m = findMethod(Reflect.field(inst, "__class"), name);
							if (m != null) return callMethod(inst, m, [for (a in args) evalExpr(a)]);
						}
						callValue(evalExpr(callee), evalCallArgs(callee, args));
					// STATIC method call: `ClassName.method(args)` where `ClassName` names a
					// registered class, not a variable. Bare class names are never bound as
					// evaluable values (ClassDecl execution only populates the separate
					// `classes` map, never `globals`/a stack frame — see the ClassDecl case
					// above), so falling through to the instance-call branch below (which
					// evaluates `objExpr` as a normal expression first) always got `obj == null`
					// and landed on "Cannot call null": `static function` parsed and had real
					// isStatic-aware findMethod/callMethod machinery, but nothing ever actually
					// reached it for the natural `ClassName.method()` call syntax. Checked before
					// the instance-call case so a real local variable that happens to SHADOW a
					// class name still resolves as a variable first (stack.resolve wins).
					case EField(EIdent(className), methodName) if (stack.resolve(className) == null && classes.exists(className)):
						var m = findMethod(className, methodName);
						if (m == null) throw '$className.$methodName: static method not found';
						if (!m.isStatic) throw '$className.$methodName: not a static method (called without an instance)';
						callMethod(null, m, [for (a in args) evalExpr(a)]);
					case EField(objExpr, methodName):
						var obj = evalExpr(objExpr);
						if (obj != null && Reflect.hasField(obj, "__class")) {
							var m = findMethod(Reflect.field(obj, "__class"), methodName);
							if (m != null) return callMethod(obj, m, [for (a in args) evalExpr(a)]);
						}
						// `this`-bound fallback (native Array/String/Map methods,
						// or a plain field holding a callable) — see callValue's
						// `recv` doc comment.
						var fieldVal = obj != null ? Reflect.getProperty(obj, methodName) : null;
						callValue(fieldVal, evalCallArgs(callee, args), obj);
					default:
						callValue(evalExpr(callee), evalCallArgs(callee, args));
				}
			case ENew(className, args):
				instantiate(className, [for (a in args) evalExpr(a)]);
			case EThis:
				currentInstance();
			case ESuper(method, args):
				evalSuper(method, [for (a in args) evalExpr(a)]);
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
			case EMeta("__cs", [EConst(CInt(csId))], ECall(EIdent(csName), csArgs))
				if (stack.resolve(csName) == null && Std.isOfType(globals.get(csName), IndicatorInstance)):
				// Same CallsiteIds mechanism as crossover/rising above, generalized to
				// user-declared @indicators -- see IndicatorInstance.stateFor's doc
				// comment for the bug this closes (two differently-parameterized calls
				// to the same @indicator sharing one state map).
				var inst:IndicatorInstance = cast globals.get(csName);
				callClosureWithState(inst.closure, [for (a in csArgs) evalExpr(a)], inst.stateFor(csId));
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
					var seriesName = BuiltinSigs.wantsSeries(name, i) ? seriesNameOf(args[i]) : null;
					seriesName != null ? seriesName : evalExpr(args[i]);
				}];
			// `ta.cmo(close, 14)` must resolve series-typed args to series
			// NAMES exactly like the flat `cmo(close, 14)` does — the toolbelt
			// exposes the same registry builtins, so it gets the same argument
			// discipline (BuiltinSigs is keyed by the identical flat name). A
			// local binding shadowing `ta` opts out, matching resolve() order.
			case EField(EIdent("ta"), name) if (stack.resolve("ta") == null):
				[for (i in 0...args.length) {
					var seriesName = BuiltinSigs.wantsSeries(name, i) ? seriesNameOf(args[i]) : null;
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

	/**
	 * `recv` (default null, unchanged behavior for every pre-existing call
	 * site) is the `this` binding for the plain-native-function case only —
	 * needed so `arr.push(x)`/other native-Array-or-String-method calls off a
	 * non-`__class` object actually mutate/read the RIGHT receiver instead of
	 * running detached (Reflect.getProperty(obj,f) fetches the function VALUE,
	 * losing which object it came from). Harmless for MuseScript-authored
	 * closures/builtins, which never reference `this`.
	 */
	public function callValue(f:Dynamic, args:Array<Dynamic>, ?recv:Dynamic):Dynamic {
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
			return Reflect.callMethod(recv, f, args);
		}
		throw 'Not callable: $f';
	}

	public function callClosure(fn:FnClosure, args:Array<Dynamic>):Dynamic {
		return callClosureWithState(fn, args, fn.indicatorState);
	}

	/** `callClosure` with an explicit state map — see IndicatorInstance.stateFor's doc comment
	 * for why a per-callsite map (not always `fn.indicatorState`) matters. */
	function callClosureWithState(fn:FnClosure, args:Array<Dynamic>, stateMap:Null<Map<String, Dynamic>>):Dynamic {
		var frame = new CallFrame(fn.parent, fn.name != null ? fn.name : "<fn>");
		for (i in 0...fn.args.length) {
			frame.define(fn.args[i], i < args.length ? args[i] : null);
		}
		var stateObj:Dynamic = null;
		if (stateMap != null) {
			stateObj = {};
			for (k => v in stateMap) Reflect.setField(stateObj, k, v);
			frame.define("state", stateObj);
		}
		stack.push(frame);
		var prevRet = returnFlag;
		var prevVal = returnValue;
		returnFlag = false;
		returnValue = null;
		var result = evalExpr(fn.body);
		if (returnFlag) result = returnValue;
		if (stateObj != null && stateMap != null) {
			for (f in Reflect.fields(stateObj))
				stateMap.set(f, Reflect.field(stateObj, f));
		}
		returnFlag = prevRet;
		returnValue = prevVal;
		stack.pop();
		return result;
	}

	function binop(op:String, a:Expr, b:Expr):Dynamic {
		// `&&`/`||` evaluate BOTH operands (no short-circuit) so that STATEFUL builtins
		// (crossover/crossunder/rising/falling — see CallsiteIds) update their per-bar state every
		// bar regardless of the boolean value of the other operand. Short-circuiting them skips the
		// state update on bars the operand isn't reached, leaving stale "previous value" state that
		// makes the signal fire at the wrong bars -- and it diverged from the WASM backend, which
		// has always emitted `a && b` / `a || b` as `i32.and`/`i32.or` over BOTH sides
		// (StrategyWasmEmitter.emitBinop). Evaluating both here makes the three backends agree and
		// matches Pine's series model (ta.* signals are computed every bar, not conditionally). The
		// left operand is still evaluated first, preserving evaluation order. Division by zero and
		// warmup NaNs are non-trapping (f64 inf/NaN, and the stateful builtins guard NaN inputs), so
		// eager evaluation of the second operand can't fault where short-circuit previously hid it.
		if (op == "&&") { var la = truthy(evalExpr(a)); var lb = truthy(evalExpr(b)); return la && lb; }
		if (op == "||") { var la = truthy(evalExpr(a)); var lb = truthy(evalExpr(b)); return la || lb; }

		if (op == "=") {
			var right = evalExpr(b);
			switch (a) {
				case EIdent(name):
					assignName(name, right);
					return right;
				case EField(obj, f):
					var o = evalExpr(obj);
					if (o == null) throw "assignment target is null";
					Reflect.setProperty(o, f, right);
					return right;
				case EArray(obj, idxExpr):
					var o = evalExpr(obj);
					if (o == null) throw "assignment target is null";
					var idx = evalExpr(idxExpr);
					// Mirrors the READ side's EArray case (evalExpr, ~line 691):
					// real Array -> index in place; any other object -> dynamic
					// field keyed by the index's string form.
					if (Std.isOfType(o, Array)) {
						(cast o : Array<Dynamic>)[Std.int(idx)] = right;
					} else {
						Reflect.setProperty(o, Std.string(idx), right);
					}
					return right;
				default:
					throw "assignment target must be an identifier, field, or index";
			}
		}

		// no short-circuit
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
		} 
		catch (_:Dynamic) {
			return 0;
		}
		#else
		return Std.parseFloat(Std.string(v));
		#end
	}

	/**
	 * BuiltinSigs.seriesNameOf plus runtime auxiliary tape columns: a bare
	 * identifier naming an aux series (and not shadowed by a local binding)
	 * is passed to series-typed builtin args as the series NAME, so
	 * `sma(my_fund_col, 5)` sees full history — matching how `close` etc.
	 * are passed, and killing the old `sma("my_fund_col", 1)` workaround.
	 */
	function seriesNameOf(e:Expr):Null<String> {
		var n = BuiltinSigs.seriesNameOf(e);
		if (n != null) return n;
		return switch (e) {
			case EIdent(id) | EBarField(id) if (stack.resolve(id) == null && harness.isAuxSeries(id)): id;
			case EParent(inner): seriesNameOf(inner);
			default: null;
		};
	}

	function resolve(name:String):Dynamic {
		var r = stack.resolve(name);
		if (r != null)
			return r.value;
		// F2 (hybrid escape thunk only — see bindFramePublic): a boundary-
		// crossing name reads through the SAME shared memory slot the native
		// WASM side uses, not a normal interp global.
		if (frameMap != null && frameMap.exists(name))
			return frameGetFn(frameMap.get(name));
		// Optional `this` (Haxe-flavored): a bare identifier not bound by any
		// frame resolves to the current method receiver's field of that name,
		// BEFORE falling to globals/params — matching `this.field` semantics
		// without requiring the `this.` prefix.
		var inst = currentInstance();
		if (inst != null && Reflect.hasField(inst, name))
			return Reflect.field(inst, name);
		if (globals.exists(name))
			return globals.get(name);
		if (harness.params.all().exists(name))
			return harness.params.get(name);

		return null;
	}

	function define(name:String, value:Dynamic):Void {
		var cur = stack.current();
		if (cur != null) {
			if (cur.bindings.exists(name)) {
				cur.bindings.get(name).value = value;
			}
			else {
				cur.define(name, value);
			}
		}
		else {
			globals.set(name, value);
		}
	}

	/**
	 * Bare-identifier ASSIGNMENT (`x = expr`, not `var x = expr`) — used by
	 * `Stmt.Assign` and the hscript `=` binop's `EIdent` target. Unlike
	 * `define` (always declares/updates a binding in the CURRENT frame, the
	 * correct behavior for `var`), a plain assignment must check, in order:
	 * an existing frame-local shadow, then the current method receiver's
	 * field of that name (optional-`this` WRITE), then fall back to
	 * declaring in the current frame / globals exactly like `define`.
	 */
	function assignName(name:String, value:Dynamic):Void {
		var cur = stack.current();
		if (cur != null && cur.bindings.exists(name)) {
			cur.bindings.get(name).value = value;
			return;
		}
		// F2 (hybrid escape thunk only): write through to the shared frame slot.
		if (frameMap != null && frameMap.exists(name)) {
			frameSetFn(frameMap.get(name), value);
			return;
		}
		var inst = currentInstance();
		if (inst != null && Reflect.hasField(inst, name)) {
			Reflect.setField(inst, name, value);
			return;
		}
		if (cur != null) {
			cur.define(name, value);
		} else {
			globals.set(name, value);
		}
	}

	function currentInstance():Dynamic {
		return instanceStack.length > 0 ? instanceStack[instanceStack.length - 1] : null;
	}

	/**
	 * Allocate an instance, run field initializers PARENT-FIRST across the
	 * whole `extends` chain (so a child's default for a same-named field
	 * overrides the parent's, and a field ANY ancestor declares is always
	 * present by the time a ctor runs), then chain ctors starting from the
	 * most-derived class (see `runCtorChain`).
	 */
	function instantiate(className:String, argVals:Array<Dynamic>):Dynamic {
		if (!classes.exists(className)) throw 'Unknown class: $className';
		var inst:Dynamic = {};
		Reflect.setField(inst, "__class", className);
		instanceStack.push(inst);
		try {
			initFieldsChain(className);
			runCtorChain(className, argVals);
		} catch (ex:Dynamic) {
			instanceStack.pop();
			throw ex;
		}
		instanceStack.pop();
		return inst;
	}

	function initFieldsChain(className:String):Void {
		var cls = classes.get(className);
		if (cls == null) return;
		if (cls.parent != null) initFieldsChain(cls.parent);
		var inst = currentInstance();
		for (f in cls.fields)
			Reflect.setField(inst, f.name, f.def != null ? evalExpr(f.def) : null);
	}

	/**
	 * Runs `className`'s own ctor (with `this` still the SAME instance already
	 * on `instanceStack` — no new push) if it has one; otherwise, Haxe-style
	 * implicit chaining, falls through to the parent's ctor with the SAME
	 * `argVals` a subclass that omits its own constructor entirely still needs
	 * to run its ancestor's setup. An explicit `super(...)` inside a ctor body
	 * (see `evalSuper`) reaches this same function with the PARENT's name and
	 * whatever args the user actually wrote, taking over from there.
	 */
	function runCtorChain(className:String, argVals:Array<Dynamic>):Void {
		var cls = classes.get(className);
		if (cls == null) return;
		if (cls.ctor != null) {
			var frame = new CallFrame(stack.current(), '$className.new');
			for (i in 0...cls.ctor.args.length)
				frame.define(cls.ctor.args[i], i < argVals.length ? argVals[i] : null);
			stack.push(frame);
			methodClassStack.push(className);
			var prevRet = returnFlag, prevVal = returnValue;
			returnFlag = false;
			returnValue = null;
			evalExpr(cls.ctor.body);
			returnFlag = prevRet;
			returnValue = prevVal;
			methodClassStack.pop();
			stack.pop();
		} else if (cls.parent != null) {
			runCtorChain(cls.parent, argVals);
		}
	}

	/**
	 * Method resolution walks the `extends` chain starting at `className` —
	 * a subclass's own method wins over an inherited one of the same name
	 * (standard override/virtual-dispatch), found simply by checking the
	 * subclass's own method list BEFORE recursing to `cls.parent`. `owner` is
	 * the class the definition actually came from (may differ from
	 * `className` for an inherited/un-overridden method) — `callMethod` needs
	 * it so a `super.m()` INSIDE that method resolves relative to ITS class,
	 * not the runtime instance's most-derived `__class`.
	 */
	function findMethod(className:String, methodName:String):Null<{name:String, args:Array<String>, body:Expr, isStatic:Bool, owner:String}> {
		var cls = classes.get(className);
		if (cls == null) return null;
		for (m in cls.methods)
			if (m.name == methodName)
				return { name: m.name, args: m.args, body: m.body, isStatic: m.isStatic, owner: className };
		if (cls.parent != null) return findMethod(cls.parent, methodName);
		return null;
	}

	function callMethod(inst:Dynamic, m:{name:String, args:Array<String>, body:Expr, isStatic:Bool, owner:String}, argVals:Array<Dynamic>):Dynamic {
		var frame = new CallFrame(stack.current(), m.name);
		for (i in 0...m.args.length)
			frame.define(m.args[i], i < argVals.length ? argVals[i] : null);
		stack.push(frame);
		instanceStack.push(inst);
		methodClassStack.push(m.owner);
		var prevRet = returnFlag, prevVal = returnValue;
		returnFlag = false;
		returnValue = null;
		var result = evalExpr(m.body);
		if (returnFlag) result = returnValue;
		returnFlag = prevRet;
		returnValue = prevVal;
		methodClassStack.pop();
		instanceStack.pop();
		stack.pop();
		return result;
	}

	/**
	 * `super(args)` (method == null) chains to the parent's ctor via the SAME
	 * `runCtorChain` used for implicit chaining — same instance, no new
	 * `instanceStack` push. `super.method(args)` dispatches starting from the
	 * PARENT of the LEXICAL class the currently-executing method/ctor is
	 * defined in (`methodClassStack`'s top), not the runtime instance's
	 * `__class` — otherwise a 3+ level `super.m()` chain inside an overridden
	 * method would re-dispatch to itself instead of walking upward.
	 */
	function evalSuper(method:Null<String>, argVals:Array<Dynamic>):Dynamic {
		var inst = currentInstance();
		if (inst == null) throw "super used outside a method/ctor";
		var definingClass = methodClassStack.length > 0
			? methodClassStack[methodClassStack.length - 1]
			: Reflect.field(inst, "__class");
		var cls = classes.get(definingClass);
		if (cls == null || cls.parent == null)
			throw 'super: $definingClass has no parent class';
		if (method == null) {
			runCtorChain(cls.parent, argVals);
			return null;
		}
		var m = findMethod(cls.parent, method);
		if (m == null) throw 'super.$method: not found in $definingClass\'s parent chain';
		return callMethod(inst, m, argVals);
	}

	function truthy(v:Dynamic):Bool {
		// Type-checked, not `v == false` / `v == 0` / `v == ""` -- those relied on JS's loose
		// `==` coercion across types (works fine there: `true == 0` is just `false`, no error).
		// On the JVM target, Haxe's Dynamic `==` codegen against a numeric literal tries to
		// numeric-coerce ANY value including a genuine Boolean, throwing ClassCastException
		// instead of returning false. Same truthiness semantics on every target either way.
		if (v == null) return false;
		if (Std.isOfType(v, Bool)) return (v : Bool);
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float) != 0;
		if (Std.isOfType(v, String)) return (v : String).length > 0;
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
			if (stream == null)
				return;
			iter = stream;
		}

		var self = this;
		IterDriver.each(iter, function(tick) {
			self.bindTick(tick);
			for (h in self.onTickHandlers) {
				for (st in h) {
					switch (st) {
						/*
						MatchFor arms are evaluated in a fresh CallFrame per tick, so the
						bindings are isolated and the guard is evaluated in the same frame.
						*/
						case MatchFor(name, _, arms):
							var r = self.matcher.match(tick, arms);
							if (!r.matched)
								continue;

							// bind onto the matched arm's own CallFrame so the guard sees the bindings
							var frame = new CallFrame(self.stack.current(), "tick");
							for (k => v in r.bindings) 
								frame.define(k, v);
							self.stack.push(frame);
							self.define(name, r.bindings.exists(name) ? r.bindings.get(name) : null);

							// that yupstuff
							var ok = true;
							if (r.guard != null) 
								ok = self.truthy(self.evalExpr(r.guard));
							if (ok) 
								self.evalExpr(r.body);
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
		if (iter == null) 
			return;

		var self = this;
		var handlers = [for (h in onEventHandlers) if (h.stream == streamName || h.stream == "event") h];
		if (handlers.length == 0) 
			return;

		// Snapshot once so plain per-event handlers and MatchFor can both see events.
		var events:Array<Dynamic> = MuseIters.toArray(iter);

		for (h in handlers) {
			var plain:Array<Stmt> = [];
			var matchers:Array<Stmt> = [];
			for (st in h.body) {
				switch (st) {
					case MatchFor(_, _, _): matchers.push(st);
					default: plain.push(st);
				}
			}

			for (event in events) {
				self.bindEvent(event);
				for (st in plain) 
					self.execStmt(st);
			}

			if (matchers.length > 0) {
				var replay = MuseIters.from(events);
				for (st in matchers) {
					switch (st) {
						// MatchFor arms are evaluated in a fresh CallFrame per event, so the
						// bindings are isolated and the guard is evaluated in the same frame.
						case MatchFor(name, _, arms):
							var sm = new StreamMatcher(self.matcher);

							/*
							define the per-arm callbacks for the stream matcher. 
							The `bb` callback is called when a match is found, 
							and the `bg` callback is called to evaluate the guard expression.
							*/
							function bb(bindings:Map<String, Dynamic>, body:musescript.ast.Expr) {
								var frame = new CallFrame(self.stack.current(), "event");
								for (k => v in bindings)
									frame.define(k, v);
								self.stack.push(frame);
								self.evalExpr(body);
								self.stack.pop();
							}
							function bg(bindings:Map<String, Dynamic>, guard:musescript.ast.Expr):Bool {
								var frame = new CallFrame(self.stack.current(), "guard");
								for (k => v in bindings)
									frame.define(k, v);
								self.stack.push(frame);
								var ok = self.truthy(self.evalExpr(guard));
								self.stack.pop();
								return ok;
							}

							sm.matchFor(replay, arms, bb, bg);

						default:
					}
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
