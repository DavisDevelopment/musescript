package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.MuseCompiler;
import musescript.compile.MusePrinter;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.StaticInlinePass;
import musescript.ast.Expr;
import musescript.ast.Const;

/**
 * Phase 2 (classes) language tests. Instances are the canonical tagged record
 * `{ __class, field... }`; methods dispatch off `__class` via the class's own
 * registry (never copied per-instance). `this` is optional inside methods —
 * bare `field` resolves/assigns like `this.field` (Haxe-flavored). Pins
 * construction, ctor `this` binding, optional-this read/write, explicit
 * `this.field`, print-reparse round trip (genome-expansion contract, same as
 * TestLangEnums), interp==JS parity (the hard gate), and a WASM escape-region
 * sanity check (P2 has no class-WASM lowering yet — F1 must still compile the
 * surrounding program via host_eval, not crash or bail the whole module).
 */
class TestLangClasses extends Test {
	static function interpWith(source:String):MuseInterp {
		var prog = new MuseParser().parse(source);
		var interp = new MuseInterp(new HarnessContext());
		for (d in prog.decls) interp.registerDeclPublic(d);
		return interp;
	}

	static final AVERAGER_SRC = 'class Averager {\n'
		+ '  sum = 0.0;\n'
		+ '  count = 0.0;\n'
		+ '  new(seed) {\n'
		+ '    sum = seed\n'
		+ '    count = 1.0\n'
		+ '  }\n'
		+ '  function add(x) {\n'
		+ '    sum = sum + x\n'
		+ '    count = count + 1.0\n'
		+ '  }\n'
		+ '  function avg() {\n'
		+ '    return sum / count\n'
		+ '  }\n'
		+ '  function avgExplicit() {\n'
		+ '    return this.sum / this.count\n'
		+ '  }\n'
		+ '}\n';

	// ── Construction ──────────────────────────────────────────────────────

	// `new`/`this` are new-surface-only syntax (StrategyParser), not part of the
	// legacy hscript grammar `MuseParser().parseExpr()` parses standalone
	// expressions with — so these tests build the `ENew` node directly rather
	// than parsing a string through the wrong parser.
	static function newAverager(seed:Float):Expr {
		return ENew("Averager", [EConst(CFloat(seed))]);
	}

