package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.evo.Simplify;
import musescript.evo.Variation;
import musescript.evo.Canonical;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.harness.BarFeed;

/**
 * Regression coverage for Simplify.hx -- the semantic-equivalence-aware simplification pass wired
 * into EvolutionEngine.step so every crossover/mutation child gets cleaned up for free. Every rule
 * tested here is a real algebraic/logical identity, not a heuristic, so each test both checks the
 * STRUCTURAL collapse happened AND (where practical) that a real backtest produces IDENTICAL
 * results before and after simplification -- proving these are true equivalences, not lossy
 * approximations.
 */
class TestSimplify extends Test {
	static var TRUE:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
	static var FALSE:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	function baseGenome(entryLong:BoolNode):StrategyGenome {
		return {
			entryLong: entryLong,
			entryShort: FALSE,
			exitLong: FALSE,
			exitShort: FALSE,
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
	}

	function isAlwaysTrueShape(n:BoolNode):Bool
		return switch (n) { case BCmp(op, KConst(a), KConst(b)): evalCmpLocal(op, a, b) == true; default: false; }

	function isAlwaysFalseShape(n:BoolNode):Bool
		return switch (n) { case BCmp(op, KConst(a), KConst(b)): evalCmpLocal(op, a, b) == false; default: false; }

	function evalCmpLocal(op:String, a:Float, b:Float):Bool {
		return switch (op) {
			case ">": a > b; case "<": a < b; case ">=": a >= b;
			case "<=": a <= b; case "==": a == b; case "!=": a != b;
			default: false;
		};
	}

	// ── BAnd / BOr identities ──────────────────────────────────────────────────────────────

	public function testAndWithAlwaysTrueCollapsesToOtherSide() {
		var real = BCmp(">", KSeries(SPrice("close")), KConst(5.0));
		var s = Simplify.simplifyBool(BAnd(real, TRUE));
		Assert.isTrue(Type.enumEq(real, s), "expected structural passthrough of the surviving side"); // Type.enumEq: deep structural (not reference) equality -- see Haxe semantics note above simplifyBool tests
	}

	public function testAndWithAlwaysFalseCollapsesToFalse() {
		var real = BCmp(">", KSeries(SPrice("close")), KConst(5.0));
		var s = Simplify.simplifyBool(BAnd(real, FALSE));
		Assert.isTrue(isAlwaysFalseShape(s));
	}

	public function testOrWithAlwaysFalseCollapsesToOtherSide() {
		var real = BCmp("<", KSeries(SPrice("close")), KConst(5.0));
		var s = Simplify.simplifyBool(BOr(real, FALSE));
		Assert.isTrue(Type.enumEq(real, s));
	}

	public function testOrWithAlwaysTrueCollapsesToTrue() {
		var real = BCmp("<", KSeries(SPrice("close")), KConst(5.0));
		var s = Simplify.simplifyBool(BOr(real, TRUE));
		Assert.isTrue(isAlwaysTrueShape(s));
	}

	public function testAndOfIdenticalSubtreesCollapsesToOneCopy() {
		var real = BCmp(">", KSeries(SPrice("high")), KConst(3.0));
		var s = Simplify.simplifyBool(BAnd(real, BCmp(">", KSeries(SPrice("high")), KConst(3.0))));
		Assert.equals(0, Canonical.nodeCount(baseGenome(s)) - Canonical.nodeCount(baseGenome(real)));
	}

	public function testOrOfIdenticalSubtreesCollapsesToOneCopy() {
		var real = BCmp("<", KSeries(SPrice("low")), KConst(2.0));
		var s = Simplify.simplifyBool(BOr(real, BCmp("<", KSeries(SPrice("low")), KConst(2.0))));
		Assert.equals(Canonical.nodeCount(baseGenome(real)), Canonical.nodeCount(baseGenome(s)));
	}

	/** Regression: caught LIVE in a real corpus-evo run's champion output before this rule existed
	 * -- `(falling(...) && (ema1 > ema2)) && (ema1 > ema2)`, a conjunct repeated across a NESTED
	 * AND, not just the two immediate top-level operands (which `testAndOfIdenticalSubtreesCollapses
	 * ToOneCopy` above already covered). Confirms the deeper `conjunctSubsumedBy` search actually
	 * fires and collapses to just the two distinct conjuncts. */
	public function testNestedRepeatedConjunctCollapses() {
		var falling = BTrend("under", SInd("ema", "close", 5, null), 5);
		var emaCmp = BCmp(">", KSeries(SInd("ema", "close", 8, null)), KSeries(SInd("ema", "close", 34, null)));
		var nested = BAnd(BAnd(falling, emaCmp), emaCmp);
		var s = Simplify.simplifyBool(nested);
		var expected = BAnd(falling, emaCmp);
		Assert.isTrue(Type.enumEq(expected, s), 'expected the repeated conjunct dropped, got: $s');
	}

	public function testNestedRepeatedDisjunctCollapses() {
		var a = BCmp(">", KSeries(SPrice("close")), KConst(1.0));
		var b = BCmp("<", KSeries(SPrice("close")), KConst(9.0));
		var nested = BOr(BOr(a, b), b);
		var s = Simplify.simplifyBool(nested);
		Assert.isTrue(Type.enumEq(BOr(a, b), s));
	}

	// ── BNot ───────────────────────────────────────────────────────────────────────────────

	public function testDoubleNotCancels() {
		var real = BCmp(">", KSeries(SPrice("close")), KConst(1.0));
		var s = Simplify.simplifyBool(BNot(BNot(real)));
		Assert.isTrue(Type.enumEq(real, s));
	}

	// ── BCmp constant folding ──────────────────────────────────────────────────────────────

	public function testConstantComparisonFoldsToTrueOrFalse() {
		Assert.isTrue(isAlwaysTrueShape(Simplify.simplifyBool(BCmp(">", KConst(5.0), KConst(2.0)))));
		Assert.isTrue(isAlwaysFalseShape(Simplify.simplifyBool(BCmp(">", KConst(2.0), KConst(5.0)))));
		Assert.isTrue(isAlwaysTrueShape(Simplify.simplifyBool(BCmp("<=", KConst(2.0), KConst(2.0)))));
		Assert.isTrue(isAlwaysFalseShape(Simplify.simplifyBool(BCmp("<", KConst(2.0), KConst(2.0)))));
	}

	// ── BCmp self-comparison (a op a) ──────────────────────────────────────────────────────

	public function testSelfComparisonOfNonIndicatorFoldsByReflexivity() {
		var feat = KFeature("unrealized_pnl_pct()");
		Assert.isTrue(isAlwaysFalseShape(Simplify.simplifyBool(BCmp("<", feat, KFeature("unrealized_pnl_pct()")))));
		Assert.isTrue(isAlwaysTrueShape(Simplify.simplifyBool(BCmp(">=", feat, KFeature("unrealized_pnl_pct()")))));
		Assert.isTrue(isAlwaysFalseShape(Simplify.simplifyBool(BCmp(">", feat, KFeature("unrealized_pnl_pct()")))));
	}

	public function testSelfComparisonOfIndicatorIsNotFolded() {
		// Safety boundary: an indicator-containing self-comparison must NOT be folded (see
		// scalarEqForFold's doc comment) -- structurally unchanged.
		var ind = KSeries(SInd("sma", "close", 8, null));
		var n = BCmp("<", ind, KSeries(SInd("sma", "close", 8, null)));
		var s = Simplify.simplifyBool(n);
		Assert.isFalse(isAlwaysTrueShape(s));
		Assert.isFalse(isAlwaysFalseShape(s));
	}

	// ── BCross self-comparison ─────────────────────────────────────────────────────────────

	public function testCrossoverOfSeriesWithItselfIsAlwaysFalse() {
		var s = Simplify.simplifyBool(BCross("over", SPrice("close"), SPrice("close")));
		Assert.isTrue(isAlwaysFalseShape(s));
	}

	public function testCrossoverOfDifferentSeriesIsUnaffected() {
		var n = BCross("over", SPrice("close"), SInd("sma", "close", 8, null));
		var s = Simplify.simplifyBool(n);
		Assert.isTrue(Type.enumEq(n, s));
	}

	// ── KArith identities ──────────────────────────────────────────────────────────────────

	public function testArithIdentities() {
		var x = KSeries(SPrice("close"));
		Assert.isTrue(Type.enumEq(x, Simplify.simplifyScalar(KArith("+", x, KConst(0.0)))));
		Assert.isTrue(Type.enumEq(x, Simplify.simplifyScalar(KArith("-", x, KConst(0.0)))));
		Assert.isTrue(Type.enumEq(x, Simplify.simplifyScalar(KArith("+", KConst(0.0), x))));
		Assert.isTrue(Type.enumEq(x, Simplify.simplifyScalar(KArith("*", x, KConst(1.0)))));
		Assert.isTrue(Type.enumEq(x, Simplify.simplifyScalar(KArith("*", KConst(1.0), x))));
		switch (Simplify.simplifyScalar(KArith("*", x, KConst(0.0)))) {
			case KConst(0.0): Assert.pass();
			default: Assert.fail("expected a*0 to fold to KConst(0.0)");
		}
		switch (Simplify.simplifyScalar(KArith("min", x, KSeries(SPrice("close"))))) {
			case KSeries(SPrice("close")): Assert.pass();
			default: Assert.fail("expected min(a,a) to collapse to a");
		}
	}

	public function testConstantArithFolds() {
		switch (Simplify.simplifyScalar(KArith("+", KConst(2.0), KConst(3.0)))) {
			case KConst(v): Assert.floatEquals(5.0, v);
			default: Assert.fail("expected constant fold");
		}
	}

	// ── end-to-end: simplification preserves real backtest behavior ──────────────────────────

	/** The concrete degenerate shape this whole simplification pass exists for: `crossover(...) &&
	 * (1 > 0)`. Before simplification this renders as a literal tautological AND clause; after,
	 * it's just the crossover condition. Runs BOTH through Fitness.evaluate on the same tape and
	 * asserts byte-identical trades/equity -- proving the simplification is a true equivalence,
	 * not just a smaller-looking tree. */
	public function testSimplificationPreservesRealBacktestBehavior() {
		var v = new Variation(3);
		var redundantAnd:BoolNode = BAnd(
			BCross("over", SPrice("close"), SInd("sma", "close", 8, null)),
			TRUE
		);
		var g = baseGenome(redundantAnd);
		var simplified = Simplify.simplifyGenome(g, v);

		Assert.isTrue(Canonical.nodeCount(simplified) < Canonical.nodeCount(g),
			'expected simplification to shrink the genome: before=${Canonical.nodeCount(g)} after=${Canonical.nodeCount(simplified)}');

		var bars = BarFeed.synthetic(400, 5).all();
		var before = Fitness.evaluate(g, bars, "js", false);
		var after = Fitness.evaluate(simplified, bars, "js", false);
		Assert.isTrue(before.ok && after.ok);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
	}

	/** Idempotence: simplifying an already-simplified genome must be a no-op (same structural
	 * key) -- otherwise the pass could keep "simplifying" forever across generations. */
	public function testSimplificationIsIdempotent() {
		var v = new Variation(4);
		var g = baseGenome(BAnd(BCmp(">", KSeries(SPrice("close")), KConst(1.0)), TRUE));
		var once = Simplify.simplifyGenome(g, v);
		var twice = Simplify.simplifyGenome(once, v);
		Assert.equals(Canonical.structuralKey(once), Canonical.structuralKey(twice));
	}
}
