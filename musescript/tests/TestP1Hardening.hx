package musescript.tests;

import utest.Assert;
import utest.Test;
import haxe.Int64;
import haxe.ds.Vector;
import musescript.ew.mcmc.DetRng;
import musescript.ew.mcmc.DetMath;
import musescript.ew.mcmc.RegimeMcmc;
import musescript.ew.BenchmarkHarness;
import musescript.ew.HostWarmup;
import musescript.ew.auction.VolumeProfile;
import musescript.harness.Bar;
import musescript.harness.OrderSim;
import musescript.evo.NmaNodeEvalPool;
import musescript.evo.CorpusSeed;
import musescript.evo.RivalryArena;
import musescript.evo.Rand;
import musescript.evo.ProjectionProvider;
import musescript.evo.StrategyGenome;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.Fitness;

/**
 * P1 hardening suite (PIPELINE_HARDENING_TODO.md buckets D / E / F / G / I).
 */
class TestP1Hardening extends Test {
	// ── D1 / D2: DetRng battery ───────────────────────────────────────────────

	public function testNextUnitUniformChiSquare() {
		var rng = new DetRng(Int64.make(1, 2));
		var bins = [for (_ in 0...10) 0];
		var n = 10000;
		for (_ in 0...n) {
			var u = rng.nextUnit();
			Assert.isTrue(u >= 0 && u < 1);
			bins[Std.int(u * 10)]++;
		}
		var expected = n / 10.0;
		var chi = 0.0;
		for (c in bins) {
			var d = c - expected;
			chi += d * d / expected;
		}
		// 9 df, 99.9% critical ≈ 27.9 — keep slack for one seed
		Assert.isTrue(chi < 40, 'chi-square too high: $chi');
	}

	public function testNextIntNoModuloBiasEvenAndOdd() {
		for (n in [7, 8, 10, 17]) {
			var rng = new DetRng(Int64.make(3, n));
			var counts = [for (_ in 0...n) 0];
			var draws = n * 2000;
			for (_ in 0...draws) counts[rng.nextInt(n)]++;
			var expected = draws / (n + 0.0);
			var chi = 0.0;
			for (c in counts) {
				var d = c - expected;
				chi += d * d / expected;
			}
			Assert.isTrue(chi < 40, 'nextInt($n) chi=$chi');
		}
	}

	public function testNextUnitLag1NearZero() {
		var rng = new DetRng(Int64.make(9, 9));
		var n = 5000;
		var xs = [for (_ in 0...n) rng.nextUnit()];
		var mean = 0.0;
		for (x in xs) mean += x;
		mean /= n;
		var num = 0.0, den = 0.0;
		for (i in 0...n - 1) {
			num += (xs[i] - mean) * (xs[i + 1] - mean);
			den += (xs[i] - mean) * (xs[i] - mean);
		}
		var rho = num / den;
		Assert.isTrue(Math.abs(rho) < 0.05, 'lag-1 rho=$rho');
	}

	public function testGaussianMomentsAndNoLag1FromCache() {
		var rng = new DetRng(Int64.make(5, 6));
		var n = 8000;
		var xs = [for (_ in 0...n) rng.nextGaussian()];
		var mean = 0.0;
		for (x in xs) mean += x;
		mean /= n;
		var var_ = 0.0;
		for (x in xs) {
			var d = x - mean;
			var_ += d * d;
		}
		var_ /= n;
		Assert.isTrue(Math.abs(mean) < 0.05, 'mean=$mean');
		Assert.isTrue(Math.abs(var_ - 1.0) < 0.08, 'var=$var_');
		// Lag-1 should stay near 0 even with Marsaglia pair cache
		var num = 0.0, den = 0.0;
		for (i in 0...n - 1) {
			num += (xs[i] - mean) * (xs[i + 1] - mean);
			den += (xs[i] - mean) * (xs[i] - mean);
		}
		Assert.isTrue(Math.abs(num / den) < 0.05);
	}

