package musescript.runtime;

import musescript.ast.MuseProgram;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.parse.MuseParser;
import musescript.compile.ModuleExpand;
import musescript.compile.TemplateExpand;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.Metrics;
import musescript.interp.MuseInterp;
import musescript.builtins.TradeBuiltins;

/**
 * Bar-stepping debugger for the Strategy Studio, over the interp tier.
 *
 * Drives a backtest ONE BAR AT A TIME, pausing between bars, so the IDE can
 * step / set breakpoints / inspect state / evaluate watch expressions. The
 * per-bar sequence replicates BacktestEngine.run exactly —
 *   orders.beginBar(open, index) → observeBar(bar) → interp.execBar(bar) →
 *   orders.mark(close)
 * — and reuses MuseInterp.execBar (the same code a full run executes), so the
 * paused state at bar N is identical to a full run's state at bar N (pinned by
 * a parity test).
 *
 * Scope: bar stepping, bar-index breakpoints, conditional breakpoints (a watch
 * expression going true), state inspection, watch-eval, and post-bar guard
 * truth ("why did this fire"). Mid-bar line breakpoints (pausing inside the
 * AST walk) need a suspendable interpreter and are deferred.
 *
 * JS API (after `haxe build-runtime.hxml`):
 *   const dbg = new MuseDebugSession(source, barsArray);
 *   dbg.stepBar(); dbg.runToBar(50); dbg.continueRun();
 *   dbg.inspect(); dbg.evalWatch("sma(\"close\",20) - sma(\"close\",50)");
 *   dbg.result();  // final metrics once done
 */
@:expose("MuseDebugSession")
class MuseDebugSession {
	var harness:HarnessContext;
	var interp:MuseInterp;
	var bars:Array<Bar>;
	var idx:Int; // index of the last executed bar (-1 before any step)
	var breakBars:Map<Int, Bool>;
	var setupError:Null<String>;
	/** Top-level on(bar) guard conditions (when/if), for "why did this fire". */
	var guardConds:Array<Expr>;

	public function new(source:String, ?barsArray:Array<Dynamic>) {
		idx = -1;
		breakBars = new Map();
		setupError = null;
		guardConds = [];
		harness = new HarnessContext();
		bars = toBars(barsArray);
		try {
			var prog = parse(source);
			harness.feed = new BarFeed(bars);
			TradeBuiltins.resetCrossState();
			interp = new MuseInterp(harness);
			interp.setupRun(prog);
			collectGuards(prog);
		} catch (e:Dynamic) {
			setupError = Std.string(e);
		}
	}

	/** Add/remove a breakpoint at a bar index. */
	public function setBreakpoint(bar:Int, ?on:Bool = true):Void {
		if (on) breakBars.set(bar, true); else breakBars.remove(bar);
	}

	public function clearBreakpoints():Void breakBars = new Map();

	/**
	 * Execute the next bar (full BacktestEngine per-bar sequence). Returns
	 * { done:Bool, index:Int, bar:{...} } — done=true when the tape is exhausted.
	 */
	public function stepBar():Dynamic {
		if (setupError != null) return { done: true, error: setupError };
		if (idx + 1 >= bars.length) return { done: true, index: idx };
		idx++;
		var bar = bars[idx];
		harness.orders.beginBar(bar.open, bar.index, bar.high, bar.low);
		harness.observeBar(bar);
		interp.execBar(bar);
		harness.orders.mark(bar.close);
		return { done: idx + 1 >= bars.length, index: idx, bar: barObj(bar) };
	}

	/** Step until the bar at `n` has executed (or the tape ends). */
	public function runToBar(n:Int):Dynamic {
		var last:Dynamic = { done: idx + 1 >= bars.length, index: idx };
		while (idx < n) {
			last = stepBar();
			if (Reflect.field(last, "done") == true && idx < n) break;
		}
		return last;
	}

	/** Step until a bar-index breakpoint is hit or the tape ends. */
	public function continueRun():Dynamic {
		var last:Dynamic = stepBar();
		while (Reflect.field(last, "done") != true) {
			if (breakBars.exists(idx)) break;
			last = stepBar();
		}
		return last;
	}

	/**
	 * Snapshot of the current paused state: bar index, all in-scope numeric
	 * globals (locals + params + bar fields), and account state.
	 */
	public function inspect():Dynamic {
		var vars:Dynamic = {};
		for (name in interp.globals.keys()) {
			var v = interp.globals.get(name);
			if (Std.isOfType(v, Float) || Std.isOfType(v, Int) || Std.isOfType(v, Bool))
				Reflect.setField(vars, name, v);
		}
		var px = harness.currentBar != null ? harness.currentBar.close : 0.0;
		return {
			index: idx,
			done: idx + 1 >= bars.length,
			vars: vars,
			position: harness.orders.positionSize(),
			cash: harness.orders.cash,
			equity: harness.orders.equityAt(px),
			unrealizedPnl: harness.orders.unrealizedPnl(px),
			trades: harness.orders.trades
		};
	}

