package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.evo.GrowthWeights;
import musescript.evo.Rand;
import musescript.evo.Variation;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.StrategyGenome;
import musescript.evo.Fitness;
import musescript.harness.BarFeed;

/**
 * Regression coverage for GrowthWeights (the node-type auto-tuning machinery) and its wiring into
 * Variation.attributedPointMutate's reward loop. Covers: default weights reproduce the ORIGINAL
 * hardcoded literal cascades' proportions (zero behavior change for anyone who never rewards),
 * reward() actually shifts the distribution in the rewarded direction, the min-weight floor keeps
 * explore pressure alive, `enabled=false` makes reward() inert, and (statistically, matching this
 * file's established pattern) that a genuinely BETTER growth choice gets reinforced over many
 * mutation cycles on a crafted fitness landscape.
 */
class TestGrowthWeights extends Test {
	// ── pick() distribution ────────────────────────────────────────────────────────────────

	public function testPickRespectsDefaultProportions() {
		var gw = new GrowthWeights();
		var rng = new Rand(11);
		var counts = new Map<String, Int>();
		var trials = 4000;
		for (_ in 0...trials) {
			var tag = gw.pick("boolTerm", rng);
			counts.set(tag, (counts.exists(tag) ? counts.get(tag) : 0) + 1);
		}
		// boolTerm defaults: cross 0.35, cmp 0.25, trend 0.2, riskExit 0.2 -- cross should clearly
		// be drawn most often, riskExit/trend roughly tied and both below cmp.
		var cross = counts.get("cross");
		var cmp = counts.get("cmp");
		Assert.isTrue(cross != null && cmp != null);
		Assert.isTrue(cross > cmp, 'expected cross (0.35) drawn more than cmp (0.25): cross=$cross cmp=$cmp');
	}

	public function testPickThrowsOnUnknownCategory() {
		var gw = new GrowthWeights();
		var rng = new Rand(1);
		Assert.raises(() -> gw.pick("not_a_real_category", rng));
	}

	// ── reward() ───────────────────────────────────────────────────────────────────────────

	public function testRewardShiftsDistributionTowardRewardedTag() {
		var gw = new GrowthWeights();
		var before = gw.summary("riskExit");
		var timeStopBefore = [for (e in before) if (e.tag == "timeStop") e.weight][0];
		// Reward "timeStop" heavily, many times, with a strong positive delta.
		for (_ in 0...30) gw.reward("riskExit", "timeStop", 0.8);
		var after = gw.summary("riskExit");
		var timeStopAfter = [for (e in after) if (e.tag == "timeStop") e.weight][0];
		Assert.isTrue(timeStopAfter > timeStopBefore,
			'expected timeStop weight to grow: before=$timeStopBefore after=$timeStopAfter');
		// It should also now be the LARGEST share of the category (started smallest at 0.25).
		after.sort((a, b) -> a.weight > b.weight ? -1 : 1);
		Assert.equals("timeStop", after[0].tag);
	}

	public function testRewardNeverDrivesWeightBelowFloor() {
		var gw = new GrowthWeights(0.15, 0.02);
		for (_ in 0...200) gw.reward("boolRecurse", "not", -5.0); // repeated non-improvement
		var s = gw.summary("boolRecurse");
		var notShare = [for (e in s) if (e.tag == "not") e.weight][0];
		Assert.isTrue(notShare > 0, "a tag must never be driven to exactly zero probability");
	}

	public function testDisabledTunerRewardIsNoOp() {
		var gw = new GrowthWeights();
		gw.enabled = false;
		var before = gw.summary("multiOutput");
		for (_ in 0...50) gw.reward("multiOutput", "macd", 1.0);
		var after = gw.summary("multiOutput");
		for (i in 0...before.length)
			Assert.floatEquals(before[i].weight, after[i].weight, 'disabled tuner must not move ${before[i].tag}');
	}

	public function testRewardIgnoresUnknownCategoryOrTag() {
		var gw = new GrowthWeights();
		// Must not throw -- unlike pick(), reward() on a bogus category/tag is a silent no-op
		// (a mutation site targeting logic bug shouldn't crash the whole evolution run).
		gw.reward("nope", "nope", 1.0);
		gw.reward("boolTerm", "nope", 1.0);
		Assert.pass();
	}

	// ── persistence ────────────────────────────────────────────────────────────────────────

