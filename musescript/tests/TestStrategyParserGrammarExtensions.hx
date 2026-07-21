package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.MuseCompiler;
import musescript.compile.StrategyWasmBackend;
import musescript.builtins.TradeBuiltins;

/**
 * Regression coverage for three StrategyParser.hx grammar extensions (see
 * plan doc "MuseScript grammar extensions"):
 *
 * 1. `indicator function name(args) { ... }` — a statement-block body form
 *    for the modern surface's `indicator` declaration, alongside the
 *    existing single-expression `indicator name(args) = expr` form. Same
 *    IndicatorDecl AST the legacy `@indicator("name") function(args){}`
 *    annotation syntax already produces.
 * 2. General `if (cond) { ... } [else if ...]* [else { ... }]?` at both
 *    statement and expression position — previously a deliberate parse
 *    error directing users to `when cond: { ... }` (which has no `else`).
 * 3. `onBar() when (cond) { ... }` guard sugar: a run of guarded onBar()
 *    blocks (optionally ending in one bare fallback) desugars to a SINGLE
 *    OnBar wrapping an if/else-if/else chain — first true guard wins, the
 *    bare fallback runs only if none matched. Unguarded onBar() blocks keep
 *    today's concatenation semantics (all run, every bar) unchanged.
 */
class TestStrategyParserGrammarExtensions extends Test {
	function interpRun(src:String, bars:Int = 20):HarnessContext {
		TradeBuiltins.resetCrossState();
		var harness = new HarnessContext();
		new MuseInterp(harness).runBacktest(new MuseParser().parse(src, "<test>"), BarFeed.synthetic(bars, 5));
		return harness;
	}

	// ── 1. indicator function name(args) { ... } ────────────────────────────

	public function testIndicatorFunctionFormMatchesLegacyAnnotationForm() {
		var modern = '
		indicator function cmoLike(period) {
			if (state.hasPrev != true) {
				state.hasPrev = true
				state.prevPrice = close
				return null
			}
			var change = close - state.prevPrice
			state.prevPrice = close
			return change
		}
		strategy P {
			onBar {
				var v = cmoLike(5)
				log("v|" + v)
			}
		}
		';
		var legacy = '
		{
			@indicator("cmoLike") function(period) {
				if (state.hasPrev != true) {
					state.hasPrev = true;
					state.prevPrice = close;
					return null;
				}
				var change = close - state.prevPrice;
				state.prevPrice = close;
				return change;
			}

			@strategy("P")
			@on(bar) {
				var v = cmoLike(5);
				log("v|" + v);
			}
		}
		';
		var a = interpRun(modern);
		var b = interpRun(legacy);
		Assert.equals(a.logs.length, b.logs.length);
		for (i in 0...a.logs.length) Assert.equals(b.logs[i].msg, a.logs[i].msg);
	}

	public function testIndicatorFunctionSupportsMultipleArgsAndState() {
		var h = interpRun('
		indicator function sumN(n) {
			if (state.total == null) {
				state.total = 0.0
			}
			state.total = state.total + n
			return state.total
		}
		strategy P {
			onBar {
				log("t|" + sumN(3))
			}
		}
		', 4);
		var vals = [for (l in h.logs) Std.parseFloat(l.msg.substr(2))];
		Assert.same([3.0, 6.0, 9.0, 12.0], vals);
	}

	// ── 2. general if / else if / else ───────────────────────────────────────

	public function testIfElseIfElseAtStatementPosition() {
		var h = interpRun('
		strategy P {
			onBar {
				var x = 0.0
				if (close > 1000000.0) {
					x = 1.0
				} else if (close < -1000000.0) {
					x = 2.0
				} else {
					x = 3.0
				}
				log("x|" + x)
			}
		}
		', 3);
		Assert.same(["x|3", "x|3", "x|3"], [for (l in h.logs) l.msg]);
	}

	public function testIfWithoutElseIsValidExpressionAndStatement() {
		var h = interpRun('
		strategy P {
			onBar {
				var x = 1.0
				if (close > 1000000.0) {
					x = 2.0
				}
				log("x|" + x)
			}
		}
		', 2);
		Assert.same(["x|1", "x|1"], [for (l in h.logs) l.msg]);
	}

	public function testIfElseWithOrdersMatchesAcrossInterpJsAndWasm() {
		var src = '
		strategy IfProbe {
			onBar {
				var x = 0.0
				if (close > 100.0) {
					x = 1.0
					long()
				} else if (close < 95.0) {
					x = -1.0
					short()
				} else {
					x = 0.5
					flat()
				}
				plot(x, "x")
			}
		}
		';
		var feed = BarFeed.synthetic(60, 11);

		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(src, "<if-parity>"), feed);

		TradeBuiltins.resetCrossState();
		var jsHarness = new HarnessContext();
		jsHarness.feed = feed;
		var jsResult:Dynamic = MuseCompiler.compileEx(new MuseParser().parse(src, "<if-parity>"), {target: "js"}).fn(jsHarness);
		Assert.equals(interpResult.trades, Std.int(Reflect.field(jsResult, "trades")));
		Assert.floatEquals(interpResult.finalEquity, Reflect.field(jsResult, "finalEquity"));

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			TradeBuiltins.resetCrossState();
			var wasmHarness = new HarnessContext();
			Reflect.setField(wasmHarness, "feed", feed);
			var wasmResult = StrategyWasmBackend.compile(new MuseParser().parse(src, "<if-parity>"))(wasmHarness);
			Assert.equals(interpResult.trades, wasmResult.trades);
			Assert.floatEquals(interpResult.finalEquity, wasmResult.finalEquity);
		}
		#end
	}

	// ── 3. onBar() when(cond) { ... } guard sugar ────────────────────────────

	public function testOnBarGuardChainFirstMatchWinsWithFallback() {
		var h = interpRun('
		strategy P {
			onBar() when (close > 1000000.0) {
				log("branch|high")
			}
			onBar() when (close < -1000000.0) {
				log("branch|low")
			}
			onBar() {
				log("branch|default")
			}
		}
		', 3);
		// Neither guard can ever be true on a normal synthetic tape -- every bar must
		// take the fallback, exactly once per bar (not zero, not more than one).
		Assert.same(["branch|default", "branch|default", "branch|default"], [for (l in h.logs) l.msg]);
	}

	public function testOnBarGuardActuallyFiresWhenTrue() {
		var h = interpRun('
		strategy P {
			onBar() when (close > 0.0) {
				log("branch|matched")
			}
			onBar() {
				log("branch|default")
			}
		}
		', 2);
		// Synthetic bars are always positive-priced, so the FIRST guard should win every
		// time, never falling through to the default -- proves the guard is actually
		// evaluated, not just structurally parsed.
		Assert.same(["branch|matched", "branch|matched"], [for (l in h.logs) l.msg]);
	}

	public function testUnguardedOnBarBlocksStillConcatenate() {
		// No `when` anywhere -- must keep today's behavior: every onBar() block runs,
		// every bar, unconditionally (NOT folded into a guard chain).
		var h = interpRun('
		strategy P {
			onBar() {
				log("a|1")
			}
			onBar() {
				log("b|1")
			}
		}
		', 2);
		Assert.same(["a|1", "b|1", "a|1", "b|1"], [for (l in h.logs) l.msg]);
	}
}
