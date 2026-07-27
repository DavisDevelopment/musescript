package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.compile.ClassStrategyLower;
import musescript.compile.MusePrinter;
import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * Class-shaped declarations: `class X extends muse.Strat { ... }` and `extends muse.Indicator`.
 *
 * The contract is equivalence, not merely "it runs": a class-form strategy must lower to the
 * SAME declaration the equivalent `strategy` block produces, because that is what lets every
 * downstream pass, both emitters and the evolution substrate stay ignorant of classes. Most
 * tests here therefore compare the lowered program against a hand-written twin rather than
 * asserting on shapes in isolation.
 */
class TestLangClassStrategy extends Test {

	static function lower(src:String) {
		return ClassStrategyLower.expand(new MuseParser().parse(src));
	}

	/**
	 * The printed body of ONE named strategy. Named, because a base class that itself extends
	 * `muse.Strat` lowers to a strategy of its own — taking "the first one" would silently read
	 * the base while claiming to test the subclass.
	 */
	static function strategyText(src:String, name:String):String {
		var prog = lower(src);
		for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body) if (n == name):
				return new MusePrinter().printDecl(StrategyDecl(n, body));
			default:
		}
		return '<no strategy $name>';
	}

	static function declNames(src:String):Array<String> {
		var out = [];
		for (d in lower(src).decls) out.push(switch (d) {
			case StrategyDecl(n, _): 'strategy:$n';
			case IndicatorDecl(n, _, _): 'indicator:$n';
			case ParamDecl(n, _, _): 'param:$n';
			case ClassDecl(n, _, _, _, _): 'class:$n';
			default: "other";
		});
		return out;
	}

	// ---------- equivalence with the strategy surface ----------

	static final AS_CLASS = 'class MaCross extends muse.Strat {\n'
		+ '  param fast: Window = 10\n'
		+ '  param slow: Window = 30\n'
		+ '  f = sma(close, fast)\n'
		+ '  s = sma(close, slow)\n'
		+ '  function onBar() {\n'
		+ '    when crossover(f, s): long()\n'
		+ '    when crossunder(f, s): flat()\n'
		+ '  }\n'
		+ '}';

	static final AS_STRATEGY = 'strategy MaCross {\n'
		+ '  param fast: Window = 10\n'
		+ '  param slow: Window = 30\n'
		+ '  f = sma(close, fast)\n'
		+ '  s = sma(close, slow)\n'
		+ '  onBar {\n'
		+ '    when crossover(f, s): long()\n'
		+ '    when crossunder(f, s): flat()\n'
		+ '  }\n'
		+ '}';

	/**
	 * The equivalence that matters: same trades, same equity, through the real pipeline.
	 *
	 * Deliberately behavioural rather than an AST comparison. The two surfaces do NOT produce
	 * identical trees — inside a class method the parser folds `when c: x` through `stmtAsExpr`
	 * into an `EIf`, while a strategy body keeps a `When` statement that desugars to the same
	 * `if` later. Comparing prints would pin that incidental difference instead of the property
	 * anyone cares about.
	 */
	public function testClassFormRunsIdenticallyToEquivalentStrategyBlock() {
		var feed = BarFeed.synthetic(300, 11);
		var a = runBacktest(AS_CLASS, feed);
		var b = runBacktest(AS_STRATEGY, feed);
		Assert.equals(b.trades, a.trades, "trades");
		Assert.floatEquals(b.finalEquity, a.finalEquity, "finalEquity");
		Assert.isTrue(a.trades > 0, "the fixture actually trades, so the comparison means something");
	}

	/**
	 * The reason this is a lowering pass and not a runtime feature. MuseScript's class runtime is
	 * interpreter-only — `JsEmitter` throws on `EThis`/`ESuper` and `TestClassStructLowering`
	 * pins that a class with a parent escapes native lowering. A strategy that dispatched methods
	 * per bar would run interpreted, costing roughly 70x against the columnar path. Flattening at
	 * compile time is what buys real override semantics without paying that, so "it emitted" is
	 * the property to guard: if someone later makes the pass leave a class behind, this fails.
	 */
	public function testClassFormStaysOnTheCompiledPath() {
		var ex = MuseCompiler.compileEx(new MuseParser().parse(AS_CLASS), { target: "js", strict: true });
		Assert.equals("js", ex.backend);
		Assert.isTrue(ex.emitted, "class form must emit, not fall back to the interpreter");
	}

	public function testInheritedClassFormStaysOnTheCompiledPath() {
		var src = RISK_BASE + 'class Momentum extends RiskBase {\n'
			+ '  function onBar() { when crossover(sma(close, 10), sma(close, 30)): long() }\n'
			+ '}';
		var ex = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true });
		Assert.equals("js", ex.backend);
		Assert.isTrue(ex.emitted, "inheritance must be gone by the time a backend sees the program");
	}

	static function runBacktest(src:String, feed:Dynamic):Dynamic {
		var harness = new HarnessContext();
		Reflect.setField(harness, "feed", feed);
		return MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js" }).fn(harness);
	}

	public function testParamsHoistOutOfClassBodyLikeStrategyBody() {
		var names = declNames('class P extends muse.Strat {\n'
			+ '  param fast: Window = 10\n'
			+ '  function onBar() { when close > fast: long() }\n'
			+ '}');
		Assert.isTrue(names.indexOf("param:fast") >= 0, 'param hoisted (got $names)');
		Assert.isTrue(names.indexOf("strategy:P") >= 0, 'strategy emitted (got $names)');
	}

	public function testAllThreeLifecycleHooksLower() {
		var prog = lower('class H extends muse.Strat {\n'
			+ '  function onBar() { long() }\n'
			+ '  function onPosition() { flat() }\n'
			+ '  function onTick() { plot(close, "c") }\n'
			+ '}');
		var kinds = [];
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): for (s in body) kinds.push(switch (s) {
				case OnBar(_): "bar";
				case OnPosition(_): "pos";
				case OnTick(_): "tick";
				default: "other";
			});
			default:
		}
		Assert.same(["bar", "pos", "tick"], kinds);
	}

	// ---------- inheritance, resolved statically ----------

	static final RISK_BASE = 'class RiskBase extends muse.Strat {\n'
		+ '  param stop: Scalar = 0.05\n'
		+ '  function riskExit() { return unrealized_pnl_pct() < -stop }\n'
		+ '  function onPosition() { when riskExit(): flat() }\n'
		+ '  function onBar() { }\n'
		+ '}\n';

	public function testSubclassInheritsBaseHook() {
		var prog = lower(RISK_BASE
			+ 'class Momentum extends RiskBase {\n'
			+ '  function onBar() { when crossover(sma(close, 10), sma(close, 30)): long() }\n'
			+ '}');
		var momentum = null;
		for (d in prog.decls) switch (d) {
			case StrategyDecl("Momentum", body): momentum = body;
			default:
		}
		Assert.notNull(momentum, "Momentum lowered to a strategy");
		var kinds = [for (s in momentum) switch (s) {
			case OnBar(_): "bar"; case OnPosition(_): "pos"; default: "other";
		}];
		Assert.isTrue(kinds.indexOf("pos") >= 0, 'inherited onPosition present (got $kinds)');
		Assert.isTrue(kinds.indexOf("bar") >= 0, 'own onBar present (got $kinds)');
	}

	public function testSubclassOverrideWinsOverBase() {
		var txt = strategyText(RISK_BASE
			+ 'class Tight extends RiskBase {\n'
			+ '  function riskExit() { return bars_in_trade() > 3 }\n'
			+ '}', "Tight");
		Assert.isTrue(txt.indexOf("bars_in_trade") >= 0, 'override inlined into the hook: $txt');
		Assert.isTrue(txt.indexOf("unrealized_pnl_pct") < 0, 'base version must not survive: $txt');
	}

	public function testSuperMethodSplicesTheOverriddenVersion() {
		var txt = strategyText(RISK_BASE
			+ 'class Both extends RiskBase {\n'
			+ '  function riskExit() { return super.riskExit() || bars_in_trade() > 8 }\n'
			+ '}', "Both");
		Assert.isTrue(txt.indexOf("unrealized_pnl_pct") >= 0, 'super version spliced in: $txt');
		Assert.isTrue(txt.indexOf("bars_in_trade") >= 0, 'own condition kept: $txt');
	}

	public function testHelperMethodArgumentsSubstitute() {
		var txt = strategyText('class A extends muse.Strat {\n'
			+ '  function fast(n) { return ema(close, n) }\n'
			+ '  function onBar() { when fast(9) > fast(21): long() }\n'
			+ '}', "A");
		Assert.isTrue(txt.indexOf("9") >= 0 && txt.indexOf("21") >= 0,
			'both call sites substituted their own argument: $txt');
	}

	public function testThreeLevelChainFlattens() {
		var prog = lower('class L1 extends muse.Strat { function onBar() { long() } }\n'
			+ 'class L2 extends L1 { function onPosition() { flat() } }\n'
			+ 'class L3 extends L2 { function onTick() { plot(close, "c") } }');
		for (d in prog.decls) switch (d) {
			case StrategyDecl("L3", body):
				Assert.equals(3, body.length, "L3 gathers all three hooks from the chain");
			default:
		}
	}

	// ---------- indicators ----------

	public function testIndicatorClassLowersToIndicatorDecl() {
		var names = declNames('class Spread extends muse.Indicator {\n'
			+ '  function compute(src, len) { return ema(src, len) - sma(src, len) }\n'
			+ '}');
		Assert.isTrue(names.indexOf("indicator:Spread") >= 0, 'got $names');
	}

	// ---------- ordinary classes are untouched ----------

	public function testPlainClassIsLeftAlone() {
		var names = declNames('class Averager {\n'
			+ '  sum = 0.0;\n'
			+ '  function add(x) { sum = sum + x }\n'
			+ '}\n'
			+ 'strategy S { onBar { long() } }');
		Assert.isTrue(names.indexOf("class:Averager") >= 0,
			'a class with no builtin root keeps the class runtime (got $names)');
	}

	// ---------- diagnostics ----------

	public function testStrategyClassWithoutHookIsRejected() {
		Assert.raises(() -> lower('class Empty extends muse.Strat { x = 1 }'));
	}

	public function testConstructorOnDeclarationClassIsRejected() {
		Assert.raises(() -> lower('class C extends muse.Strat {\n'
			+ '  new() { }\n'
			+ '  function onBar() { long() }\n'
			+ '}'));
	}

	public function testUnknownParentIsRejected() {
		Assert.raises(() -> lower('class C extends NoSuch { function onBar() { long() } }'));
	}

	public function testRecursiveMethodIsRejectedRatherThanHanging() {
		Assert.raises(() -> lower('class R extends muse.Strat {\n'
			+ '  function loop() { return loop() }\n'
			+ '  function onBar() { when loop(): long() }\n'
			+ '}'));
	}

	public function testArityMismatchIsRejected() {
		Assert.raises(() -> lower('class R extends muse.Strat {\n'
			+ '  function f(a) { return a }\n'
			+ '  function onBar() { when f(1, 2) > 0: long() }\n'
			+ '}'));
	}
}