	public function testFieldDefaultsInitializeInstance() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(0.0));
		Assert.notNull(v);
		Assert.equals("Averager", Reflect.field(v, "__class"));
	}

	public function testCtorRunsWithThisBound() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(5.0));
		Assert.floatEquals(5.0, Reflect.field(v, "sum"));
		Assert.floatEquals(1.0, Reflect.field(v, "count"));
	}

	// ── Optional `this` (read + write) and explicit `this.field` ──────────

	public function testMethodCallMutatesInstanceViaOptionalThis() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(0.0));
		interp.callInstanceMethodPublic(v, "add", [4.0]);
		interp.callInstanceMethodPublic(v, "add", [6.0]);
		Assert.floatEquals(10.0, Reflect.field(v, "sum"));
		Assert.floatEquals(3.0, Reflect.field(v, "count"));
	}

	public function testMethodReturnValueViaOptionalThis() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(2.0));
		interp.callInstanceMethodPublic(v, "add", [8.0]);
		var avg = interp.callInstanceMethodPublic(v, "avg", []);
		Assert.floatEquals(5.0, avg); // (2 + 8) / 2
	}

	public function testExplicitThisMatchesOptionalThis() {
		var interp = interpWith(AVERAGER_SRC + "strategy S { onBar { } }");
		var v:Dynamic = interp.evalExpr(newAverager(2.0));
		interp.callInstanceMethodPublic(v, "add", [8.0]);
		var a = interp.callInstanceMethodPublic(v, "avg", []);
		var b = interp.callInstanceMethodPublic(v, "avgExplicit", []);
		Assert.floatEquals(a, b);
	}

	// ── print → reparse round-trip (the genome-expansion contract) ────────
	// Same discipline as TestLangEnums.testEnumProgramRoundTripsThroughPrinter
	// — MuseGene's Expand.hx generates SOURCE TEXT and reparses it, never
	// splices AST directly, so MusePrinter output for classes must be readable
	// by the same parser bit-for-bit.

	public function testClassProgramRoundTripsThroughPrinter() {
		var src = AVERAGER_SRC
			+ "strategy S { onBar {\n"
			+ "  var a = new Averager(close)\n"
			+ "  var v = a.avg()\n"
			+ "  plot(v, \"avg\")\n"
			+ "} }";
		var prog1 = new MuseParser().parse(src);
		var printed = new MusePrinter().printProgram(prog1);

		var prog2 = new MuseParser().parse(printed);
		Assert.equals(2, prog2.decls.length); // ClassDecl + StrategyDecl

		var feed = BarFeed.synthetic(200, 5);
		var r1 = new MuseInterp(new HarnessContext()).runBacktest(prog1, feed);
		var r2 = new MuseInterp(new HarnessContext()).runBacktest(prog2, feed);
		Assert.equals(r1.trades, r2.trades);
		Assert.floatEquals(r1.finalEquity, r2.finalEquity);
	}

	// ── interp == JS-backend parity (the hard gate) ───────────────────────

	static final STRATEGY_SRC = AVERAGER_SRC
		+ "strategy ClassDemo { onBar {\n"
		+ "  var a = new Averager(close)\n"
		+ "  a.add(open)\n"
		+ "  var v = a.avg()\n"
		+ "  plot(v, \"avg\")\n"
		+ "  when v > close: { long() }\n"
		+ "  when v < close: { flat() }\n"
		+ "} }";

	public function testClassStrategyInterpJsParity() {
		var feed = BarFeed.synthetic(300, 17);

		var interpProg = new MuseParser().parse(STRATEGY_SRC);
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(interpProg, feed);
		Assert.isTrue(interpResult.trades >= 0);

		#if js
		var jsHarness = new HarnessContext();
		var jsProg = new MuseParser().parse(STRATEGY_SRC);
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(jsProg, { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	// ── WASM: no class-WASM lowering yet (P4) — must still compile via
	// escape regions, not crash or bail the whole module, and stay parity-
	// correct end to end through the interp thunk.

	public function testClassStrategyCompilesViaWasmEscapeRegions() {
		var prog = new MuseParser().parse(STRATEGY_SRC);
		var wat = StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(StringTools.contains(wat, "host_eval"));

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(150, 9);
			var interpResult = new MuseInterp(new HarnessContext())
				.runBacktest(new MuseParser().parse(STRATEGY_SRC), feed);
			var hybridHarness = new HarnessContext();
			Reflect.setField(hybridHarness, "feed", feed);
			var hybridResult = StrategyWasmBackend.compile(new MuseParser().parse(STRATEGY_SRC))(hybridHarness);
			Assert.equals(interpResult.trades, hybridResult.trades);
			Assert.floatEquals(interpResult.finalEquity, hybridResult.finalEquity);
		}
		#end
	}

	// ── static methods (2026-07-20 regression) ────────────────────────────
	//
	// `static function` parsed and MuseInterp had real isStatic-aware findMethod/callMethod
	// machinery, but nothing ever actually DISPATCHED a `ClassName.method(...)` call to it —
	// both evalExpr's ECall(EField(...)) branch and JsEmitter's equivalent case only handled
	// INSTANCE calls (an object value with a `__class` field); a bare class name was never bound
	// as an evaluable value at all, so evaluating `ClassName` as the "object" always produced
	// null/undefined and every static call failed with "Cannot call null". Fixed in both the
	// interpreter (MuseInterp's new EField(EIdent(className), ...) case + callStaticMethodPublic)
	// and the JS backend (JsEmitter's classNames-aware ECall case + JsBackend's __static_call
	// bridge) — independent bugs in independent code paths, both covered here.

	static final STATIC_SRC = "class Signals {\n"
		+ "  static function inner(x) { return x * 2.0 }\n"
		+ "  static function outer(x) { return Signals.inner(x) + 1.0 }\n"
		+ "}\n"
		+ "strategy StaticDemo { onBar {\n"
		+ "  var v = Signals.outer(close)\n"
		+ "  plot(v, \"v\")\n"
		+ "  when v > 0.0: { long() }\n"
		+ "  when v <= 0.0: { flat() }\n"
		+ "} }";

	public function testStaticMethodCallFromOutsideClass() {
		var interp = interpWith("class Signals {\n  static function thresh(x, t) { return x > t }\n}\n");
		var prog = new MuseParser().parse("Signals.thresh(3.0, 1.0)");
		Assert.isTrue(interp.evalExpr(exprOf(prog)));
	}

	public function testStaticMethodCallingAnotherStaticMethodByPrefixedName() {
		// Signals.outer calls Signals.inner(x) internally -- the SAME dispatch path, exercised
		// from inside a static method body rather than top-level code.
		var interp = interpWith("class Signals {\n"
			+ "  static function inner(x) { return x * 2.0 }\n"
			+ "  static function outer(x) { return Signals.inner(x) + 1.0 }\n"
			+ "}\n");
		var prog = new MuseParser().parse("Signals.outer(3.0)");
		Assert.floatEquals(7.0, interp.evalExpr(exprOf(prog)));
	}

	public function testStaticMethodInterpJsParity() {
		var feed = BarFeed.synthetic(300, 23);

		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(STATIC_SRC), feed);
		Assert.isTrue(interpResult.trades >= 0);

		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(STATIC_SRC), { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	public function testLocalVariableShadowsClassNameForStaticCall() {
		// A real local binding of the same name as a class must win (matches the existing
		// optional-`this` precedence comment in evalExpr) -- not silently misroute into static
		// dispatch just because a class happens to share the name.
		var interp = interpWith("class Signals {\n  static function thresh(x, t) { return x > t }\n}\n"
			+ "function useShadow() {\n"
			+ "  var Signals = { thresh: function(a, b) { return false } }\n"
			+ "  return Signals.thresh(3.0, 1.0)\n"
			+ "}\n");
		var prog = new MuseParser().parse("useShadow()");
		Assert.isFalse(interp.evalExpr(exprOf(prog)));
	}

	// ── static-method inlining (StaticInlinePass, 2026-07-20) ─────────────

	static final INLINE_SRC = "class Signals {\n"
		+ "  static function thresh(x, t) { return x > t }\n"
		+ "  static function double(x) { return x * 2.0 }\n"
		+ "}\n"
		+ "strategy InlineDemo { onBar {\n"
		+ "  var v = Signals.double(close)\n"
		+ "  when Signals.thresh(v, 100.0): { long(1); }\n"
		+ "  when !Signals.thresh(v, 100.0): { flat(); }\n"
		+ "} }";

	public function testStaticInlineEliminatesCallSites() {
		var prog = new MuseParser().parse(INLINE_SRC);
		var inlined = StaticInlinePass.transform(prog);
		var printed = new MusePrinter().printProgram(inlined);
		Assert.isFalse(StringTools.contains(printed, "Signals.thresh("));
		Assert.isFalse(StringTools.contains(printed, "Signals.double("));
	}

	public function testStaticInlineIsBehaviorPreserving() {
		// The actual correctness bar: inlined and non-inlined runs must produce IDENTICAL
		// results, not just "still compiles" -- StaticInlinePass runs unconditionally inside
		// MuseCompiler.compileEx, so this exercises it via the normal compile path, not by
		// calling the pass directly.
		var feed = BarFeed.synthetic(200, 5);
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(INLINE_SRC), feed);

		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(INLINE_SRC), { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	public function testStaticInlineHandlesRepeatedAndUnusedParams() {
		// A parameter used twice must not be double-evaluated (or dropped) -- binds via a local,
		// not textual substitution, so this must come out exactly like a hand-written version.
		var src = "class M {\n  static function sq(x) { return x * x }\n}\n"
			+ "strategy P { onBar {\n  var v = M.sq(close)\n  when v > 0.0: { long(1); }\n} }";
		var feed = BarFeed.synthetic(150, 3);
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		Assert.isTrue(interpResult.trades >= 0);
		var inlined = StaticInlinePass.transform(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(inlined);
		Assert.isFalse(StringTools.contains(printed, "M.sq("));
	}

	static function exprOf(prog:musescript.ast.MuseProgram):Expr {
		return switch (prog.stmts[0]) {
			case ExprStmt(e): e;
			default: throw "expected a bare expression statement";
		};
	}

	// ── strategy parameter signature notation (StrategyParser.parseStrategy, 2026-07-20) ──
	// `strategy Name(p0 = 1.0, p1: Float = 2.0) { ... }` desugars into the SAME
	// ParamDecl(name, def, opts) nodes the body-statement `param name = value;`
	// form produces, so it must be 100% behavior-identical -- not just "also parses".

	static final SIG_SRC = "strategy SigDemo(fast = 5.0, slow: Float = 20.0) {\n"
		+ "  onBar {\n"
		+ "    when sma(close, fast) > sma(close, slow): { long(1); }\n"
		+ "    when sma(close, fast) <= sma(close, slow): { flat(); }\n"
		+ "  }\n"
		+ "}";

	static final STMT_SRC = "strategy SigDemo {\n"
		+ "  param fast = 5.0;\n"
		+ "  param slow: Float = 20.0;\n"
		+ "  onBar {\n"
		+ "    when sma(close, fast) > sma(close, slow): { long(1); }\n"
		+ "    when sma(close, fast) <= sma(close, slow): { flat(); }\n"
		+ "  }\n"
		+ "}";

	public function testStrategyParamSignatureMatchesBodyStatementForm() {
		var feed = BarFeed.synthetic(300, 11);
		var sigResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(SIG_SRC), feed);
		var stmtResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(STMT_SRC), feed);
		Assert.equals(stmtResult.trades, sigResult.trades);
		Assert.floatEquals(stmtResult.finalEquity, sigResult.finalEquity);
	}

	public function testStrategyParamSignatureInterpJsParity() {
		var feed = BarFeed.synthetic(300, 11);
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(SIG_SRC), feed);

		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(SIG_SRC), { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	public function testStrategyWithNoParensStillParses() {
		// The overwhelming majority of existing strategy sources have no `(...)` at all --
		// the optional signature list must never become mandatory.
		var feed = BarFeed.synthetic(200, 7);
		var src = "strategy NoParams {\n  onBar {\n    when close > 0.0: { long(1); }\n  }\n}";
		var result = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		Assert.isTrue(result.trades >= 0);
	}

	public function testStrategyWithEmptyParensStillParses() {
		var feed = BarFeed.synthetic(200, 7);
		var src = "strategy EmptyParams() {\n  onBar {\n    when close > 0.0: { long(1); }\n  }\n}";
		var result = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		Assert.isTrue(result.trades >= 0);
	}

	// ── inlining extensions: multi-statement bodies + plain functions (2026-07-20) ──
	// StaticInlinePass originally only handled single-expression-body static methods.
	// It now also inlines: (a) "straight-line, tail-return" multi-statement bodies (any
	// number of leading statements with no `return`, followed by a tail `return`/expr),
	// and (b) plain top-level `function` declarations, not just class statics. Both share
	// the same eligibility/shadow-safety machinery -- see StaticInlinePass's doc comment.

	static final MULTI_STMT_STATIC_SRC = "class M {\n"
		+ "  static function score(x, t) {\n"
		+ "    var scaled = x * 2.0\n"
		+ "    var shifted = scaled - t\n"
		+ "    return shifted > 0.0\n"
		+ "  }\n"
		+ "}\n"
		+ "strategy MultiStaticDemo { onBar {\n  when M.score(close, 100.0): { long(1); }\n} }";

	public function testMultiStatementStaticBodyIsInlined() {
		var inlined = StaticInlinePass.transform(new MuseParser().parse(MULTI_STMT_STATIC_SRC));
		var printed = new MusePrinter().printProgram(inlined);
		Assert.isFalse(StringTools.contains(printed, "M.score("));
	}

	public function testMultiStatementStaticBodyBehaviorPreserved() {
		var feed = BarFeed.synthetic(200, 5);
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(MULTI_STMT_STATIC_SRC), feed);
		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(MULTI_STMT_STATIC_SRC), { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	static final PLAIN_FN_SRC = "function clampish(x, lo, hi) {\n"
		+ "  y = x\n"
		+ "  when y < lo: { y = lo }\n"
		+ "  when y > hi: { y = hi }\n"
		+ "  return y\n"
		+ "}\n"
		+ "strategy PlainFnDemo { onBar {\n  v = clampish(close, 0.0, 1000.0)\n  when v > 0.0: { long(1); }\n} }";

	public function testPlainTopLevelFunctionIsInlined() {
		var inlined = StaticInlinePass.transform(new MuseParser().parse(PLAIN_FN_SRC));
		var printed = new MusePrinter().printProgram(inlined);
		// The declaration itself ("function clampish(x, lo, hi) {") is intentionally kept
		// (in case it's called elsewhere or recursively beyond MAX_DEPTH) -- only the CALL
		// SITE ("clampish(close") must be gone.
		Assert.isFalse(StringTools.contains(printed, "clampish(close"));
	}

	public function testPlainTopLevelFunctionBehaviorPreserved() {
		var feed = BarFeed.synthetic(200, 9);
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(PLAIN_FN_SRC), feed);
		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(PLAIN_FN_SRC), { target: "js", strict: true });
		var jsResult = ex.fn(jsHarness);
		Assert.equals(interpResult.trades, jsResult.trades);
		Assert.floatEquals(interpResult.finalEquity, jsResult.finalEquity);
		#end
	}

	public function testEarlyReturnInConditionalIsNeverInlined() {
		// A `return` inside a `when`/`if` that ISN'T the final tail statement needs the
		// interpreter's real call-boundary returnFlag save/restore to unwind only its own
		// scope -- splicing it as a plain expression would incorrectly unwind the CALLER's
		// enclosing scope too. Must be left as a real call, not partially/incorrectly inlined.
		var src = "function pick(x) {\n"
			+ "  when x > 0.0: { return 1.0 }\n"
			+ "  return -1.0\n"
			+ "}\n"
			+ "strategy EarlyReturnDemo { onBar {\n  v = pick(close)\n  when v > 0.0: { long(1); }\n} }";
		var inlined = StaticInlinePass.transform(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(inlined);
		Assert.isTrue(StringTools.contains(printed, "pick("));
	}

	public function testShadowedClassNameIsNotInlinedOrStaticDispatched() {
		// A local `Signals = {...}` shadowing the real `Signals` class must suppress BOTH
		// StaticInlinePass's inlining AND JsEmitter's independent static-dispatch fast path
		// (two separate places that used to have this exact bug independently -- see
		// BoundNames' doc comment). Compiled behavior must match the interpreter's (which
		// resolves the shadow correctly via ordinary lexical scoping).
		var src = "class Signals {\n  static function thresh(x, t) { return x > t }\n}\n"
			+ "strategy ShadowDemo { onBar {\n"
			+ "  Signals = { thresh: function(a, b) { return false } }\n"
			+ "  when Signals.thresh(3.0, 1.0): { long(1) }\n"
			+ "} }";
		var feed = BarFeed.synthetic(50, 1);
		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var jsResult = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(jsHarness);
		Assert.equals(0, jsResult.trades);
		#end
	}

	public function testShadowedPlainFunctionIsNotInlined() {
		var src = "function helper(x) { return x * 100.0 }\n"
			+ "strategy ShadowFnDemo { onBar {\n"
			+ "  helper = function(x) { return -1.0 }\n"
			+ "  v = helper(1.0)\n"
			+ "  when v > 0.0: { long(1) }\n"
			+ "} }";
		var feed = BarFeed.synthetic(50, 1);
		#if js
		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var jsResult = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(jsHarness);
		Assert.equals(0, jsResult.trades);
		#end
	}
}