	/**
	 * Evaluate an arbitrary MuseScript expression against the current paused
	 * interpreter state (a REPL / watch). Returns { ok, value } or { ok:false }.
	 */
	public function evalWatch(exprSource:String):Dynamic {
		if (setupError != null) return { ok: false, error: setupError };
		try {
			// Wrap as a trivial expression statement and pull its parsed expr.
			var prog = parse("{ @strategy(\"__w\") @on(bar) { __w = (" + exprSource + "); } }");
			var e = extractWatchExpr(prog);
			if (e == null) return { ok: false, error: "could not parse watch expression" };
			return { ok: true, value: interp.evalExpr(e) };
		} catch (e:Dynamic) {
			return { ok: false, error: Std.string(e) };
		}
	}

	/**
	 * "Why did this fire": evaluate each top-level on(bar) guard condition
	 * (`when <cond>:` / `if (<cond>)`) against the current paused state and
	 * report its truth. For same-close strategies the post-bar state equals the
	 * decision-time state, so a `true` here is exactly a guard that fired this
	 * bar. Returns [{ src, truth }].
	 */
	public function guards():Array<Dynamic> {
		var out:Array<Dynamic> = [];
		var printer = new musescript.compile.MusePrinter();
		for (c in guardConds) {
			var truth:Null<Bool> = null;
			try {
				var v = interp.evalExpr(c);
				truth = v == true;
			} catch (_:Dynamic) {}
			var src = try printer.printExpr(c) catch (_:Dynamic) "<expr>";
			out.push({ src: src, truth: truth });
		}
		return out;
	}

	/** Final backtest metrics once stepping has reached the end (mirrors BacktestEngine.run). */
	public function result():Dynamic {
		// `harness.orders.equity` is a `GrowableVec<Float>` (see OrderSim.equity's doc comment);
		// materialize ONCE here, this `result` is `Dynamic` output (JS/debugger interop).
		var eq = harness.orders.equity.toArray();
		var rets = Metrics.returnsFromEquity(eq);
		return {
			done: idx + 1 >= bars.length,
			index: idx,
			bars: bars.length,
			equity: eq,
			fills: harness.orders.fills,
			chart: harness.chart.commands,
			logs: harness.logs,
			trades: harness.orders.trades,
			sharpe: finF(Metrics.sharpe(rets, 0)),
			maxDrawdown: finF(Metrics.maxDrawdown(eq)),
			winRate: finF(Metrics.winRate(harness.orders.wins, harness.orders.trades)),
			finalEquity: eq.length > 0 ? eq[eq.length - 1] : harness.orders.cash
		};
	}

	// --- internals ------------------------------------------------------------

	static function parse(source:String):MuseProgram {
		var prog = new MuseParser().parse(source, "<debug>");
		// Order: see MuseCompiler.compileEx's comment. ClassStrategyLower first so a
		// `class X extends muse.Strat` under the debugger lowers to a StrategyDecl before the
		// template/module passes (no-op without class-strategy roots); then TemplateExpand
		// before ModuleExpand — the reverse can't see `use` inside templates.
		prog = musescript.compile.ClassStrategyLower.expand(prog);
		prog = musescript.compile.MuseHostLower.lower(prog);
		prog = TemplateExpand.expand(prog);
		prog = ModuleExpand.expand(prog);
		return prog;
	}

	/** Collect top-level on(bar) guard conditions (when/if) for `guards()`. */
	function collectGuards(prog:MuseProgram):Void {
		function scanStmts(ss:Array<Stmt>):Void {
			for (s in ss) switch (s) {
				case OnBar(body): scanStmts(body);
				case Block(body): scanStmts(body);
				case When(cond, _): guardConds.push(cond);
				case ExprStmt(EIf(cond, _, _)): guardConds.push(cond);
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): scanStmts(body);
			default:
		}
		scanStmts(prog.stmts);
	}

	/** Pull the `__w = (<expr>)` right-hand side out of the wrapper program. */
	static function extractWatchExpr(prog:MuseProgram):Null<Expr> {
		var found:Null<Expr> = null;
		function scanStmts(ss:Array<Stmt>):Void {
			for (s in ss) switch (s) {
				case OnBar(body): scanStmts(body);
				case Block(body): scanStmts(body);
				case Assign("__w", e): found = e;
				case ExprStmt(EBinop("=", EIdent("__w"), e)): found = e;
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): scanStmts(body);
			default:
		}
		scanStmts(prog.stmts);
		return found;
	}

	function toBars(barsArray:Array<Dynamic>):Array<Bar> {
		if (barsArray == null) return BarFeed.synthetic(200, 1).all();
		var out:Array<Bar> = [];
		for (i in 0...barsArray.length) {
			var b = barsArray[i];
			out.push({
				open: num(b, "open"),
				high: num(b, "high"),
				low: num(b, "low"),
				close: num(b, "close"),
				volume: Reflect.hasField(b, "volume") ? num(b, "volume") : 0.0,
				time: Reflect.hasField(b, "time") ? num(b, "time") : (i : Float),
				index: i
			});
		}
		return out;
	}

	static function num(o:Dynamic, f:String):Float {
		var v:Dynamic = Reflect.field(o, f);
		return v == null ? Math.NaN : (v : Float);
	}

	static function barObj(bar:Bar):Dynamic {
		return { open: bar.open, high: bar.high, low: bar.low, close: bar.close,
			volume: bar.volume, time: bar.time, index: bar.index };
	}

	static function finF(x:Float):Null<Float> {
		return Math.isFinite(x) ? x : null;
	}
}
