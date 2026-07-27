package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.compile.ConstFold;
import musescript.compile.MusePrinter;
import musescript.compile.MuseCompiler;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * ConstFold (2026-07-20): folds literal arithmetic/comparison/logical sub-expressions and
 * eliminates statically-decidable `when`/`if`/ternary branches. Wired into MuseCompiler right
 * after StaticInlinePass specifically because inlining routinely substitutes literal default-
 * argument values into a call's body, which turns comparisons/conditions inside it fold-
 * eligible only AFTER splicing -- see MuseCompiler.compileEx and ConstFold's own doc comment.
 * Every fold here mirrors MuseInterp's runtime semantics (binop/truthy) exactly, by design, so
 * behavior-preservation is the real correctness bar, not just "still compiles".
 */
class TestConstFold extends Test {
	public function testArithmeticFoldsToLiteral() {
		var printed = new MusePrinter().printProgram(ConstFold.transform(new MuseParser().parse("2.0 * 3.0 + 1.0")));
		Assert.isTrue(StringTools.contains(printed, "7"));
		Assert.isFalse(StringTools.contains(printed, "*"));
	}

	public function testStringConcatFolds() {
		var printed = new MusePrinter().printProgram(ConstFold.transform(new MuseParser().parse('"a" + "b"')));
		Assert.isTrue(StringTools.contains(printed, '"ab"'));
	}

	public function testFalseConditionWhenIsDropped() {
		var src = "strategy DeadWhen { onBar {\n  when false: { long(1); }\n  when true: { short(1); }\n} }";
		var printed = new MusePrinter().printProgram(ConstFold.transform(new MuseParser().parse(src)));
		Assert.isFalse(StringTools.contains(printed, "long("));
		Assert.isTrue(StringTools.contains(printed, "short("));
		Assert.isFalse(StringTools.contains(printed, "when true"));
	}

	public function testShortCircuitAndDropsUnreachedRightOperand() {
		// `false && expr` never evaluates `expr` at runtime either -- dropping the whole `when`
		// at compile time is not a behavior change, just doing the same skip earlier.
		var src = "strategy ShortCircuit { onBar {\n  when false && (close > 0.0): { long(1); }\n} }";
		var printed = new MusePrinter().printProgram(ConstFold.transform(new MuseParser().parse(src)));
		Assert.isFalse(StringTools.contains(printed, "long("));
	}

	public function testNonConstantOperandLeftIntact() {
		var src = "strategy KeepReal { onBar {\n  when close > 5.0: { long(1); }\n} }";
		var printed = new MusePrinter().printProgram(ConstFold.transform(new MuseParser().parse(src)));
		Assert.isTrue(StringTools.contains(printed, "close"));
	}

	public function testCompoundsWithStaticInlining() {
		// A static helper called with LITERAL args: its internal comparison should fold away
		// entirely once StaticInlinePass splices the literal in, THEN ConstFold runs on it.
		var src = "class M {\n  static function over(x, t) { return x > t }\n}\n"
			+ "strategy Compound { onBar {\n  when M.over(5.0, 1.0): { long(1); }\n} }";
		var feed = BarFeed.synthetic(100, 3);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(h);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
		#end
	}

	public function testMixedFoldAndNoFoldPipelineParity() {
		var src = "strategy Mixed { onBar {\n"
			+ "  v = close * (2.0 - 1.0)\n"
			+ "  when true: { when v > 0.0: { long(1); } }\n"
			+ "  when 1.0 > 2.0: { short(1); }\n"
			+ "} }";
		var feed = BarFeed.synthetic(150, 4);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(h);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
		#end
	}

	public function testFloatArithmeticDoesNotTruncate() {
		// JVM Dynamic `+` used to unify ConstFold locals to Int (5.2-3.8 → 2). Must stay ~1.4.
		var printed = new MusePrinter().printProgram(ConstFold.transform(new MuseParser().parse("5.2 - 3.8")));
		Assert.isFalse(StringTools.contains(printed, "2"), 'expected fractional fold, got: $printed');
		Assert.isTrue(StringTools.contains(printed, "1.4") || StringTools.contains(printed, "1.400"),
			'expected ~1.4 fold, got: $printed');
	}

	public function testFloatComparisonFoldKeepsStrictInequality() {
		// 449.3 < 449.4 must stay true — Int truncation would make both 449 and fold to false.
		var printed = new MusePrinter().printProgram(
			ConstFold.transform(new MuseParser().parse("449.335876 < 449.46488714285715")));
		Assert.isTrue(StringTools.contains(printed, "true"), 'expected true fold, got: $printed');
	}

	// ── nested EBlock flattening (2026-07-20) ──────────────────────────────
	// Repeated StaticInlinePass splicing accumulates one block-nesting level per inline;
	// ConstFold flattens them back down since this language's EBlock never pushes a real
	// scope (see ConstFold's doc comment). The real correctness bar is generator safety:
	// MuseInterp's BlockResume matches a suspended block by AST node IDENTITY, so any block
	// containing a `yield` anywhere must be left untouched by the flattener.

	public function testChainedInliningFlattensAndBehaviorPreserved() {
		var src = "class C {\n"
			+ "  static function a(x) { return C.b(x) + 1.0 }\n"
			+ "  static function b(x) { return C.c(x) * 2.0 }\n"
			+ "  static function c(x) { return x - 3.0 }\n"
			+ "}\n"
			+ "strategy Chain { onBar {\n  v = C.a(close)\n  when v > 0.0: { long(1); }\n} }";
		var feed = BarFeed.synthetic(200, 6);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(h);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
		#end
	}

	public function testGeneratorBlocksSurviveFlatteningPass() {
		// Not about flattening actually firing here -- about it NOT corrupting a generator's
		// block identities just because the flattening pass now runs unconditionally on every
		// compile. A silent generator-resume break would show up as wrong/missing yields.
		var src = "function gen() {\n"
			+ "  yield 1.0\n"
			+ "  yield 2.0\n"
			+ "  yield 3.0\n"
			+ "}\n"
			+ "strategy GenDemo { onBar {\n"
			+ "  total = 0.0\n"
			+ "  for (v in gen()) { total = total + v }\n"
			+ "  when total > 5.0: { long(1); }\n"
			+ "} }";
		var feed = BarFeed.synthetic(50, 2);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js" }).fn(h);
		Assert.equals(before.trades, after.trades);
		#end
	}
}