	// ── D3: DetMath ───────────────────────────────────────────────────────────

	public function testDetMathLogExpAccuracy() {
		var xs = [0.01, 0.1, 0.5, 1.0, 2.0, Math.exp(1), Math.PI, 10.0, 100.0, 1e6];
		for (x in xs) {
			var dlog = DetMath.log(x);
			var mlog = Math.log(x);
			var rel = Math.abs(dlog - mlog) / Math.max(1e-15, Math.abs(mlog));
			Assert.isTrue(rel < 1e-10, 'log($x) rel=$rel');
		}
		// exp: stay in a moderate range where both DetMath and libm are finite
		var ys = [-5.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
		for (y in ys) {
			var dexp = DetMath.exp(y);
			var mexp = Math.exp(y);
			var relE = Math.abs(dexp - mexp) / Math.max(1e-15, Math.abs(mexp));
			Assert.isTrue(relE < 1e-10, 'exp($y) rel=$relE');
		}
	}

	public function testDetMathEdgeCases() {
		Assert.isTrue(Math.isNaN(DetMath.log(0)));
		Assert.isTrue(Math.isNaN(DetMath.log(-1)));
		Assert.isTrue(Math.isNaN(DetMath.exp(Math.NaN)));
		Assert.isTrue(DetMath.exp(0) > 0.999 && DetMath.exp(0) < 1.001);
		Assert.isTrue(DetMath.exp(800) == Math.POSITIVE_INFINITY || DetMath.exp(800) > 1e100);
		Assert.floatEquals(0.0, DetMath.exp(-800));
	}

	// ── E1 / E2: RegimeMcmc ───────────────────────────────────────────────────

	public function testRegimeMcmcEssAndAcceptBand() {
		var rng = new DetRng(Int64.make(0xABCD, 0x1234));
		var n = 240;
		var v = new Vector<Float>(n);
		for (t in 0...n) v[t] = (t < 120 ? 0.004 : 0.02) * rng.nextGaussian();
		var m = new RegimeMcmc(Int64.make(0, 42), v, 2);
		m.run(4000, 1500, true);
		var ar = m.acceptRate();
		Assert.isTrue(ar > 0.05 && ar < 0.7, 'accept=$ar');
		var ess = m.essCurrentRegime();
		Assert.isTrue(Math.isFinite(ess) && ess > 15, 'ESS=$ess');
		Assert.isTrue(m.mixingOk(15, 0.05, 0.7));
	}

	public function testRegimeMcmcShortBudgetFlagged() {
		var rng = new DetRng(Int64.make(1, 1));
		var v = new Vector<Float>(80);
		for (t in 0...80) v[t] = 0.01 * rng.nextGaussian();
		var m = new RegimeMcmc(Int64.make(0, 1), v, 2);
		m.run(50, 40, true); // tiny post-burn sample
		Assert.isFalse(m.mixingOk(100, 0.05, 0.7), "too-short budget must fail mixingOk");
	}

	public function testRegimePredictiveCoverageApprox90() {
		// Known process: i.i.d. N(0, 0.01). Predictive p05–p95 of cum return over H should cover ~90%.
		var H = 5;
		var trials = 40;
		var hits = 0;
		for (trial in 0...trials) {
			var rng = new DetRng(Int64.make(100 + trial, 7));
			var v = new Vector<Float>(120);
			for (t in 0...120) v[t] = 0.01 * rng.nextGaussian();
			var m = new RegimeMcmc(Int64.make(0, 50 + trial), v, 2);
			m.run(1500, 500);
			var pred = m.predictCumReturn(H, 120);
			// Draw one future path from the SAME generating process
			var fut = 0.0;
			for (_ in 0...H) fut += 0.01 * rng.nextGaussian();
			if (fut >= pred.p05 && fut <= pred.p95) hits++;
		}
		var cov = hits / (trials + 0.0);
		Assert.isTrue(cov > 0.7 && cov < 0.99, 'coverage=$cov (expect ~0.9)');
	}

	// ── E3: VolumeProfile value-area invariant ────────────────────────────────

	public function testValueAreaContainsTargetPct() {
		// Concentrated tape: most volume in a tight mid band
		var bars:Array<Bar> = [];
		for (i in 0...30) {
			var mid = 100.0 + (i % 3) * 0.2;
			bars.push({
				open: mid, high: mid + 0.5, low: mid - 0.5, close: mid,
				volume: 1000.0 + (i == 15 ? 5000 : 0), time: i + 0.0, index: i
			});
		}
		var lv = VolumeProfile.fromBars(bars, 30, 40, 0.70);
		Assert.isTrue(Math.isFinite(lv.poc));
		Assert.isTrue(lv.vaHigh >= lv.vaLow);
		Assert.isTrue(lv.poc >= lv.vaLow - 1e-9 && lv.poc <= lv.vaHigh + 1e-9);
		Assert.isTrue(lv.valueAreaVolFrac >= 0.70 - 1e-6, 'VA frac=${lv.valueAreaVolFrac}');
	}

	// ── F1 / F2 / F5 ──────────────────────────────────────────────────────────

	public function testRivalryBlendPreservesProjections() {
		var seeds = CorpusSeed.seedFromEwHostProjection("lattice");
		Assert.isTrue(seeds.length >= 1);
		var g = seeds[0];
		Assert.isTrue(g.projections != null && g.projections.length > 0);
		var loser:StrategyGenome = {
			entryLong: g.entryLong, entryShort: g.entryShort,
			exitLong: g.exitLong, exitShort: g.exitShort,
			size: g.size,
			params: [{name: "p", defaultValue: 1.0, min: 0.0, max: 2.0, step: 0.1, tune: "float"}],
			name: "loser", lineage: [], seedOrigin: null,
			projections: g.projections
		};
		var winner:StrategyGenome = {
			entryLong: g.entryLong, entryShort: g.entryShort,
			exitLong: g.exitLong, exitShort: g.exitShort,
			size: g.size,
			params: [{name: "p", defaultValue: 1.5, min: 0.0, max: 2.0, step: 0.1, tune: "float"}],
			name: "winner", lineage: [], seedOrigin: null,
			projections: null
		};
		var child = RivalryArena.paramBlendToward(loser, winner, new Rand(7));
		Assert.isTrue(child.projections != null && child.projections.length > 0,
			"paramBlendToward must keep projections");
	}

	public function testWorkerJsonGuardRejectsHostGenome() {
		var seeds = CorpusSeed.seedFromEwHostProjection("lattice");
		Assert.isFalse(NmaNodeEvalPool.isWorkerJsonSafe(seeds[0]));
		var plain:StrategyGenome = {
			entryLong: BCmp(">", KConst(1), KConst(0)),
			entryShort: BCmp(">", KConst(0), KConst(1)),
			exitLong: BCmp(">", KConst(0), KConst(1)),
			exitShort: BCmp(">", KConst(0), KConst(1)),
			size: KConst(1), params: [], name: "plain", lineage: [], seedOrigin: null
		};
		Assert.isTrue(NmaNodeEvalPool.isWorkerJsonSafe(plain));
		var threw = false;
		try NmaNodeEvalPool.assertWorkerJsonSafe(seeds) catch (_:Dynamic) threw = true;
		Assert.isTrue(threw, "must reject projection genomes on worker path");
	}

	public function testRegimeAuctionSeedsDropDeadInvalidate() {
		var reg = CorpusSeed.seedFromEwHostProjection("regime");
		var auc = CorpusSeed.seedFromEwHostProjection("auction");
		var lat = CorpusSeed.seedFromEwHostProjection("lattice");
		function hasInv(gs:Array<StrategyGenome>):Bool {
			for (g in gs) if (g.name != null && g.name.indexOf("vs_invalidate") >= 0) return true;
			return false;
		}
		Assert.isFalse(hasInv(reg));
		Assert.isFalse(hasInv(auc));
		Assert.isTrue(hasInv(lat));
	}

	public function testProjectionProviderTapeSwapInvalidatesClouds() {
		var barsA:Array<Bar> = [for (i in 0...40) {
			var c = 100.0 + i;
			({open: c, high: c + 1, low: c - 1, close: c, volume: 1.0, time: i + 0.0, index: i} : Bar);
		}];
		var barsB:Array<Bar> = [for (i in 0...40) {
			var c = 200.0 - i;
			({open: c, high: c + 1, low: c - 1, close: c, volume: 1.0, time: i + 0.0, index: i} : Bar);
		}];
		var stack = new musescript.indicators.geom.SwingGraphStack(0.02, 0.05, 16);
		var host = musescript.ew.LatticeForecastHost.withStack(stack);
		var p = new ProjectionProvider(host);
		var cA = p.materialize(barsA);
		Assert.equals(40, cA.length);
		p.invalidate();
		var cB = p.materialize(barsB);
		// Different tapes must not reuse prior clouds by identity
		Assert.isTrue(cA != cB);
		Assert.equals(40, cB.length);
	}

	// ── G1 / G3 / G4 ──────────────────────────────────────────────────────────

	public function testSlippageChargedOnEntryAndExit() {
		function run(bps:Float):Float {
			var sim = new OrderSim();
			sim.book.slippageBps = bps;
			sim.reset(100000);
			sim.long(100.0, 10, 0); // buy 10 @ slipped
			sim.flat(110.0, 1); // sell 10 @ slipped
			return sim.cash;
		}
		var cash0 = run(0);
		var cash20 = run(20);
		var cash100 = run(100);
		Assert.isTrue(cash20 < cash0, "20bps must reduce cash vs free");
		Assert.isTrue(cash100 < cash20, "higher bps must cost more");
		// free: 100000 - 10*100 + 10*110 = 100100
		Assert.floatEquals(100100.0, cash0, 1e-6);
	}

	public function testFlipChargesBothLegs() {
		function flipCash(bps:Float):Float {
			var sim = new OrderSim();
			sim.book.slippageBps = bps;
			sim.reset(100000);
			sim.long(100.0, 10, 0);
			sim.short(100.0, 10, 1); // close long + open short
			Assert.equals(3, sim.trades); // long + flat + short
			Assert.floatEquals(-10.0, sim.position);
			return sim.cash;
		}
		Assert.isTrue(flipCash(100) < flipCash(0), "slippage must reduce cash vs free flip");
	}

	public function testRiskCapClampsExplicitQty() {
		var sim = new OrderSim(100000);
		sim.long(100.0, 5000, 0); // request way over 25% cash
		Assert.isTrue(sim.position <= 250 + 1e-9, 'cap=${sim.position}');
		Assert.isTrue(sim.position >= 250 - 1e-9);
	}

	public function testBankruptScoresNegInfUnderDefaultMinTrades() {
		Fitness.defaultMinTrades = 20;
		var r = new musescript.evo.FitnessResult(true, 3.0, 50, 0, "js");
		r.bankrupt = true;
		Assert.equals(Fitness.NEG_INF, Fitness.score(r));
	}

	// ── I1 / I3 ───────────────────────────────────────────────────────────────

	public function testBenchmarkHarnessAnchorGrid() {
		var grid = BenchmarkHarness.anchorGrid(200, 60, 5, 20);
		Assert.isTrue(grid.length > 0);
		for (t in grid) Assert.isTrue(BenchmarkHarness.isLegalAnchor(t, 60, 5, 20, 200));
		Assert.isFalse(BenchmarkHarness.isLegalAnchor(10, 60, 5, 20, 200));
	}

	public function testNullBaselineDocsPresent() {
		Assert.isTrue(BenchmarkHarness.nullBaselineDoc("ew").indexOf("ATR") >= 0);
		Assert.isTrue(BenchmarkHarness.nullBaselineDoc("regime").indexOf("persistence") >= 0);
		Assert.isTrue(BenchmarkHarness.nullBaselineDoc("auction").indexOf("drift") >= 0);
		Assert.isTrue(BenchmarkHarness.nullBaselineDoc("shuffled").indexOf("shuffle") >= 0);
	}

	public function testWarmupConstantsMatchHarness() {
		Assert.equals(HostWarmup.EW_LATTICE_BENCHMARK, 60);
		Assert.equals(HostWarmup.REGIME_BENCHMARK, 180);
		Assert.equals(HostWarmup.AUCTION_BENCHMARK, 120);
	}

	public function testEmpiricalNullCollapsePerRunner() {
		var rng = new DetRng(Int64.make(0x11, 0x22));
		// Regime: persistence vs Δvol on i.i.d. Gaussian → |IC| not large
		var rets = [for (_ in 0...200) 0.01 * rng.nextGaussian()];
		var ic = BenchmarkHarness.persistenceDeltaVolIc(rets, 20, 5);
		Assert.isTrue(Math.isFinite(ic), 'ic=$ic');
		Assert.isTrue(Math.abs(ic) < 0.45, 'persistence Δvol IC should collapse, got $ic');

		// Auction: random labels → class edge ≈ 0
		var fwd = [for (_ in 0...120) 0.001 * rng.nextGaussian()];
		var labels = [for (_ in 0...120) rng.nextInt(3)];
		var edge0 = BenchmarkHarness.auctionClassEdge(fwd, labels, 0);
		var edge1 = BenchmarkHarness.auctionClassEdge(fwd, labels, 1);
		Assert.isTrue(Math.abs(edge0) < 0.002, 'edge0=$edge0');
		Assert.isTrue(Math.abs(edge1) < 0.002, 'edge1=$edge1');

		// EW ATR null on thin (H=L=C) tape: tight band hits less than wide
		var bars:Array<Bar> = [];
		var px = 100.0;
		for (i in 0...180) {
			px += 0.35 * rng.nextGaussian();
			bars.push({
				open: px, high: px, low: px, close: px,
				volume: 1.0, time: i + 0.0, index: i
			});
		}
		var hrTight = BenchmarkHarness.atrNullHitRate(bars, 40, 5, 10, 14, 0.25);
		var hrWide = BenchmarkHarness.atrNullHitRate(bars, 40, 5, 10, 14, 8.0);
		Assert.isTrue(Math.isFinite(hrTight) && Math.isFinite(hrWide));
		Assert.isTrue(hrTight < hrWide, 'tight=$hrTight wide=$hrWide');
		Assert.isTrue(hrTight < 0.9, 'tight ATR null must not look like an oracle ($hrTight)');
		Assert.isTrue(hrWide > 0.9, 'wide ATR null should nearly always capture ($hrWide)');

		// Shuffled / constant predictor already covered; confirm rank-IC collapse
		var constPred = [for (_ in 0...40) 1.0];
		var y = [for (i in 0...40) i * 1.0];
		Assert.floatEquals(0.0, BenchmarkHarness.rankIc(constPred, y));
	}

	public function testHostDrainRateNearZeroAfterMutations() {
		var seeds = CorpusSeed.seedFromEwHostProjection("lattice");
		Assert.isTrue(seeds.length >= 1);
		var rate = musescript.evo.HostDrainGuard.drainRateAfterMutations(seeds[0], 40, 3);
		Assert.isTrue(rate < 0.05, 'drain rate $rate must be ≈0 after F1/F4 fixes');
		var pop = seeds.copy();
		Assert.isFalse(musescript.evo.HostDrainGuard.reinjectNeeded(pop));
		// Artificial drain → reinject needed
		var dead = seeds[0];
		dead = {
			entryLong: dead.entryLong, entryShort: dead.entryShort,
			exitLong: dead.exitLong, exitShort: dead.exitShort,
			size: dead.size, params: dead.params, name: dead.name,
			lineage: dead.lineage, seedOrigin: dead.seedOrigin, projections: null
		};
		Assert.isTrue(musescript.evo.HostDrainGuard.reinjectNeeded([dead]));
	}

	// ── F3 / F4 / G3 / I2 / E4 ────────────────────────────────────────────────

	public function testBindHostKeyDiffersPrefixVsFullTape() {
		var full:Array<Bar> = [for (i in 0...50) {
			var c = 100.0 + i * 0.1;
			({open: c, high: c + 1, low: c - 1, close: c, volume: 1.0, time: i + 0.0, index: i} : Bar);
		}];
		var prefix = full.slice(0, 30);
		var seeds = CorpusSeed.seedFromEwHostProjection("lattice");
		var g = seeds[0];
		var p = ProjectionProvider.forEvoHost(false);
		p.bindHostForGenome(g, prefix);
		var k1 = p.debugBindKey();
		p.bindHostForGenome(g, full);
		var k2 = p.debugBindKey();
		Assert.isTrue(k1 != null && k2 != null);
		Assert.isTrue(k1 != k2, "prefix vs full tape must not share bind key");
	}

	public function testCompactParamsPreservesProjections() {
		var seeds = CorpusSeed.seedFromEwHostProjection("lattice");
		var g = seeds[0];
		g.params = [
			{name: "unused_gap", defaultValue: 1.0, min: 0.0, max: 2.0, step: 0.1, tune: "float"},
			{name: "p_used", defaultValue: 1.0, min: 0.0, max: 2.0, step: 0.1, tune: "float"}
		];
		var out = new musescript.evo.Variation(1).compactParams(g);
		Assert.isTrue(out.projections != null && out.projections.length > 0);
	}

	public function testNextOpenDefersFill() {
		var sim = new OrderSim(100000);
		sim.executionMode = "next-open";
		sim.long(100.0, 10, 0);
		Assert.floatEquals(0.0, sim.position, "must not fill same bar");
		sim.beginBar(105.0, 1);
		Assert.floatEquals(10.0, sim.position);
		Assert.floatEquals(105.0, sim.fills[0].price);
	}

	public function testConstantPredictorProjectionScoreIsZero() {
		var p = [for (_ in 0...30) 1.0];
		var y = [for (i in 0...30) i * 1.0];
		Assert.floatEquals(0.0, musescript.evo.ProjectionScore.rankIC(p, y));
	}

	public function testEwGuidelineAlternationNeutralOnShort() {
		var piv = new haxe.ds.Vector<musescript.indicators.geom.PivotPoint>(3);
		for (i in 0...3) piv[i] = new musescript.indicators.geom.PivotPoint(100.0 + i, i % 2 == 0 ? 1.0 : -1.0, i);
		var s = musescript.indicators.ew.EwGuidelines.alternationImpulse(piv, 0);
		Assert.floatEquals(0.5, s);
	}

	public function testImpulseWave4OverlapHardReject() {
		// Classic invalid impulse: wave 4 enters wave 1 price territory
		var piv = new haxe.ds.Vector<musescript.indicators.geom.PivotPoint>(6);
		piv[0] = new musescript.indicators.geom.PivotPoint(100, -1, 0);
		piv[1] = new musescript.indicators.geom.PivotPoint(110, 1, 1);  // W1 high
		piv[2] = new musescript.indicators.geom.PivotPoint(105, -1, 2); // W2
		piv[3] = new musescript.indicators.geom.PivotPoint(120, 1, 3);  // W3
		piv[4] = new musescript.indicators.geom.PivotPoint(101, -1, 4); // W4 overlaps W1
		piv[5] = new musescript.indicators.geom.PivotPoint(125, 1, 5);
		Assert.isTrue(musescript.indicators.ew.ImpulseRules.wave4OverlapsWave1(piv, 0));
		Assert.isFalse(musescript.indicators.ew.ImpulseRules.isValidMotive(piv, 0));
	}
}
