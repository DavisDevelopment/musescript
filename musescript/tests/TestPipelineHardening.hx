package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.ProjectionScore;
import musescript.evo.ProjKind;
import musescript.evo.ProjectionProvider;
import musescript.evo.StrategyGenome;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.rigor.ProbSharpe;
import musescript.evo.rigor.NormApprox;
import musescript.evo.rigor.BlockBootstrap;
import musescript.evo.rigor.Pbo;
import musescript.evo.rigor.PurgeEmbargo;
import musescript.evo.rigor.PreRegistration;
import musescript.evo.rigor.SeedRobustness;
import musescript.evo.rigor.UniverseRobustness;
import musescript.evo.rigor.OosVerdict;
import musescript.ew.NullForecastHost;
import musescript.ew.OracleForecastHost;
import musescript.ew.HostLeakageProbe;
import musescript.ew.EwForecastHost.EwForecastHostStub;
import musescript.harness.Bar;
import musescript.harness.Metrics;
import musescript.ew.mcmc.DetRng;
import haxe.Int64;

/**
 * Pipeline hardening regression suite (PIPELINE_HARDENING_TODO.md).
 * Buckets A / B / C1 / J — every test must FAIL on the pre-fix instrument.
 */
class TestPipelineHardening extends Test {
	function setup() {
		Fitness.defaultMinTrades = 20;
	}

	function teardown() {
		Fitness.defaultMinTrades = 20;
	}

	static function bars(n:Int, ?seed:Int = 1):Array<Bar> {
		var rng = new DetRng(Int64.ofInt(seed), Int64.ofInt(0xBA25));
		var out:Array<Bar> = [];
		var px = 100.0;
		for (i in 0...n) {
			var r = (rng.nextUnit() - 0.48) * 0.02;
			var o = px;
			px = px * (1 + r);
			var h = Math.max(o, px) * 1.001;
			var l = Math.min(o, px) * 0.999;
			out.push({open: o, high: h, low: l, close: px, volume: 1000 + rng.nextInt(100), time: i + 0.0, index: i});
		}
		return out;
	}

	static function iidReturns(n:Int, mean:Float, std:Float, seed:Int):Array<Float> {
		var rng = new DetRng(Int64.ofInt(seed), Int64.ofInt(0x51D));
		return [for (_ in 0...n) mean + std * rng.nextGaussian()];
	}

	// ── A1: min-trade gate ────────────────────────────────────────────────────

	public function testOneTradeGenomeScoresNegInf() {
		var r = new FitnessResult(true, 5.0, 1, 110000, "js");
		Assert.equals(Fitness.NEG_INF, Fitness.score(r), "1-trade must be NEG_INF at default minTrades=20");
		Assert.equals(Fitness.NEG_INF, Fitness.scoreFacts(1, 5.0));
		Assert.isTrue(Fitness.score(r, 1) > 0, "explicit minTrades=1 still allows thin trades for tests");
	}

	public function testNineteenTradesStillNegInfTwentyClears() {
		Assert.equals(Fitness.NEG_INF, Fitness.scoreFacts(19, 1.5));
		Assert.floatEquals(1.5, Fitness.scoreFacts(20, 1.5));
	}

	// ── A2: PSR / DSR ─────────────────────────────────────────────────────────

	public function testNormCdfKnownValues() {
		Assert.floatEquals(0.5, NormApprox.cdf(0), 1e-6);
		Assert.isTrue(NormApprox.cdf(1.96) > 0.97 && NormApprox.cdf(1.96) < 0.98);
		Assert.floatEquals(0.0, NormApprox.invCdf(0.5), 1e-4);
	}

	public function testPsrKnownGaussianSeries() {
		// Large i.i.d. positive-mean series → PSR → 1
		var rets = iidReturns(500, 0.001, 0.01, 7);
		var p = ProbSharpe.psr(rets, 0);
		Assert.isTrue(p > 0.95, 'expected high PSR, got $p');
		// Zero-mean → PSR ~ 0.5
		var z = iidReturns(500, 0.0, 0.01, 8);
		var pz = ProbSharpe.psr(z, 0);
		Assert.isTrue(pz > 0.2 && pz < 0.8, 'zero-mean PSR should center near 0.5, got $pz');
	}

