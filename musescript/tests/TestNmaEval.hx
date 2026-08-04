package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.GrowableVec;
import musescript.harness.HarnessContext;
import musescript.builtins.TradeBuiltins;
import musescript.evo.EvoParam;
import musescript.evo.nma.NmaEpoch;
import musescript.evo.nma.NmaEvalContext;
import musescript.evo.nma.NmaEval;
import musescript.evo.nma.NmaSeries;
import musescript.evo.nma.NmaScalar;
import musescript.evo.nma.NmaBool;

/**
 * P1 coverage for the NMA columnar evaluator (`NmaEval`) + memo signature (`NmaEpoch`).
 *
 * The load-bearing checks are DIFFERENTIAL against the real `TradeBuiltins` cross/trend builtins
 * (via their compiled-path `*CS` variants, driven bar-by-bar exactly as the interp/WASM genome path
 * drives them) -- so the stateful, historically bug-prone primitives (see Expand.hx's BTrend-dir
 * war story) are pinned bit-exact, not merely to a hand-guess. The numeric/logic primitives are
 * checked against direct computation, and the memo/epoch mechanics against their own contract.
 *
 * Everything here is indicator-free (the `ThrowingIndicatorProvider` default) -- the engine-backed
 * `SInd` provider + its fitness-level A/B is the next gate.
 */
class TestNmaEval extends Test {

	static function ctxOf(fields:Map<String, Array<Float>>, n:Int):NmaEvalContext {
		NmaEpoch.resetRegistry();
		return new NmaEvalContext(n, NmaEpoch.of("test-tape", []), fields);
	}

	static function assertColEquals(expected:Array<Float>, col:GrowableVec<Float>, ?msg:String):Void {
		Assert.equals(expected.length, col.length, (msg != null ? msg + ": " : "") + "length");
		for (i in 0...expected.length) {
			var e = expected[i], a = col.at(i);
			if (Math.isNaN(e)) Assert.isTrue(Math.isNaN(a), '${msg} idx $i expected NaN got $a');
			else Assert.floatEquals(e, a, '${msg} idx $i');
		}
	}

	// ---------- differential parity vs TradeBuiltins (the real thing) ----------

	public function testCrossoverMatchesTradeBuiltins() {
		var a = [1.0, 2.0, 3.0, 2.0, 1.0, 3.0, 3.0, 4.0];
		var b = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 3.0, 2.0];
		var n = a.length;
		// Ground truth: the compiled-path crossover, one call/bar at a fixed callsite id.
		var h = new HarnessContext();
		var ref = [for (i in 0...n) TradeBuiltins.crossoverCS(h, 0, a[i], b[i]) ? 1.0 : 0.0];

