package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.StrategyParser;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.Decl;
import musescript.cli.MuseFill;
import musescript.evo.CorpusSeed;
import musescript.evo.Variation;
import musescript.evo.HoleMeta;
import musescript.evo.HoleDomain;
import musescript.evo.Palette;
import musescript.evo.ScalarNode;
import musescript.evo.BoolNode;
import musescript.evo.Expand;
import musescript.evo.rigor.ProbSharpe;
import musescript.evo.rigor.TrialsSession;
import musescript.evo.rigor.TruthVerdict;

/**
 * SPEC_AUTHOR_HOLES — parse → CorpusSeed → domain-aware fill → honest verdict.
 * Refuses dishonest nTrials=1 after search, and Robust without purge/embargo OOS.
 * Green path: honestOos scores the champion on the OOS slice so Robust is earnable.
 */
class TestAuthorHoles extends Test {
	function allowed():Map<String, Bool> {
		var m = new Map<String, Bool>();
		for (n in Palette.INDS) m.set(n, true);
		return m;
	}

	function sketch(body:String):String {
		return 'strategy S {\n  onBar {\n$body\n  }\n}';
	}

	public function testParseUntypedAndTypedHoles() {
		var p = new StrategyParser();
		var prog = p.parse(sketch("when ?Bool: { long(1) }\nwhen close > ?Scalar: { flat() }"), "<t>");
		Assert.equals(1, prog.decls.length);
		var found = 0;
		walk(prog.decls[0], function(e) {
			switch (e) {
				case EMeta("__hole", args, _):
					found++;
					Assert.isTrue(HoleMeta.typeOf(args) == "Bool" || HoleMeta.typeOf(args) == "Scalar");
				default:
			}
		});
		Assert.equals(2, found);
	}

	public function testParseScalarIntDomain() {
		var p = new StrategyParser();
		var prog = p.parse(sketch("when rsi(close, ?Scalar in 2..30) < 30: { long(1) }\nwhen ?Bool: { flat() }"), "<t>");
		var saw = false;
		walk(prog.decls[0], function(e) {
			switch (e) {
				case EMeta("__hole", args, _):
					var d = HoleMeta.decodeDomain(args);
					switch (d) {
						case DIntRange(lo, hi):
							Assert.equals(2, lo);
							Assert.equals(30, hi);
							saw = true;
						default:
					}
				default:
			}
		});
		Assert.isTrue(saw, "expected DIntRange(2,30) on ?Scalar in 2..30");
	}

	public function testParseScalarRealDomain() {
		var p = new StrategyParser();
		var prog = p.parse(sketch("when close > ?Scalar in [0.1, 1.0]: { long(1) }\nwhen ?Bool: { flat() }"), "<t>");
		var saw = false;
		walk(prog.decls[0], function(e) {
			switch (e) {
				case EMeta("__hole", args, _):
					var d = HoleMeta.decodeDomain(args);
					switch (d) {
						case DRealInterval(lo, hi):
							Assert.floatEquals(0.1, lo, 1e-9);
							Assert.floatEquals(1.0, hi, 1e-9);
							saw = true;
						default:
					}
				default:
			}
		});
		Assert.isTrue(saw, "expected DRealInterval on ?Scalar in [0.1,1.0]");
	}