	public function testEqualSharpeHigherNRanksAbove() {
		// Same per-period Sharpe, 10× observations → strictly higher rankScore
		var small = iidReturns(50, 0.001, 0.01, 11);
		var large = iidReturns(500, 0.001, 0.01, 12);
		var srS = ProbSharpe.sharpePerPeriod(small);
		var srL = ProbSharpe.sharpePerPeriod(large);
		// Force equal SR by scaling large series mean to match small's SR*std
		// Simpler: use rankFromAnnualized with identical ann Sharpe, different n
		var rSmall = ProbSharpe.rankFromAnnualized(1.0, 50);
		var rLarge = ProbSharpe.rankFromAnnualized(1.0, 500);
		Assert.isTrue(rLarge > rSmall, 'n=500 must rank above n=50 at equal Sharpe: $rLarge vs $rSmall (srS=$srS srL=$srL)');
	}

	public function testDsrDeflatesUnderManyTrials() {
		var rets = iidReturns(200, 0.0005, 0.01, 13);
		var psr1 = ProbSharpe.dsr(rets, 1);
		var psr100 = ProbSharpe.dsr(rets, 100);
		Assert.isTrue(psr100 <= psr1 + 1e-9, 'more trials must not raise DSR: $psr100 vs $psr1');
	}

	// ── A3/A4: OOS verdict + block bootstrap ──────────────────────────────────

	public function testThinTradeOosVerdictIsNoGo() {
		var rets = iidReturns(30, 0.01, 0.01, 21); // lucky positive
		var v = OosVerdict.evaluate(rets, 1, 0.0, {minTrades: 20, nTrials: 1, nBoot: 50});
		Assert.isFalse(v.go);
		Assert.equals("NO-GO", v.label);
		Assert.isTrue(v.reason.indexOf("minTrades") >= 0);
	}

	public function testBlockBootstrapCiHasFiniteBounds() {
		var rets = iidReturns(100, 0.001, 0.01, 22);
		var ci = BlockBootstrap.sharpeCi(rets, 42, 100);
		Assert.isTrue(Math.isFinite(ci.lo) && Math.isFinite(ci.hi));
		Assert.isTrue(ci.lo <= ci.point && ci.point <= ci.hi);
	}

	// ── A6: ProjectionScore floors ────────────────────────────────────────────

	public function testRankIcBelowMinSampleIsZero() {
		Assert.floatEquals(0.0, ProjectionScore.rankIC([1, 2, 3], [3, 2, 1]));
	}

	public function testConstantPredictorIcIsZero() {
		var p = [for (_ in 0...30) 1.0];
		var y = [for (i in 0...30) i * 1.0];
		Assert.floatEquals(0.0, ProjectionScore.rankIC(p, y));
	}

	// ── B1: PBO ───────────────────────────────────────────────────────────────

	public function testPboOnRandomPopulationNearHalf() {
		var rng = new DetRng(Int64.ofInt(99), Int64.ofInt(1));
		var nStrat = 8;
		var nSlices = 6;
		var perf:Array<Array<Float>> = [];
		for (_ in 0...nStrat) {
			perf.push([for (_s in 0...nSlices) rng.nextGaussian()]);
		}
		var pbo = Pbo.estimate(perf);
		Assert.isTrue(Math.isFinite(pbo));
		Assert.isTrue(pbo > 0.15 && pbo < 0.85, 'random PBO should be ~0.5, got $pbo');
	}

	// ── B2: purge & embargo ───────────────────────────────────────────────────

	public function testPurgeEmbargoEnforcesLookbackGap() {
		var s = PurgeEmbargo.split(1000, 0.25, 200);
		Assert.equals(200, s.embargo);
		Assert.isTrue(s.oosStart - s.isEnd == 400); // purge + embargo
		Assert.isFalse(PurgeEmbargo.isLegalOosBar(s.oosStart - 1, 1000 - 250, 200));
		Assert.isTrue(PurgeEmbargo.isLegalOosBar(s.oosStart, 1000 - 250, 200));
		// Strategy with 200-bar lookback cannot score OOS bars within 200 of split
		var split = 750;
		Assert.isFalse(PurgeEmbargo.isLegalOosBar(split + 50, split, 200));
		Assert.isTrue(PurgeEmbargo.isLegalOosBar(split + 200, split, 200));
	}