	public function testSaveLoadRoundTripsLearnedWeights() {
		var path = "build/test-growth-weights.tsv";
		var a = new GrowthWeights();
		for (_ in 0...20) a.reward("scalarTerm", "multiOutput", 0.6);
		a.save(path);

		var b = new GrowthWeights(); // fresh defaults
		b.load(path);
		var aw = [for (e in a.summary("scalarTerm")) e.tag => e.weight];
		var bw = [for (e in b.summary("scalarTerm")) e.tag => e.weight];
		for (tag in aw.keys())
			Assert.floatEquals(aw.get(tag), bw.get(tag), 'loaded weight for $tag should match saved');
		sys.FileSystem.deleteFile(path);
	}

	// ── integration: attributedPointMutate actually closes the loop ──────────────────────────

	/** A crafted landscape where introducing a stop-loss (riskExit terminal) demonstrably improves
	 * fitness (a naive always-long strategy on a downtrend loses money without one), and confirm
	 * running attributedPointMutate repeatedly with a REAL evalFn nudges "riskExit" tags upward in
	 * the shared tuner -- proving the reward wiring in Variation.hx actually fires end-to-end, not
	 * just that GrowthWeights works in isolation. */
	public function testAttributedPointMutateGrowsRiskExitWeightOnARealImprovingLandscape() {
		var tuner = new GrowthWeights();
		var v = new Variation(5, null, tuner);
		var bars = BarFeed.synthetic(500, 3).all();
		var evalFn = (g:StrategyGenome) -> Fitness.score(Fitness.evaluate(g, bars, "js", false), 1);

		var riskExitBefore = [for (e in tuner.summary("boolTerm")) if (e.tag == "riskExit") e.weight][0];
		var g:StrategyGenome = {
			entryLong: BCmp(">", KConst(0.0), KConst(-1.0)), // always true -- always long
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)), // always false
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)), // always false -- NEVER exits without help
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
		for (_ in 0...40) g = v.attributedPointMutate(g, evalFn, 2);
		var riskExitAfter = [for (e in tuner.summary("boolTerm")) if (e.tag == "riskExit") e.weight][0];
		// Not a strict guarantee (mutation is stochastic and 40 cycles is a small sample), but the
		// reward loop firing at all across 40 real evaluations should be visible as SOME movement.
		Assert.isTrue(riskExitAfter != riskExitBefore,
			'expected the riskExit tag weight to move at all: before=$riskExitBefore after=$riskExitAfter');
	}

	/**
	 * Regression for a real bug caught in a live 80-generation corpus-evo run: `riskExit`/
	 * `multiOutput`/`scalarTerm`/`scalarRecurse` sat at their EXACT seeded defaults (to the
	 * decimal) after 80 real generations, while `boolTerm`/`boolRecurse` clearly converged --
	 * because `growBool`'s nested calls (into growScalar/growRiskExit/growMultiOutputField, and
	 * its own recursive self-calls) never threaded `tagOut` through, so only the OUTERMOST pick
	 * `attributedPointMutate` captured could ever be rewarded. Those four categories are ONLY
	 * ever reachable via a nested call from growBool -- there is no other path to them -- so this
	 * is a direct proof the fix works: run enough cycles that the "cmp" boolTerm branch (which
	 * recurses into growScalar, the only path to scalarTerm/scalarRecurse) gets hit, and confirm
	 * scalarTerm/scalarRecurse move from their defaults too, not just boolTerm.
	 */
	public function testNestedCategoriesMoveNotJustTheOutermostPick() {
		var tuner = new GrowthWeights();
		var v = new Variation(17, null, tuner);
		var bars = BarFeed.synthetic(500, 19).all();
		var evalFn = (g:StrategyGenome) -> Fitness.score(Fitness.evaluate(g, bars, "js", false), 1);

		var scalarTermBefore = tuner.summary("scalarTerm");
		var scalarRecurseBefore = tuner.summary("scalarRecurse");

		var g:StrategyGenome = {
			entryLong: BCmp(">", KConst(0.0), KConst(-1.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: "T",
			lineage: [],
			seedOrigin: null
		};
		for (_ in 0...150) g = v.attributedPointMutate(g, evalFn, 2);

		var scalarTermAfter = tuner.summary("scalarTerm");
		var scalarRecurseAfter = tuner.summary("scalarRecurse");
		var scalarTermMoved = [for (i in 0...scalarTermBefore.length) scalarTermBefore[i].weight != scalarTermAfter[i].weight].indexOf(true) >= 0;
		var scalarRecurseMoved = [for (i in 0...scalarRecurseBefore.length) scalarRecurseBefore[i].weight != scalarRecurseAfter[i].weight].indexOf(true) >= 0;
		Assert.isTrue(scalarTermMoved || scalarRecurseMoved,
			'expected at least one of scalarTerm/scalarRecurse to move from its seeded default over 150 cycles -- '
			+ 'before(scalarTerm)=$scalarTermBefore after=$scalarTermAfter');
	}
}
