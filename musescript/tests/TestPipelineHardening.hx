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
import musescript.evo.rigor.TruthReport;
import musescript.evo.rigor.TruthVerdict;
import musescript.evo.rigor.TrialsSession;
import musescript.evo.rigor.ReportCard;
import musescript.evo.rigor.HonestLedger;
import musescript.evo.rigor.LedgerDisposition;
import musescript.evo.rigor.LeaderboardScore;
import musescript.evo.BasketFitness;
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

	// ── Initiative 1.4: null-baseline min-trades exemption ───────────────────

	public function testBuyAndHoldNullBaselineNotNegInf() {
		// Candidate gate still kills 1-trade luck; null baseline must stay a fair bar.
		Assert.equals(Fitness.NEG_INF, Fitness.scoreFacts(1, 2.5));
		Assert.floatEquals(2.5, Fitness.scoreFactsNullBaseline(1, 2.5));
		var bh = new FitnessResult(true, 1.2, 1, 110000, "js");
		Assert.equals(Fitness.NEG_INF, Fitness.score(bh));
		Assert.floatEquals(1.2, Fitness.scoreNullBaseline(bh));
		var agg = {trades: 1, sharpe: 0.8, bankrupt: false};
		Assert.equals(Fitness.NEG_INF, BasketFitness.scoreAggregate(agg));
		Assert.floatEquals(0.8, BasketFitness.scoreNullBaseline(agg));
	}

	public function testNullBaselineBankruptStillNegInf() {
		var dead = new FitnessResult(true, 3.0, 1, 0, "js");
		dead.bankrupt = true;
		Assert.equals(Fitness.NEG_INF, Fitness.scoreNullBaseline(dead));
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

	// ── Initiative 1: Truth Report + trials ───────────────────────────────────

	public function testTrialsSessionIncrementsAndEffectiveFloor() {
		TrialsSession.reset();
		Assert.equals(0, TrialsSession.getCount());
		Assert.equals(1, TrialsSession.effectiveTrials());
		Assert.equals(1, TrialsSession.recordTrial());
		Assert.equals(2, TrialsSession.recordTrial());
		Assert.equals(2, TrialsSession.effectiveTrials());
		TrialsSession.setCount(40);
		Assert.equals(40, TrialsSession.getCount());
		TrialsSession.reset();
		Assert.equals(0, TrialsSession.getCount());
	}

	public function testTruthReportThinTradeIsCoinFlip() {
		TrialsSession.reset();
		var rets = iidReturns(40, 0.02, 0.01, 31);
		var tr = TruthReport.evaluate(rets, 1, 0.0, {
			minTrades: 20, nTrials: 1, nBoot: 40, oosHeld: true, purgeEmbargoApplied: true
		});
		Assert.equals(TruthVerdict.CoinFlip, tr.verdict);
		Assert.isFalse(tr.minTradesPassed);
		Assert.isFalse(tr.gates.minTrades);
		Assert.isTrue(tr.reasons.length > 0);
		Assert.isTrue(tr.reasons[0].indexOf("trade") >= 0);
	}

	public function testTruthReportPboOverfitVerdict() {
		var rets = iidReturns(80, 0.002, 0.01, 32);
		var tr = TruthReport.evaluate(rets, 40, -0.5, {
			minTrades: 20, nTrials: 1, nBoot: 40, pbo: 0.72,
			oosHeld: true, purgeEmbargoApplied: true, psrGate: 0.5
		});
		Assert.equals(TruthVerdict.Overfit, tr.verdict);
		Assert.isFalse(tr.gates.pbo);
	}

	public function testTruthReportJsonRoundTrip() {
		var rets = iidReturns(100, 0.001, 0.01, 33);
		var tr = TruthReport.evaluate(rets, 30, 0.0, {
			minTrades: 20, nTrials: 5, nBoot: 50,
			purgeEmbargoApplied: true, embargoBars: 10, oosHeld: true
		});
		var json = tr.toJson();
		var back = TruthReport.parse(json);
		Assert.equals(tr.verdict, back.verdict);
		Assert.equals(tr.trades, back.trades);
		Assert.equals(tr.nTrials, back.nTrials);
		Assert.equals(tr.gates.minTrades, back.gates.minTrades);
		Assert.equals(tr.reasons.length, back.reasons.length);
	}

	public function testTruthReportUsesTrialsSessionWhenNTrialsOmitted() {
		TrialsSession.reset();
		TrialsSession.setCount(25);
		var rets = iidReturns(60, 0.001, 0.01, 34);
		var tr = TruthReport.evaluate(rets, 25, 0.0, {
			minTrades: 20, nBoot: 40, oosHeld: true, purgeEmbargoApplied: true
		});
		Assert.equals(25, tr.nTrials);
		TrialsSession.reset();
	}

	// ── Initiative 3: honesty-gated optimizer ─────────────────────────────────

	public function testHonestOptimizeNoTunableParams() {
		TrialsSession.reset();
		var src = "
strategy NoParams {
  onBar {
    when close > open: long()
    when close < open: flat()
  }
}";
		var r:Dynamic = musescript.harness.HonestOptimize.search(src, bars(80, 7), {
			seed: 42, minTrades: 5
		});
		Assert.isTrue(r.ok == true);
		Assert.isFalse(r.found == true);
		Assert.equals("no tunable params", r.reason);
	}

	public function testHonestOptimizeEmptyIsFeature() {
		// Tiny grid on noise tape — Truth Report should refuse to ship a "winner".
		TrialsSession.reset();
		var src = '
{
  @strategy("NoiseGrid")
  @param("fast", 5) { min: 5, max: 8, step: 3, tune: "grid" }
  @macro("discover") {
    tune(fast);
    optimize(sharpe, [fast]);
  }
  @on(bar) {
    var a = sma(close, fast);
    if (close > a) long();
    if (close < a) flat();
  }
}';
		var r:Dynamic = musescript.harness.HonestOptimize.search(src, bars(120, 11), {
			seed: 7,
			minTrades: 20,
			acceptVerdicts: ["Robust"],
			oosHeld: true,
			purgeEmbargoApplied: true
		});
		Assert.isTrue(r.ok == true, Std.string(r.error));
		Assert.isTrue(r.trials > 0, "expected at least one trial");
		// Honest empty (or rare Robust) — never returns Overfit/Coin-flip as best.
		if (r.found == true) {
			Assert.equals("Robust", Reflect.field(Reflect.field(r.best, "truthReport"), "verdict"));
		} else {
			Assert.isTrue(
				r.reason == "nothing beat the null" || r.reason == "no robust strategy found",
				'unexpected reason: ${r.reason}'
			);
		}
		TrialsSession.reset();
	}

	public function testForecastFieldAliases() {
		var c:musescript.ew.ForecastCloud = {
			horizon: 5,
			priceLo: 90, priceHi: 110, barLo: 0, barHi: 5,
			priceMid: 100, spread: 20, probUp: 0.62,
			topMass: 0.5, countEntropy: 0.4,
			invalidatePrice: Math.NaN, distToInvalidation: Math.NaN,
			nestScore: 1.0, labelCode: 0, samples: 1
		};
		Assert.floatEquals(100, ProjectionProvider.cloudField(c, "poc"), 1e-12);
		Assert.floatEquals(0.62, ProjectionProvider.cloudField(c, "breakout_prob"), 1e-12);
		Assert.floatEquals(0.4, ProjectionProvider.cloudField(c, "entropy"), 1e-12);
	}

	// ── Initiative 5: Report Card / Honest Ledger ─────────────────────────────

	public function testReportCardFromTruthReport() {
		TrialsSession.reset();
		var rets = iidReturns(80, 0.002, 0.01, 41);
		var tr = TruthReport.evaluate(rets, 30, 0.0, {
			minTrades: 20, nTrials: 1, nBoot: 40,
			oosHeld: true, purgeEmbargoApplied: true,
			strategyReturn: 0.12, nullReturn: 0.05
		});
		var card = ReportCard.fromTruthReport(tr, { strategyLabel: "demo", tape: "SPY" });
		Assert.equals(ReportCard.SCHEMA, card.schema);
		Assert.equals(tr.verdict, card.verdict);
		Assert.isTrue(Math.isFinite(card.skillVsNull));
		Assert.isTrue(card.profitVsBaseline != null && Math.abs(card.profitVsBaseline - 0.07) < 1e-9);
		Assert.equals("pending", card.seedRobustness.status);
		Assert.equals("single-tape", card.universeRobustness.status);
		var dyn = card.toDyn();
		var back = ReportCard.fromDyn(dyn);
		Assert.equals(card.verdict, back.verdict);
		Assert.equals("demo", back.strategyLabel);
	}

	public function testReportCardSeedMetrics() {
		var rets = iidReturns(60, 0.001, 0.01, 42);
		var tr = TruthReport.evaluate(rets, 25, -0.1, {
			minTrades: 20, nTrials: 1, nBoot: 40, oosHeld: true, purgeEmbargoApplied: true
		});
		var card = ReportCard.fromTruthReport(tr, {
			seedMetrics: [-0.5, -0.2, 2.0, 0.1, -0.1],
			seedThreshold: 0.0
		});
		Assert.equals("no-go", card.seedRobustness.status);
		Assert.isFalse(card.seedRobustness.go);
		Assert.isTrue(card.seedRobustness.max > 0);
	}

	public function testHonestLedgerDispositions() {
		Assert.equals(LedgerDisposition.Go, HonestLedger.dispositionOf(TruthVerdict.Robust));
		Assert.equals(LedgerDisposition.Caution, HonestLedger.dispositionOf(TruthVerdict.Fragile));
		Assert.equals(LedgerDisposition.NoGo, HonestLedger.dispositionOf(TruthVerdict.CoinFlip));
		Assert.equals(LedgerDisposition.NoGo, HonestLedger.dispositionOf(TruthVerdict.Overfit));

		var rets = iidReturns(50, 0.0, 0.02, 43);
		var tr = TruthReport.evaluate(rets, 1, 0.0, {
			minTrades: 20, nTrials: 1, nBoot: 30, oosHeld: true, purgeEmbargoApplied: true
		});
		var entry = HonestLedger.entryFromTruth(tr, {
			at: "2026-07-28T00:00:00.000Z", strategyLabel: "thin", tape: "SPY"
		});
		Assert.equals(LedgerDisposition.NoGo, entry.disposition);
		Assert.equals(TruthVerdict.CoinFlip, entry.verdict);
		Assert.equals("thin", entry.strategyLabel);
		var list = HonestLedger.listToDyn([entry]);
		Assert.equals(HonestLedger.LIST_SCHEMA, list.schema);
		Assert.equals(1, list.noGoCount);
		Assert.equals(0, list.goCount);
	}

	// ── Honest Leaderboard scoring ────────────────────────────────────────────

	public function testLeaderboardNullIneligible() {
		var rets = iidReturns(80, 0.0, 0.02, 51);
		var score = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: 0.2, id: "null"
		}, { fieldN: 10, nBoot: 40, minTrades: 20 });
		Assert.isFalse(score.eligible, 'null must be ineligible: ${score.reason}');
		Assert.isTrue(
			score.reason.indexOf("DSR") >= 0
			|| score.reason.indexOf("CI") >= 0
			|| score.reason.indexOf("null") >= 0
			|| score.reason.indexOf("PBO") >= 0,
			'expected gate reason, got: ${score.reason}'
		);
	}

	public function testLeaderboardPlantedEligibleRanks() {
		var strong = iidReturns(120, 0.003, 0.01, 52);
		var mild = iidReturns(120, 0.0015, 0.01, 53);
		var noise = iidReturns(120, 0.0, 0.02, 54);
		var ranked = LeaderboardScore.rank([
			{ returns: noise, trades: 50, pbo: 0.2, id: "noise", label: "noise" },
			{ returns: mild, trades: 50, pbo: 0.2, id: "mild", label: "mild" },
			{ returns: strong, trades: 50, pbo: 0.15, id: "strong", label: "strong" }
		], { fieldN: 3, nBoot: 60, minTrades: 20 });

		Assert.isTrue(ranked.failed.length >= 1, "noise should fail the wall");
		var noiseFailed = false;
		for (f in ranked.failed) if (f.id == "noise") noiseFailed = true;
		Assert.isTrue(noiseFailed, "noise must be in failed, not ranked");

		if (ranked.wall.length >= 2) {
			Assert.equals("strong", ranked.wall[0].score.id,
				'strong should rank #1 (got ${ranked.wall[0].score.id})');
			Assert.isTrue(
				ranked.wall[0].score.rankStat >= ranked.wall[1].score.rankStat,
				"rankStat must be non-increasing down the wall"
			);
		} else {
			Assert.isTrue(ranked.wall.length >= 1, "at least one planted edge should make the wall");
			Assert.equals("strong", ranked.wall[0].score.id);
		}
	}

	public function testLeaderboardFieldNRaisesBar() {
		var rets = iidReturns(100, 0.0012, 0.01, 55);
		var small = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: 0.2
		}, { fieldN: 2, nBoot: 50, minTrades: 20 });
		var large = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: 0.2
		}, { fieldN: 500, nBoot: 50, minTrades: 20 });
		Assert.isTrue(
			large.dsrDeflated <= small.dsrDeflated + 1e-12,
			'fieldN up must not increase DSR (small=${small.dsrDeflated} large=${large.dsrDeflated})'
		);
		Assert.isTrue(large.nTrials > small.nTrials, "larger field → more trials");
	}

	public function testLeaderboardPboAndTradesGates() {
		var rets = iidReturns(100, 0.004, 0.01, 56);
		var thin = LeaderboardScore.evaluate({
			returns: rets, trades: 5, pbo: 0.1
		}, { fieldN: 5, nBoot: 40, minTrades: 20 });
		Assert.isFalse(thin.eligible);
		Assert.isTrue(thin.reason.indexOf("trades") >= 0);

		var overfit = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: 0.8
		}, { fieldN: 5, nBoot: 40, minTrades: 20 });
		Assert.isFalse(overfit.eligible);
		Assert.isTrue(overfit.reason.indexOf("PBO") >= 0);

		var noPbo = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: null
		}, { fieldN: 5, nBoot: 40, minTrades: 20 });
		Assert.isFalse(noPbo.eligible);
		Assert.isTrue(noPbo.reason.indexOf("PBO") >= 0);
	}

	public function testLeaderboardAccountTrialsRaiseBar() {
		Assert.equals(10, LeaderboardScore.effectiveTrials(10, 1));
		Assert.equals(14, LeaderboardScore.effectiveTrials(10, 5));
		var rets = iidReturns(90, 0.0015, 0.01, 57);
		var one = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: 0.2, accountTrials: 1
		}, { fieldN: 8, nBoot: 40 });
		var flood = LeaderboardScore.evaluate({
			returns: rets, trades: 40, pbo: 0.2, accountTrials: 40
		}, { fieldN: 8, nBoot: 40 });
		Assert.isTrue(
			flood.dsrDeflated <= one.dsrDeflated + 1e-12,
			"account flood must not improve DSR"
		);
	}

	// ── Soft-spot closures: prereg hard abort / multi-seed matrix / planted co-evo ──

	public function testPreregGateAbortsBelowThreshold() {
		var gate = musescript.evo.rigor.PreregGate.seal(0.5, 5);
		Assert.isTrue(gate.describe().indexOf("0.5") >= 0);
		var fail = gate.evaluate(0.1);
		Assert.isFalse(fail.go);
		Assert.isTrue(fail.abort);
		Assert.isTrue(fail.label.indexOf("ABORT") >= 0);
		var pass = gate.evaluate(0.9);
		Assert.isTrue(pass.go);
		Assert.isFalse(pass.abort);
		Assert.isTrue(pass.label.indexOf("PASS") >= 0);
	}

	public function testPreregGatePassVsAbortLabels() {
		var gate = musescript.evo.rigor.PreregGate.seal(0.0);
		var lineFail = musescript.evo.rigor.PreregGate.formatLine(gate.evaluate(-1.0));
		Assert.isTrue(lineFail.indexOf("ABORT") >= 0 || lineFail.indexOf("NO-GO") >= 0);
		var linePass = musescript.evo.rigor.PreregGate.formatLine(gate.evaluate(1.0));
		Assert.isTrue(linePass.indexOf("PASS") >= 0 || linePass.indexOf("GO") >= 0);
	}

	public function testMultiSeedRestartMatrixUsesMedian() {
		// Synthetic: max clears 0 but median does not — same contract as SeedRobustness,
		// exercised through PlantedCoEvo.seedMatrix's aggregator path with canned metrics.
		var cherry = SeedRobustness.verdict([-0.4, -0.2, 1.5], 0.0);
		Assert.isFalse(cherry.go, "median must reject single-seed cherry-pick");
		Assert.isTrue(cherry.max > 0);

		Fitness.defaultMinTrades = 20;
		Fitness.equityCurveNeeded = true;
		var all = bars(420, 61);
		var matrix = musescript.evo.rigor.PlantedCoEvo.seedMatrix(all, [11, 22, 33], {
			pop: 4, gens: 1, minTrades: 20, nTrials: 3, threshold: 0.0
		});
		Assert.equals(3, matrix.runs.length);
		Assert.isTrue(matrix.metrics.length >= 1, "expected finite OOS metrics from planted restarts");
		Assert.equals(matrix.metrics.length, matrix.verdict.n);
		// Null control on every restart must stay NO-GO.
		for (r in matrix.runs) {
			Assert.isFalse(Reflect.field(r.nullOos, "go") == true,
				'null host must stay NO-GO on seed=${r.seed}');
		}
	}

	public function testPlantedCoEvoMultiGenOosGoWhileNullNoGo() {
		Fitness.defaultMinTrades = 20;
		Fitness.equityCurveNeeded = true;
		var all = bars(480, 19);
		var r = musescript.evo.rigor.PlantedCoEvo.runOnce(all, {
			seed: 77, pop: 6, gens: 2, minTrades: 20, nTrials: 3, nBoot: 60, psrGate: 0.90
		});
		Assert.isTrue(r.gens >= 2);
		Assert.isTrue(r.championTrades >= 20,
			'planted multi-gen must clear minTrades, got ${r.championTrades}');
		Assert.isTrue(r.go, 'planted multi-gen must GO OOS: ${Reflect.field(r.oos, "label")} ${Reflect.field(r.oos, "reason")}');
		Assert.isFalse(Reflect.field(r.nullOos, "go") == true, "null control must stay NO-GO");
	}
}