	// ── B3: pre-registration ──────────────────────────────────────────────────

	public function testPreRegistrationLocksThreshold() {
		var pr = new PreRegistration("host beats BH", "buy_hold", 0.0, 5);
		var v = pr.evaluate(0.5);
		Assert.isTrue(v.go);
		Assert.floatEquals(0.0, v.threshold);
		Assert.isTrue(pr.describe().indexOf("0") >= 0);
		var no = pr.evaluate(-0.1);
		Assert.isFalse(no.go);
	}

	// ── B4: seed robustness ───────────────────────────────────────────────────

	public function testSeedRobustnessUsesMedianNotMax() {
		var metrics = [-0.5, -0.2, 2.0, 0.1, -0.1]; // max=2 clears 0; median does not
		var v = SeedRobustness.verdict(metrics, 0.0);
		Assert.isFalse(v.go);
		Assert.isTrue(v.max > 0);
		Assert.isTrue(v.median <= 0);
	}

	// ── B5: universe robustness ───────────────────────────────────────────────

	public function testSingleNameUniverseIsFlagged() {
		var v = UniverseRobustness.verdict([{name: "TSLA", metric: 1.5}], 0.0);
		Assert.isTrue(v.singleName);
		Assert.isFalse(v.go);
	}

	public function testMultiNamePassIsGo() {
		var v = UniverseRobustness.verdict([
			{name: "A", metric: 1.0}, {name: "B", metric: 0.8}, {name: "C", metric: -0.2}
		], 0.0, 2, 0.5);
		Assert.isTrue(v.go);
		Assert.isFalse(v.singleName);
	}

	// ── J1: negative control (noise must be NO-GO) ────────────────────────────

	public function testNullHostCloudIsFiniteAndInvariant() {
		var b = bars(80);
		var host = new NullForecastHost(7, 5);
		for (i in 0...b.length) host.onBar(b[i], i);
		var c = host.cloudAt(40);
		Assert.isTrue(Math.isFinite(c.priceMid));
		Assert.isNull(HostLeakageProbe.checkInvariants(c));
	}

	public function testNoiseReturnsOosVerdictNoGo() {
		// Pure noise equity → near-zero Sharpe → NO-GO under hardened verdict
		var rets = iidReturns(100, 0.0, 0.02, 33);
		var v = OosVerdict.evaluate(rets, 50, 0.0, {minTrades: 20, nTrials: 10, nBoot: 80, psrGate: 0.95});
		Assert.isFalse(v.go, 'noise must be NO-GO, got ${v.label}: ${v.reason}');
	}

	public function testCoinFlipTraderScoresNegInfOrNoEdge() {
		// Simulate a 1-trade "lucky" coin-flip: high Sharpe, 1 trade → NEG_INF
		var lucky = new FitnessResult(true, 4.5, 1, 105000, "js");
		Assert.equals(Fitness.NEG_INF, Fitness.score(lucky));
	}

	// ── J2: positive control (planted edge scales) ────────────────────────────

	public function testOracleSignalMonotoneSkill() {
		var b = bars(120, 5);
		var h = 5;
		function dirSkill(signal:Float):Float {
			var host = OracleForecastHost.fromBars(b, signal, h, 99);
			var pred:Array<Float> = [];
			var real:Array<Float> = [];
			for (t in 0...b.length - h) {
				host.onBar(b[t], t);
				var c = host.cloudAt(t);
				pred.push(c.probUp - 0.5);
				real.push(b[t + h].close - b[t].close);
			}
			return ProjectionScore.directionalSkill(pred, real);
		}
		var s0 = dirSkill(0.0);
		var s5 = dirSkill(0.5);
		var s1 = dirSkill(1.0);
		Assert.isTrue(s0 <= s5 + 0.05, 'signal 0 should not beat 0.5: $s0 vs $s5');
		Assert.isTrue(s5 <= s1 + 0.05, 'signal 0.5 should not beat 1.0: $s5 vs $s1');
		Assert.isTrue(s1 > s0 + 0.2, 'full oracle must beat noise: $s1 vs $s0');
	}

