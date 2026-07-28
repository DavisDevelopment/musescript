package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Expand;
import musescript.evo.Canonical;
import musescript.evo.Fitness;
import musescript.evo.McFan;
import musescript.evo.ProjectionScore;
import musescript.evo.MapElites;
import musescript.evo.MapElites.EliteArchive;
import musescript.parse.MuseParser;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.evo.ProjKind;
import musescript.evo.ProjSampler;
import musescript.evo.NoiseModel;
import musescript.evo.ProjectionDecl;
import musescript.evo.Variation;
import musescript.evo.EvoParam;

/**
 * P0.a scaffolding coverage for evolvable projections (PROJECTION_COEVOLUTION_PLAN.md).
 *
 * At this layer a projection is INERT: neither `Expand` nor `Canonical` reads
 * `StrategyGenome.projections`, so attaching one must change neither the rendered MuseScript nor the
 * structural (fitness-cache) key. Pinning that inertness now means a later eval-wiring change
 * (SProj reference node + columnar eval) cannot silently alter an existing genome's identity or
 * cached fitness — the change will have to move these assertions deliberately.
 */
class TestProjectionScaffold extends Test {
	static function baseGenome():StrategyGenome {
		return {
			entryLong: BCross("over", SPrice("close"), SInd("sma", "close", 10, null)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)), // always false
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "PROJ",
			lineage: [],
			seedOrigin: null
		};
	}

	static function pointProj(name:String):ProjectionDecl {
		return {
			name: name, kind: PReturn, horizon: 5,
			sampler: PSPoint(SInd("sma", "close", 20, null)), samples: 1, seed: 42
		};
	}

	// ── the bundle-shaped types carry what the plan §2 specifies ─────────────────────────────

	public function testPointProjectionDeclShape() {
		var p = pointProj("proj_0");
		Assert.equals("proj_0", p.name);
		Assert.equals(5, p.horizon);
		Assert.equals(1, p.samples); // K=1 ⇒ deterministic point projection
		Assert.isTrue(p.kind.match(PReturn));
		Assert.isTrue(p.sampler.match(PSPoint(_)));
	}

	public function testFanProjectionDeclShape() {
		var p:ProjectionDecl = {
			name: "proj_1", kind: PVol, horizon: 20,
			sampler: PSNoise(SPrice("close"), KConst(0.02), NBlockBootstrap(5)), samples: 16, seed: 7
		};
		Assert.equals(16, p.samples); // K>1 ⇒ Monte-Carlo fan
		Assert.isTrue(p.kind.match(PVol));
		switch (p.sampler) {
			case PSNoise(_, _, model): Assert.isTrue(model.match(NBlockBootstrap(5)));
			default: Assert.fail("expected PSNoise sampler");
		}
	}

	// ── inertness at the render + key layer (the P0.a parity contract) ───────────────────────

	public function testAddingProjectionIsInertForExpand() {
		var g = baseGenome();
		var g2 = baseGenome();
		g2.projections = [pointProj("proj_0")];
		Assert.equals(Expand.expand(g), Expand.expand(g2));
	}

	public function testAddingProjectionIsInertForStructuralKey() {
		var g = baseGenome();
		var g2 = baseGenome();
		g2.projections = [pointProj("proj_0"), pointProj("proj_1")];
		Assert.equals(Canonical.structuralKey(g), Canonical.structuralKey(g2));
	}

	public function testProjectionFreeGenomeUnaffected() {
		// A genome that never touches projections renders and keys exactly as it always has.
		var g = baseGenome();
		Assert.isNull(g.projections);
		Assert.pass(); // Expand/key equality vs itself is covered above; this pins the null default.
	}

	// ── the genome actually carries the field ────────────────────────────────────────────────

	public function testGenomeCarriesProjectionsField() {
		var g = baseGenome();
		g.projections = [pointProj("proj_0")];
		Assert.notNull(g.projections);
		Assert.equals(1, g.projections.length);
		Assert.equals("proj_0", g.projections[0].name);
		Assert.isTrue(g.projections[0].sampler.match(PSPoint(_)));
	}

	// ── compactParams must NOT drop projections (host-genome drain regression) ────────────────

	static function hostProj(name:String):ProjectionDecl {
		return {
			name: name, kind: PReturn, horizon: 5,
			sampler: PSHost("lattice"), samples: 1, seed: 0
		};
	}

	static function dummyParam():EvoParam {
		return { name: "p0", defaultValue: 1.0, min: 0.0, max: 2.0, step: 0.1, tune: "grid" };
	}

	/**
	 * `compactParams`' non-tight rebuild (triggered whenever the referenced-param set isn't a dense
	 * identity — every mutate/XO that changes param count) used to reconstruct the genome struct
	 * WITHOUT the `projections` field, silently nulling every PSHost decl. That drained host genomes
	 * from the pop after gen 0 (reinject was only masking it). Here: a host genome with one UNUSED
	 * param forces the non-tight path; its projection must survive.
	 */
	public function testCompactParamsPreservesHostProjection() {
		var g = baseGenome();
		g.entryLong = BCross("over", SProj("ew_0", "p50"), SPrice("close"));
		g.projections = [hostProj("ew_0")];
		g.params = [dummyParam()]; // referenced by nothing ⇒ non-tight ⇒ rebuild path

		var out = new Variation(1).compactParams(g);

		Assert.equals(0, out.params.length);        // unused param compacted away (rebuild DID run)
		Assert.notNull(out.projections);            // … and projections were NOT dropped
		Assert.equals(1, out.projections.length);
		Assert.equals("ew_0", out.projections[0].name);
		switch (out.projections[0].sampler) {
			case PSHost(kind): Assert.equals("lattice", kind);
			default: Assert.fail("expected PSHost sampler to survive compaction");
		}
	}

	/**
	 * End-to-end drain guard: a host genome dragged through many blind `pointMutate`s (the ~88% path
	 * that is NOT host-aware and freely changes param counts) must keep its PSHost decl every step.
	 * The single SProj read may legitimately be severed by a mutation — that's allowed exploration —
	 * but the decl itself must persist so the host self-heal / selection can re-wire it.
	 */
	public function testHostDeclSurvivesRepeatedBlindMutation() {
		var v = new Variation(123);
		var g = baseGenome();
		g.entryLong = BCross("over", SProj("ew_0", "p50"), SPrice("close"));
		g.projections = [hostProj("ew_0")];
		g.params = [dummyParam()];

		for (_ in 0...60) {
			g = v.pointMutate(g); // pointMutate → withBoolRepl(copyGenome) → compactParams
			Assert.notNull(g.projections);
			Assert.isTrue(g.projections.length >= 1);
			Assert.isTrue(g.projections[0].sampler.match(PSHost(_)));
		}
	}

	// ── P0.b: a REFERENCED projection renders as a prelude field and runs end-to-end ─────────

	static function projReadingGenome():StrategyGenome {
		// entryLong reads proj_0 (= sma(close,5)) crossing over close.
		var g = baseGenome();
		g.entryLong = BCross("over", SProj("proj_0", "p50"), SPrice("close"));
		g.projections = [{
			name: "proj_0", kind: PReturn, horizon: 1,
			sampler: PSPoint(SInd("sma", "close", 5, null)), samples: 1, seed: 1
		}];
		return g;
	}

	public function testReferencedProjectionRendersAsPreludeFieldAndParses() {
		var src = Expand.expand(projReadingGenome());
		Assert.isTrue(src.indexOf('proj_0__p50 = sma("close", 5)') >= 0); // field emitted before onBar
		Assert.isTrue(src.indexOf("crossover(proj_0__p50") >= 0);         // policy reads it
		Assert.notNull(new MuseParser().parse(src, "<proj-test>"));       // valid MuseScript
	}

	public function testUnreadProjectionEmitsNoPreludeField() {
		// Declared but never referenced ⇒ no field, byte-identical to no projection (P0.a contract).
		var g = baseGenome();
		g.projections = [pointProj("proj_0")];
		Assert.equals(Expand.expand(baseGenome()), Expand.expand(g));
	}

	public function testPointProjectionTradesLikeInlinedSeries() {
		// A PSPoint projection referenced once must be behavior-identical to inlining its series.
		var bars = BarFeed.synthetic(240, 1).all();
		var gInline = baseGenome();
		gInline.entryLong = BCross("over", SInd("sma", "close", 5, null), SPrice("close"));
		var frInline = Fitness.evaluate(gInline, bars, "js");
		var frProj = Fitness.evaluate(projReadingGenome(), bars, "js");
		Assert.isTrue(frInline.ok);            // the inlined strategy actually ran
		Assert.equals(frInline.ok, frProj.ok);
		Assert.floatEquals(frInline.sharpe, frProj.sharpe);
		Assert.equals(frInline.trades, frProj.trades);
	}

	// ── P1.5: PSNoise Monte-Carlo fan (closed-form location-scale reductions) ─────────────────

	public function testMcFanShocksDeterministicOrderedAndCentered() {
		var a = McFan.shocks(7, 16, NGaussian);
		var b = McFan.shocks(7, 16, NGaussian);
		Assert.equals(16, a.length);
		for (i in 0...16) Assert.floatEquals(a[i], b[i]); // same seed ⇒ identical shocks
		var s = McFan.sortedCopy(a);
		Assert.isTrue(McFan.quantile(s, 0.05) <= McFan.quantile(s, 0.50)); // quantiles ordered
		Assert.isTrue(McFan.quantile(s, 0.50) <= McFan.quantile(s, 0.95));
		Assert.isTrue(Math.abs(McFan.mean(a)) < 0.75); // gaussian ⇒ mean ≈ 0
	}

	public function testMcFanDifferentSeedsDiffer() {
		var a = McFan.shocks(1, 8, NGaussian);
		var b = McFan.shocks(2, 8, NGaussian);
		var anyDiff = false;
		for (i in 0...8) if (Math.abs(a[i] - b[i]) > 1e-9) anyDiff = true;
		Assert.isTrue(anyDiff);
	}

	static function fanGenome(seed:Int):StrategyGenome {
		// proj_0 = Gaussian fan around close with vol=2; policy gates an sma cross on the fan spread.
		var g = baseGenome();
		g.entryLong = BAnd(
			BCmp("<", KSeries(SProj("proj_0", "spread")), KConst(1000.0)),
			BCross("over", SInd("sma", "close", 5, null), SPrice("close"))
		);
		g.projections = [{
			name: "proj_0", kind: PReturn, horizon: 5,
			sampler: PSNoise(SPrice("close"), KConst(2.0), NGaussian), samples: 8, seed: seed
		}];
		return g;
	}

	public function testPSNoiseSpreadRendersAsClosedFormAndRuns() {
		var g = fanGenome(3);
		var src = Expand.expand(g);
		Assert.isTrue(src.indexOf("proj_0__spread = ") >= 0); // fan reduction emitted as a field
		Assert.isTrue(src.indexOf("* (2)") >= 0);             // spread = coef * (vol=2)
		Assert.notNull(new MuseParser().parse(src, "<fan-test>"));
		var fr = Fitness.evaluate(g, BarFeed.synthetic(240, 1).all(), "js");
		Assert.isTrue(fr.ok); // the fan expression evaluates end-to-end
	}

	public function testFanFitnessIsDeterministic() {
		var bars = BarFeed.synthetic(240, 1).all();
		var g = fanGenome(5);
		var f1 = Fitness.evaluate(g, bars, "js");
		var f2 = Fitness.evaluate(g, bars, "js");
		Assert.equals(f1.trades, f2.trades);
		Assert.floatEquals(f1.sharpe, f2.sharpe);
	}

	// ── the projection-definition digest (the fitness-cache collision fix) ────────────────────

	public function testReferencedProjectionSeedAffectsStructuralKey() {
		// Same SProj reference, different projection seed ⇒ different rendered source ⇒ different key.
		Assert.notEquals(Canonical.structuralKey(fanGenome(1)), Canonical.structuralKey(fanGenome(2)));
		Assert.equals(Canonical.structuralKey(fanGenome(1)), Canonical.structuralKey(fanGenome(1)));
	}

	public function testUnreferencedProjectionDefinitionStaysInert() {
		// baseGenome's policy does NOT reference proj_0, so its seed must not change the key at all.
		function withDecl(seed:Int):StrategyGenome {
			var g = baseGenome();
			g.projections = [{
				name: "proj_0", kind: PReturn, horizon: 5,
				sampler: PSNoise(SPrice("close"), KConst(2.0), NGaussian), samples: 8, seed: seed
			}];
			return g;
		}
		Assert.equals(Canonical.structuralKey(withDecl(1)), Canonical.structuralKey(withDecl(2)));
		Assert.equals(Canonical.structuralKey(baseGenome()), Canonical.structuralKey(withDecl(1)));
	}

	// ── P2: leakage-free forecast-skill scoring ──────────────────────────────────────────────

	static function rampBars(n:Int):Array<Bar> {
		return [
			for (i in 0...n) {
				var c = 100.0 + i;
				({open: c, high: c + 0.5, low: c - 0.5, close: c, volume: 1.0, time: i * 1.0, index: i} : Bar);
			}
		];
	}

	/** Choppy oscillating tape: close[t] does NOT trivially predict close[t+H]. */
	static function zigzagBars(n:Int):Array<Bar> {
		return [
			for (i in 0...n) {
				var c = 100.0 + 5.0 * Math.sin(i * 0.5);
				({open: c, high: c + 0.5, low: c - 0.5, close: c, volume: 1.0, time: i * 1.0, index: i} : Bar);
			}
		];
	}

	public function testRankICPerfectAndInverse() {
		var p = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
		Assert.floatEquals(1.0, ProjectionScore.rankIC(p, [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]));
		Assert.floatEquals(-1.0, ProjectionScore.rankIC(p, [60.0, 50.0, 40.0, 30.0, 20.0, 10.0]));
	}

	public function testDirectionalSkillPerfectAndAnti() {
		var p = [1.0, -1.0, 1.0, -1.0];
		Assert.floatEquals(1.0, ProjectionScore.directionalSkill(p, [2.0, -3.0, 4.0, -1.0]));
		Assert.floatEquals(-1.0, ProjectionScore.directionalSkill(p, [-2.0, 3.0, -4.0, 1.0]));
		Assert.floatEquals(1.0, ProjectionScore.directionalAccuracy(p, [2.0, -3.0, 4.0, -1.0]));
		Assert.floatEquals(0.0, ProjectionScore.directionalAccuracy(p, [-2.0, 3.0, -4.0, 1.0]));
	}

	public function testHitRateTracksForecastMoveDirection() {
		// PSPoint(close): predicted move is 0 → hit-rate 0 on a trending tape (never matches sign).
		var bars = rampBars(20);
		var decl:ProjectionDecl = {
			name: "p",
			kind: PLevel,
			horizon: 1,
			sampler: PSPoint(SPrice("close")),
			samples: 1,
			seed: 1
		};
		var hr = ProjectionScore.hitRate(decl, [], bars);
		Assert.isTrue(Math.isFinite(hr));
		Assert.isTrue(hr >= 0 && hr <= 1);
		Assert.floatEquals(0.0, hr);
	}

	public function testRealizedTargetShapesAndLastHExcluded() {
		var bars = rampBars(6); // close = 100..105
		var lvl = ProjectionScore.realizedTarget(bars, PLevel, 1);
		Assert.equals(6, lvl.length);
		Assert.floatEquals(101.0, lvl[0]);      // close[t+1]
		Assert.isTrue(Math.isNaN(lvl[5]));      // last H=1 bar has no future target
		Assert.floatEquals(1.0, ProjectionScore.realizedTarget(bars, PDirection, 1)[0]); // rising
		Assert.floatEquals(101.0 / 100.0 - 1.0, ProjectionScore.realizedTarget(bars, PReturn, 1)[0]);
	}

	public function testLevelForecastHasHighSkillOnTrend() {
		// close[t] perfectly rank-predicts close[t+3] on a monotone ramp ⇒ IC ≈ 1.
		// Also exercises the NmaFitness column helper end-to-end.
		var decl:ProjectionDecl = {
			name: "proj_0", kind: PLevel, horizon: 3,
			sampler: PSPoint(SPrice("close")), samples: 1, seed: 1
		};
		Assert.isTrue(ProjectionScore.skill(decl, [], rampBars(60)) > 0.99);
	}

	public function testFitnessProjectionScoreWiredForReferencedProjection() {
		var g = baseGenome();
		g.entryLong = BCross("over", SProj("proj_0", "p50"), SPrice("close"));
		g.projections = [{
			name: "proj_0", kind: PLevel, horizon: 3,
			sampler: PSPoint(SPrice("close")), samples: 1, seed: 1
		}];
		Assert.isTrue(Fitness.projectionScore(g, rampBars(60)) > 0.9);
	}

	public function testUnreferencedProjectionIsNotScored() {
		// baseGenome does not reference proj_0 ⇒ nothing scoreable ⇒ NaN aggregate.
		var g = baseGenome();
		g.projections = [{
			name: "proj_0", kind: PLevel, horizon: 3,
			sampler: PSPoint(SPrice("close")), samples: 1, seed: 1
		}];
		Assert.isTrue(Math.isNaN(Fitness.projectionScore(g, rampBars(60))));
	}

	// ── P3: forecast skill as a MAP-Elites niching axis (the selection payoff) ────────────────

	public function testNormSkillMapping() {
		Assert.floatEquals(0.5, MapElites.normSkill(Math.NaN)); // no forecast ⇒ neutral
		Assert.floatEquals(1.0, MapElites.normSkill(1.0));
		Assert.floatEquals(0.0, MapElites.normSkill(-1.0));
		Assert.floatEquals(0.5, MapElites.normSkill(0.0));
	}

	public function testForecastSkillIsADistinctDescriptorAxis() {
		var lo = MapElites.behaviorVecWithSkill(0.05, 10, 0.5, 0.3, -0.9);
		var hi = MapElites.behaviorVecWithSkill(0.05, 10, 0.5, 0.3, 0.9);
		Assert.equals(5, lo.length);              // 4 behaviour axes + 1 forecast-skill axis
		Assert.floatEquals(lo[0], hi[0]);         // behaviour identical …
		Assert.floatEquals(lo[1], hi[1]);
		Assert.floatEquals(lo[2], hi[2]);
		Assert.floatEquals(lo[3], hi[3]);
		Assert.isTrue(Math.abs(lo[4] - hi[4]) > 0.5); // … forecast-skill axis differs strongly
	}

	public function testForecastSkillSplitsGenomesIntoDifferentCells() {
		// Explicit centroids identical in behaviour, split on the skill axis (0.0 vs 1.0).
		var cents = [[0.25, 0.25, 0.5, 0.3, 0.0], [0.25, 0.25, 0.5, 0.3, 1.0]];
		var lo = MapElites.assignCellWithSkill(0.05, 10, 0.5, 0.3, -0.9, cents); // normSkill 0.05 → cvt_0
		var hi = MapElites.assignCellWithSkill(0.05, 10, 0.5, 0.3, 0.9, cents);  // normSkill 0.95 → cvt_1
		Assert.notEquals(lo, hi);
	}

	public function testArchiveKeepsBothForecastQualitiesAsCoevolvedPairs() {
		// The payoff: two EQUALLY FIT, BEHAVIOURALLY IDENTICAL genomes — one a poor forecaster, one a
		// strong one — both survive, because forecast skill niches them apart. Raw-fitness selection
		// would keep only one; this is the co-evolution of forecaster/manager pairs.
		var cents = [[0.25, 0.25, 0.5, 0.3, 0.0], [0.25, 0.25, 0.5, 0.3, 1.0]];
		var arch = new EliteArchive();
		var poor = baseGenome();
		poor.name = "poorForecaster";
		var good = baseGenome();
		good.name = "goodForecaster";
		arch.offer(poor, 2.0, MapElites.assignCellWithSkill(0.05, 10, 0.5, 0.3, -0.8, cents));
		arch.offer(good, 2.0, MapElites.assignCellWithSkill(0.05, 10, 0.5, 0.3, 0.8, cents));
		Assert.equals(2, arch.size()); // both kept — not competed away into one basin
	}

	// ── the leakage-honesty guarantee ────────────────────────────────────────────────────────

	public function testScorerRewardsForesightButPitProjectionCannotCheat() {
		var bars = zigzagBars(60); // choppy: close[t] does NOT trivially predict close[t+3]
		// (1) the metric CAN detect perfect foresight — a forecast equal to the realized target scores 1
		var y = ProjectionScore.realizedTarget(bars, PLevel, 3);
		Assert.floatEquals(1.0, ProjectionScore.rankIC(y, y));
		// (2) but a PIT projection (= close) can NOT achieve perfect foresight on a choppy tape:
		// its skill is strictly, meaningfully below perfect — it does not see the future.
		var decl:ProjectionDecl = {
			name: "proj_0", kind: PLevel, horizon: 3,
			sampler: PSPoint(SPrice("close")), samples: 1, seed: 1
		};
		Assert.isTrue(ProjectionScore.skill(decl, [], bars) < 0.95);
	}
}