		var ctx = ctxOf(["a" => a, "b" => b], n);
		var node = new NmaBCross("over", new NmaSPrice("a"), new NmaSPrice("b"));
		assertColEquals(ref, NmaEval.evalBool(node, ctx), "crossover parity");
	}

	public function testCrossunderMatchesTradeBuiltins() {
		var a = [3.0, 2.0, 1.0, 2.0, 3.0, 1.0, 1.0];
		var b = [2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 1.0];
		var n = a.length;
		var h = new HarnessContext();
		var ref = [for (i in 0...n) TradeBuiltins.crossunderCS(h, 0, a[i], b[i]) ? 1.0 : 0.0];

		var ctx = ctxOf(["a" => a, "b" => b], n);
		var node = new NmaBCross("under", new NmaSPrice("a"), new NmaSPrice("b"));
		assertColEquals(ref, NmaEval.evalBool(node, ctx), "crossunder parity");
	}

	public function testCrossoverNaNHandlingMatches() {
		var a = [1.0, Math.NaN, 3.0, 2.0, 4.0];
		var b = [2.0, 2.0, 2.0, 2.0, 3.0];
		var n = a.length;
		var h = new HarnessContext();
		var ref = [for (i in 0...n) TradeBuiltins.crossoverCS(h, 0, a[i], b[i]) ? 1.0 : 0.0];

		var ctx = ctxOf(["a" => a, "b" => b], n);
		var node = new NmaBCross("over", new NmaSPrice("a"), new NmaSPrice("b"));
		assertColEquals(ref, NmaEval.evalBool(node, ctx), "crossover NaN parity");
	}

	public function testRisingAndFallingMatchTradeBuiltins() {
		var s = [1.0, 2.0, 3.0, 4.0, 3.0, 2.0, 5.0, 6.0, 7.0];
		var n = s.length;
		for (w in 1...4) {
			var hr = new HarnessContext();
			var refRise = [for (i in 0...n) TradeBuiltins.risingCS(hr, 0, s[i], w) ? 1.0 : 0.0];
			var ctxR = ctxOf(["c" => s], n);
			var rising = new NmaBTrend("over", new NmaSPrice("c"), w);
			assertColEquals(refRise, NmaEval.evalBool(rising, ctxR), 'rising w=$w parity');

			var hf = new HarnessContext();
			var refFall = [for (i in 0...n) TradeBuiltins.fallingCS(hf, 0, s[i], w) ? 1.0 : 0.0];
			var ctxF = ctxOf(["c" => s], n);
			var falling = new NmaBTrend("under", new NmaSPrice("c"), w);
			assertColEquals(refFall, NmaEval.evalBool(falling, ctxF), 'falling w=$w parity');
		}
	}

	// ---------- numeric / logic primitives ----------

	public function testArithAndLookbackAndCompare() {
		var close = [10.0, 11.0, 12.0, 11.5, 13.0];
		var n = close.length;
		var ctx = ctxOf(["close" => close], n);
		// (close - close[1]) > 0  == "close rose vs previous bar"
		var delta = new NmaKArith("-", new NmaKSeries(new NmaSPrice("close")),
			new NmaKLookback(new NmaSPrice("close"), 1));
		var deltaCol = NmaEval.evalScalar(delta, ctx);
		assertColEquals([Math.NaN, 1.0, 1.0, -0.5, 1.5], deltaCol, "close - close[1]");

		var rose = new NmaBCmp(">", delta, new NmaKConst(0.0));
		assertColEquals([0.0, 1.0, 1.0, 0.0, 1.0], NmaEval.evalBool(rose, ctx), "rose>0 (NaN=>false)");

		// min/max are now arity-aware: 2-arg `min(11, close)` is the true element-wise minimum
		// (matching WASM + Simplify). close = [10, 11, 12, 11.5, 13], so min(11, close) clamps at 11.
		var mn = new NmaKArith("min", new NmaKConst(11.0), new NmaKSeries(new NmaSPrice("close")));
		assertColEquals([10.0, 11.0, 11.0, 11.0, 11.0], NmaEval.evalScalar(mn, ctx), "min(11,close)=element-wise min");
	}

	public function testBooleanLogic() {
		var c = [1.0, 2.0, 3.0, 4.0];
		var n = c.length;
		var ctx = ctxOf(["close" => c], n);
		var gt2 = new NmaBCmp(">", new NmaKSeries(new NmaSPrice("close")), new NmaKConst(2.0));
		var lt4 = new NmaBCmp("<", new NmaKSeries(new NmaSPrice("close")), new NmaKConst(4.0));
		assertColEquals([0.0, 0.0, 1.0, 0.0], NmaEval.evalBool(new NmaBAnd(gt2, lt4), ctx), "gt2 && lt4");
		assertColEquals([1.0, 1.0, 0.0, 0.0], NmaEval.evalBool(new NmaBNot(gt2), ctx), "!(gt2)");
		assertColEquals([1.0, 1.0, 1.0, 1.0], NmaEval.evalBool(new NmaBOr(gt2, new NmaBNot(gt2)), ctx), "gt2 || !gt2");
	}

	// ---------- memo + epoch mechanics ----------

	public function testMemoReturnsSameColumnWithinEpoch() {
		var close = [1.0, 2.0, 3.0];
		var ctx = ctxOf(["close" => close], close.length);
		var node = new NmaKArith("+", new NmaKSeries(new NmaSPrice("close")), new NmaKConst(1.0));
		var first = NmaEval.evalScalar(node, ctx);
		var second = NmaEval.evalScalar(node, ctx);
		Assert.isTrue(first == second, "same epoch re-eval returns the memoized column (identity)");
		Assert.equals(ctx.epoch.id, node.evalEpoch, "node stamped with epoch id");
	}

	public function testDifferentEpochRecomputes() {
		var close = [1.0, 2.0, 3.0];
		var ctxA = ctxOf(["close" => close], close.length); // resets registry, epoch id 0
		var node = new NmaKSeries(new NmaSPrice("close"));
		var colA = NmaEval.evalScalar(node, ctxA);
		// A genuinely different tape signature -> different interned epoch -> recompute.
		var ctxB = new NmaEvalContext(close.length, NmaEpoch.of("other-tape", [], 1, 0), ["close" => close]);
		Assert.notEquals(ctxA.epoch.id, ctxB.epoch.id, "distinct tape sig -> distinct epoch id");
		var colB = NmaEval.evalScalar(node, ctxB);
		Assert.isFalse(colA == colB, "different epoch recomputes a fresh column");
		Assert.equals(ctxB.epoch.id, node.evalEpoch, "node re-stamped to newer epoch");
	}

	public function testEpochInterningIsStable() {
		NmaEpoch.resetRegistry();
		var e1 = NmaEpoch.of("tape-x", []);
		var e2 = NmaEpoch.of("tape-x", []);
		var e3 = NmaEpoch.of("tape-y", [], 1, 0);
		Assert.equals(e1.id, e2.id, "same signature -> same interned id (warm memo across evals)");
		Assert.notEquals(e1.id, e3.id, "different signature -> different id");
	}

	public function testEpochInterningDistinguishesParams() {
		NmaEpoch.resetRegistry();
		var p1:Array<EvoParam> = [{ name: "x", defaultValue: 1.0, min: 0.0, max: 10.0, step: 1.0, tune: "none" }];
		var p2:Array<EvoParam> = [{ name: "x", defaultValue: 2.0, min: 0.0, max: 10.0, step: 1.0, tune: "none" }];
		var e1 = NmaEpoch.of("tape", p1, 5, 6);
		var e2 = NmaEpoch.of("tape", p2, 5, 6);
		var e3 = NmaEpoch.of("tape", p1, 5, 6);
		Assert.notEquals(e1.id, e2.id, "different param values -> different id");
		Assert.equals(e1.id, e3.id, "same tape lanes + params -> same id");
	}

	public function testPriceColumnIsSharedWithinContext() {
		var close = [5.0, 6.0, 7.0];
		var ctx = ctxOf(["close" => close], close.length);
		Assert.isTrue(ctx.priceColumn("close") == ctx.priceColumn("close"),
			"same field returns one shared, content-addressed column");
	}
}