	// ── J3: label shuffle collapses skill ─────────────────────────────────────

	public function testLabelShuffleCollapsesRankIc() {
		var b = bars(80, 3);
		var y = ProjectionScore.realizedTarget(b, PLevel, 3);
		// Perfect foresight
		Assert.floatEquals(1.0, ProjectionScore.rankIC(y, y));
		// Shuffle targets with DetRng
		var rng = new DetRng(Int64.ofInt(44), Int64.ofInt(2));
		var shuffled = y.copy();
		var i = shuffled.length - 1;
		while (i > 0) {
			var j = rng.nextInt(i + 1);
			var tmp = shuffled[i];
			shuffled[i] = shuffled[j];
			shuffled[j] = tmp;
			i--;
		}
		var ic = ProjectionScore.rankIC(y, shuffled);
		Assert.isTrue(Math.abs(ic) < 0.35, 'shuffled IC should collapse near 0, got $ic');
	}

	// ── C1: leakage probe ─────────────────────────────────────────────────────

	public function testStubHostPassesLeakageProbe() {
		var b = bars(40);
		var err = HostLeakageProbe.probe(_ -> new EwForecastHostStub(), b, 20);
		Assert.isNull(err, 'stub must be causal: $err');
	}

	public function testOracleHostFailsLeakageProbe() {
		var b = bars(60, 2);
		var err = HostLeakageProbe.probe(tape -> OracleForecastHost.fromBars(tape, 1.0, 5, 1), b, 25);
		Assert.isTrue(err != null, "oracle must fail causality probe");
	}

	public function testNullHostPassesLeakageProbe() {
		var b = bars(50, 4);
		var err = HostLeakageProbe.probe(_ -> new NullForecastHost(5, 5), b, 20);
		Assert.isNull(err, 'null host must be causal: $err');
	}