	public function testEmptyDomainRejected() {
		var threw = false;
		try {
			new StrategyParser().parse(sketch("when close > ?Scalar in 10..2: { long(1) }"), "<t>");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("empty") >= 0, Std.string(e));
		}
		Assert.isTrue(threw, "empty int domain must fail at parse");
	}

	public function testTranslateToTemplatedGenomeWithDomain() {
		var src = sketch("when close > ?Scalar in 5..15: { long(1) }\nwhen ?Bool: { flat() }");
		var t = CorpusSeed.translateSource(src, allowed());
		Assert.isNull(t.error, t.error);
		Assert.notNull(t.genome);
		Assert.isTrue(Variation.isTemplated(t.genome), "sketch must lower to templated genome");

		var sawDomain = false;
		function walkS(n:ScalarNode) {
			switch (n) {
				case KHole(_, domain, _):
					switch (domain) {
						case DIntRange(lo, hi):
							Assert.equals(5, lo);
							Assert.equals(15, hi);
							sawDomain = true;
						default:
					}
				case KArith(_, a, b): walkS(a); walkS(b);
				default:
			}
		}
		function walkB(n:BoolNode) {
			if (n == null) return;
			switch (n) {
				case BHole(_, _, _):
				case BAnd(a, b) | BOr(a, b): walkB(a); walkB(b);
				case BNot(a): walkB(a);
				case BCmp(_, a, b): walkS(a); walkS(b);
				default:
			}
		}
		walkB(t.genome.entryLong);
		walkB(t.genome.exitLong);
		Assert.isTrue(sawDomain, "KHole must carry DIntRange from translate");
	}

	public function testDomainAwareFillStaysInRange() {
		var src = sketch("when close > ?Scalar in 10..20: { long(1) }\nwhen ?Bool: { flat() }");
		var t = CorpusSeed.translateSource(src, allowed());
		Assert.notNull(t.genome);
		var v = new Variation(42);
		for (i in 0...40) {
			var filled = v.fillHoles(t.genome);
			Assert.isFalse(Variation.isTemplated(filled), "fill must drop holes");
			var consts = [];
			collectConsts(filled.entryLong, consts);
			var inRange = false;
			for (c in consts) if (c >= 10 && c <= 20) inRange = true;
			Assert.isTrue(inRange, "expected a KConst fill in [10,20], got " + consts);
		}
	}

	public function testFillDeterministicForSeed() {
		var src = sketch("when ?Bool: { long(1) }\nwhen ?Bool: { flat() }");
		var t = CorpusSeed.translateSource(src, allowed());
		var a = Expand.expand(new Variation(7).fillHoles(t.genome));
		var b = Expand.expand(new Variation(7).fillHoles(t.genome));
		Assert.equals(a, b);
	}

	public function testNoiseFillStaysCoinFlipUnderDeflation() {
		var tape = MuseFill.driftlessTape(300, 99);
		var src = sketch("when ?Bool: { long(1) }\nwhen ?Bool: { flat() }");
		var r = MuseFill.run(src, 200, 1337, tape);
		Assert.isTrue(r.ok, r.reason);
		Assert.equals(r.nEval, r.nTrials);
		Assert.isTrue(r.nTrials > 1);
		Assert.isTrue(r.dsrDeflated <= r.dsrRaw + 1e-12);
		Assert.isTrue(r.truthVerdict != "Robust", "must not claim Robust without OOS: " + r.truthVerdict);
		Assert.isTrue(r.verdict.indexOf("Robust") < 0, r.verdict);
	}

	public function testLargerBudgetRaisesExpectedMaxBar() {
		// Monotone DSR property: same returns, larger N ⇒ DSR weakly decreases.
		var rets = [];
		for (i in 0...80) rets.push(0.002 * ((i % 3) - 1));
		var dsrSmall = ProbSharpe.dsr(rets, 10);
		var dsrLarge = ProbSharpe.dsr(rets, 2000);
		Assert.isTrue(dsrLarge <= dsrSmall + 1e-12, 'DSR@2000=$dsrLarge should be <= DSR@10=$dsrSmall');
	}

	public function testRefuseDishonestNTrials() {
		Assert.notNull(MuseFill.refuseDishonestVerdict(1, 100));
		Assert.isNull(MuseFill.refuseDishonestVerdict(50, 100));
		Assert.isNull(MuseFill.refuseDishonestVerdict(1, 1));
	}

	public function testRefuseRobustWithoutOosHelper() {
		Assert.notNull(MuseFill.refuseRobustWithoutOos(false, TruthVerdict.Robust));
		Assert.isNull(MuseFill.refuseRobustWithoutOos(true, TruthVerdict.Robust));
		Assert.isNull(MuseFill.refuseRobustWithoutOos(false, TruthVerdict.Fragile));
		Assert.isNull(MuseFill.refuseRobustWithoutOos(false, TruthVerdict.CoinFlip));
	}

	public function testInSampleFillCannotClaimRobust() {
		// Even on a planted edge tape, full-sample fill must not earn Robust / oosHeld.
		var tape = MuseFill.plantedTrendTape(400, 7);
		var src = sketch("when ?Bool: { long(1) }\nwhen ?Bool: { flat() }");
		var r = MuseFill.run(src, 40, 11, tape);
		Assert.isTrue(r.ok, r.reason);
		Assert.isTrue(r.honestOos != true);
		Assert.isTrue(r.oosHeld != true, "IS-only must not mark oosHeld");
		Assert.isTrue(r.purgeEmbargoApplied != true);
		Assert.notEquals("Robust", r.truthVerdict, "IS-only TruthReport must not say Robust");
		Assert.isTrue(r.verdict.indexOf("Robust") < 0, r.verdict);
	}

	public function testOosFillMarksPurgeEmbargoAndCanEarnRobust() {
		// Domain-constrained buy-the-dip-never sketch on a mild planted trend: IS-rank, OOS-score.
		// minTrades=1 matches buy-and-hold round-trips; search-N still deflates DSR.
		var tape = MuseFill.plantedTrendTape(480, 424242);
		var src = sketch(
			"when close > ?Scalar in [0.0, 50.0]: { long(1) }\n"
			+ "when close < ?Scalar in [-10.0, -1.0]: { flat() }"
		);
		var r = MuseFill.run(src, 8, 99, tape, {
			honestOos: true,
			oosFrac: 0.28,
			embargoBars: 5,
			minTrades: 1,
			minIsBars: 40,
			minOosBars: 40,
			nBoot: 50,
			psrGate: 0.90
		});
		Assert.isTrue(r.ok, r.reason);
		Assert.isTrue(r.honestOos == true);
		Assert.isTrue(r.oosHeld == true, "OOS path must mark oosHeld");
		Assert.isTrue(r.purgeEmbargoApplied == true);
		Assert.isTrue(r.embargoBars != null && r.embargoBars >= 0);
		Assert.isTrue(r.isBars != null && r.isBars >= 40, "IS=" + r.isBars);
		Assert.isTrue(r.oosBars != null && r.oosBars >= 40, "OOS=" + r.oosBars);
		Assert.equals(r.nEval, r.nTrials);
		Assert.isTrue(r.nTrials > 1, "search size must still deflate");
		Assert.equals("Robust", r.truthVerdict,
			"planted OOS edge should clear Robust; got " + r.truthVerdict
			+ " sharpe=" + r.sharpe + " trades=" + r.trades
			+ " dsrN=" + r.dsrDeflated + " oosReason=" + r.oosReason);
		Assert.equals("Robust", r.verdict);
	}

	public function testOosNoiseFillStaysNonRobust() {
		var tape = MuseFill.driftlessTape(400, 2026);
		var src = sketch("when ?Bool: { long(1) }\nwhen ?Bool: { flat() }");
		var r = MuseFill.run(src, 80, 3, tape, {
			honestOos: true, oosFrac: 0.25, embargoBars: 8, minTrades: 20, nBoot: 40
		});
		Assert.isTrue(r.ok, r.reason);
		Assert.isTrue(r.oosHeld == true);
		Assert.notEquals("Robust", r.truthVerdict,
			"noise + OOS must not become Robust: " + r.truthVerdict);
	}

	public function testOosTooShortRefusesHoldoutPath() {
		var tape = MuseFill.momentumTape(50, 1);
		var src = sketch("when ?Bool: { long(1) }\nwhen ?Bool: { flat() }");
		var r = MuseFill.run(src, 10, 2, tape, {
			honestOos: true, oosFrac: 0.25, embargoBars: 20, minOosBars: 40, minIsBars: 40
		});
		Assert.isFalse(r.ok);
		Assert.isTrue(r.reason.indexOf("refuse") >= 0 || r.reason.indexOf("too short") >= 0, r.reason);
	}

	public function testTrialsSessionTracksFillBudget() {
		TrialsSession.reset();
		var tape = MuseFill.driftlessTape(200, 1);
		var src = sketch("when ?Bool: { long(1) }\nwhen ?Bool: { flat() }");
		var r = MuseFill.run(src, 30, 3, tape);
		Assert.isTrue(r.ok, r.reason);
		Assert.equals(r.nEval, TrialsSession.getCount());
	}

	public function testUnfilledSketchStillRunnablePlaceholder() {
		// EMeta("__hole") seed must parse/lower without fill; expand of templated genome unwraps inners.
		var src = sketch("when ?Bool: { long(1) }\nwhen close > ?Scalar in [1.0, 2.0]: { flat() }");
		var t = CorpusSeed.translateSource(src, allowed());
		Assert.notNull(t.genome);
		var out = Expand.expand(t.genome);
		Assert.isTrue(out.indexOf("?") < 0, "Expand must not emit raw ?; got:\n" + out);
	}

	static function collectConsts(n:BoolNode, out:Array<Float>) {
		if (n == null) return;
		switch (n) {
			case BAnd(a, b) | BOr(a, b): collectConsts(a, out); collectConsts(b, out);
			case BNot(a): collectConsts(a, out);
			case BCmp(_, a, b): collectScalarConsts(a, out); collectScalarConsts(b, out);
			case BHole(inner, _, _): collectConsts(inner, out);
			default:
		}
	}

	static function collectScalarConsts(n:ScalarNode, out:Array<Float>) {
		switch (n) {
			case KConst(v): out.push(v);
			case KArith(_, a, b): collectScalarConsts(a, out); collectScalarConsts(b, out);
			case KHole(inner, _, _): collectScalarConsts(inner, out);
			default:
		}
	}

	static function walk(d:Decl, f:Expr->Void) {
		switch (d) {
			case StrategyDecl(_, body):
				for (s in body) walkStmt(s, f);
			default:
		}
	}

	static function walkStmt(s:musescript.ast.Stmt, f:Expr->Void) {
		switch (s) {
			case OnBar(body): for (x in body) walkStmt(x, f);
			case When(cond, body):
				walkExpr(cond, f);
				for (x in body) walkStmt(x, f);
			case ExprStmt(e): walkExpr(e, f);
			case Assign(_, e): walkExpr(e, f);
			default:
		}
	}

	static function walkExpr(e:Expr, f:Expr->Void) {
		if (e == null) return;
		f(e);
		switch (e) {
			case EMeta(_, args, inner):
				for (a in args) walkExpr(a, f);
				walkExpr(inner, f);
			case EBinop(_, a, b): walkExpr(a, f); walkExpr(b, f);
			case EUnop(_, _, a): walkExpr(a, f);
			case ECall(fn, args):
				walkExpr(fn, f);
				for (a in args) walkExpr(a, f);
			case EParent(a): walkExpr(a, f);
			case EBlock(es): for (x in es) walkExpr(x, f);
			case EIf(c, a, b):
				walkExpr(c, f); walkExpr(a, f); walkExpr(b, f);
			case EField(a, _): walkExpr(a, f);
			case EArray(a, b): walkExpr(a, f); walkExpr(b, f);
			default:
		}
	}
}