	/**
	 * J2 DoD — planted-edge genome → IS rankScore selection → hardened OOS → GO,
	 * while the same genome under NullForecastHost stays NO-GO.
	 * Minimal evo path: two candidates (oracle vs null host), select by IS rankScoreFacts.
	 */
	public function testJ2PlantedEdgeEvoOosGoWhileNullNoGo() {
		Fitness.defaultMinTrades = 20;
		Fitness.equityCurveNeeded = true;
		var all = bars(500, 17);
		var split = PurgeEmbargo.split(all.length, 0.30, 8);
		var isBars = all.slice(0, split.isEnd);
		var oosBars = all.slice(split.oosStart, all.length);
		Assert.isTrue(isBars.length >= 100 && oosBars.length >= 100,
			'need long enough IS/OOS: IS=${isBars.length} OOS=${oosBars.length}');

		function plantedGenome(name:String):StrategyGenome {
			// Long-only on oracle p50>close (future mid). Same-bar long+flat from dual exit
			// gates was washing P&L to zero — keep exit as the complementary p50<close only.
			return {
				entryLong: BCmp(">", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
				entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
				exitLong: BCmp("<", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
				exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
				size: KConst(1.0),
				params: [],
				name: name,
				lineage: ["j2-planted"],
				seedOrigin: null,
				projections: [ProjectionProvider.ewDecl("ew_0", 3, "oracle", 1)]
			};
		}

		function evalWithHost(g:StrategyGenome, tape:Array<Bar>, host:musescript.ew.EwForecastHost):FitnessResult {
			var provider = new ProjectionProvider(host);
			provider.autoBindGenomeHost = false;
			var prev = Fitness.projectionProvider;
			Fitness.projectionProvider = provider;
			var fr = Fitness.evaluate(g, tape, "js", false, 0.0);
			Fitness.projectionProvider = prev;
			return fr;
		}

		var gOracle = plantedGenome("j2_oracle_prob_up");
		var gNull = plantedGenome("j2_null_prob_up");
		var h = 3;
		var oracleIs = OracleForecastHost.fromBars(isBars, 1.0, h, 0x0ACE);
		var nullIs = new NullForecastHost(0x0011, h);
		for (i in 0...isBars.length) nullIs.onBar(isBars[i], i);

		var frOracleIs = evalWithHost(gOracle, isBars, oracleIs);
		var frNullIs = evalWithHost(gNull, isBars, nullIs);
		Assert.isTrue(frOracleIs.ok, "oracle IS eval: " + frOracleIs.error);
		Assert.isTrue(frNullIs.ok, "null IS eval: " + frNullIs.error);

		var rankOracle = Fitness.rankScore(frOracleIs, 20, 10);
		var rankNull = Fitness.rankScore(frNullIs, 20, 10);
		// Minimal evo selection: pick higher IS rankScore
		var selected = rankOracle >= rankNull ? gOracle : gNull;
		var selectedHostIsOracle = selected == gOracle;
		Assert.isTrue(selectedHostIsOracle,
			'IS selection must prefer planted oracle (rankOracle=$rankOracle rankNull=$rankNull tradesO=${frOracleIs.trades} tradesN=${frNullIs.trades} srO=${frOracleIs.sharpe} srN=${frNullIs.sharpe})');

		var bh:StrategyGenome = {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "buy_and_hold", lineage: [], seedOrigin: null
		};
		var frBh = Fitness.evaluate(bh, oosBars, "js", false, 0.0);
		var bhSr = frBh.ok ? frBh.sharpe : 0.0;

		var oracleOos = OracleForecastHost.fromBars(oosBars, 1.0, h, 0x0ACE);
		var frOracleOos = evalWithHost(gOracle, oosBars, oracleOos);
		Assert.isTrue(frOracleOos.ok && frOracleOos.equity != null);
		Assert.isTrue(frOracleOos.trades >= 20,
			'planted edge must clear minTrades on OOS, got ${frOracleOos.trades}');
		var retsO = Metrics.returnsFromEquity(frOracleOos.equity);
		var vOracle = OosVerdict.evaluate(retsO, frOracleOos.trades, bhSr, {
			minTrades: 20, nTrials: 5, nBoot: 80, psrGate: 0.90, bootSeed: 7
		});
		Assert.isTrue(vOracle.go, 'J2 planted edge must GO OOS: ${vOracle.label} ${vOracle.reason} trades=${frOracleOos.trades} sr=${frOracleOos.sharpe} bh=$bhSr');

		var nullOos = new NullForecastHost(0x0011, h);
		for (i in 0...oosBars.length) nullOos.onBar(oosBars[i], i);
		var frNullOos = evalWithHost(gNull, oosBars, nullOos);
		Assert.isTrue(frNullOos.ok && frNullOos.equity != null);
		var retsN = Metrics.returnsFromEquity(frNullOos.equity);
		var vNull = OosVerdict.evaluate(retsN, frNullOos.trades, bhSr, {
			minTrades: 20, nTrials: 5, nBoot: 80, psrGate: 0.90, bootSeed: 7
		});
		Assert.isFalse(vNull.go, 'J1 null must stay NO-GO on OOS: ${vNull.label} ${vNull.reason}');
	}

	public function testRankScoreFactsDeflatesAndPrefersHigherN() {
		var lowN = Fitness.rankScoreFacts(50, 1.0, 50, false, 20, 1);
		var highN = Fitness.rankScoreFacts(50, 1.0, 500, false, 20, 1);
		Assert.isTrue(highN > lowN, 'higher nObs must rank above: $highN vs $lowN');
		var one = Fitness.rankScoreFacts(50, 0.8, 200, false, 20, 1);
		var many = Fitness.rankScoreFacts(50, 0.8, 200, false, 20, 100);
		Assert.isTrue(many <= one + 1e-9, 'more trials must not raise rankScoreFacts');
		Assert.equals(Fitness.NEG_INF, Fitness.rankScoreFacts(5, 3.0, 200));
	}
}
