package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.Archipelago;
import musescript.evo.BoolNode;
import musescript.evo.Canonical;
import musescript.evo.Fitness;
import musescript.evo.Foundry;
import musescript.evo.Rand;
import musescript.evo.RivalryArena;
import musescript.evo.OpponentFeatures;
import musescript.evo.ScalarNode;
import musescript.evo.StrategyGenome;
import musescript.evo.SymbolSelector;
import musescript.evo.Variation;

/**
 * Guards for Rivalry Archipelago + Foundry: deme sizing, scale-safe selection blend,
 * cohort sampling, opponent-conditioned retunes, Foundry bag resolve / fork gate.
 * Arena Murmuration run is exercised via corpus-evo smoke, not here (keeps utest free of tick cost).
 */
class TestRivalryArchipelago extends Test {

	static function genome(name:String, ?params:Array<musescript.evo.EvoParam>):StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: params != null ? params : [],
			name: name,
			lineage: [],
			seedOrigin: null
		};
	}

	static function feat(
		rank:Int, niche:String, ?tpb:Float = 0.1, ?hold:Float = 5, ?longFrac:Float = 0.5
	):OpponentFeatures {
		return {
			mtm: 100.0 - rank,
			rank: rank,
			trades: 10,
			tradesPerBar: tpb,
			avgHold: hold,
			longFrac: longFrac,
			dutyCycle: 0.3,
			nicheKey: niche,
			selectorScore: null
		};
	}

	public function testResolveDemeSizePriority() {
		Assert.equals(0, Archipelago.resolveDemeSize(1000, 0, 0, false));
		Assert.equals(128, Archipelago.resolveDemeSize(1000, 0, 0, true));
		Assert.equals(100, Archipelago.resolveDemeSize(1000, 100, 0, true)); // explicit wins
		Assert.equals(125, Archipelago.resolveDemeSize(1000, 0, 8, true)); // ceil(1000/8)
		Assert.equals(0, Archipelago.resolveDemeSize(100, 0, 0, true)); // too small for 2 demes of 128
	}

	public function testDemeCountAndStats() {
		Assert.equals(8, Archipelago.demeCount(1000, 128));
		var fit = [for (i in 0...256) (i % 128) * 1.0];
		var stats = Archipelago.demeStats(fit, 128);
		Assert.equals(2, stats.length);
		Assert.equals(127.0, stats[0].best);
		Assert.equals(127.0, stats[1].best);
	}

	public function testBlendSelectionWeightZeroIdentity() {
		var tape = [1.0, 2.0, Fitness.NEG_INF];
		var riv = [9.0, 8.0, 7.0];
		Assert.equals(tape, Archipelago.blendSelection(tape, riv, 0));
	}

	/**
	 * Scale-safe blend: among dual-valid slots, z-normalize then mix.
	 * A mild tape lead + bad arena z loses to a slightly worse tape + strong arena at weight 0.40.
	 */
	public function testBlendSelectionZNormCanUnseatTapeElite() {
		var tape = [2.0, 1.8, 1.0]; // slot 0 mild tape elite
		var riv = [-2.0, 1.5, 0.5]; // slot 1 won the arena
		var soft = Archipelago.blendSelection(tape, riv, 0.10);
		Assert.isTrue(soft[0] > soft[1]); // soft weight: tape elite still ahead
		var hard = Archipelago.blendSelection(tape, riv, 0.40);
		Assert.isTrue(hard[1] > hard[0]); // default rivalry weight unseats tape-only elite
		Assert.equals(Fitness.NEG_INF,
			Archipelago.blendSelection(tape.concat([Fitness.NEG_INF]), riv.concat([0.0]), 0.5)[3]);
	}

	public function testSampleCohortTakesElitePerDeme() {
		var pop = [for (i in 0...16) genome('g$i')];
		var fit = [for (i in 0...16) i * 1.0]; // last index best in each half
		var cohort = RivalryArena.sampleCohort(pop, fit, 8, 2, new Rand(1));
		Assert.equals(4, cohort.length); // 2 demes * 2
		var deme0 = [for (m in cohort) if (m.deme == 0) m.popIndex];
		Assert.isTrue(deme0.indexOf(7) >= 0); // elite of deme 0
		var deme1 = [for (m in cohort) if (m.deme == 1) m.popIndex];
		Assert.isTrue(deme1.indexOf(15) >= 0);
	}

	public function testMateWithBeaterProducesChild() {
		var v = new Variation(3);
		var a = genome("a");
		var b = genome("b");
		// Make them structurally different so crossover can move material.
		b.entryLong = BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(0.0), KConst(1.0)));
		var child = RivalryArena.mateWithBeater(a, b, v);
		Assert.notNull(child);
		Assert.isTrue(Canonical.structuralKey(child) != null);
	}

	public function testParamBlendTowardWinnerMovesValue() {
		var loser = genome("L", [{name: "p", defaultValue: 1.0, min: 0.0, max: 10.0, step: 0.1, tune: "float"}]);
		var winner = genome("W", [{name: "q", defaultValue: 9.0, min: 0.0, max: 10.0, step: 0.1, tune: "float"}]);
		var after = RivalryArena.paramBlendToward(loser, winner, new Rand(42));
		Assert.isTrue(after != loser);
		Assert.isTrue(after.params[0].defaultValue != 1.0);
		// Moved toward winner (9), not away past 1 in the wrong direction on average.
		Assert.isTrue(after.params[0].defaultValue > 1.0);
	}

	public function testOpponentRespondDivergentNichePrefersMate() {
		var v = new Variation(7);
		var loser = genome("L");
		var winner = genome("W");
		winner.entryLong = BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(0.0), KConst(1.0)));
		var lf = feat(5, "scalp_short", 0.5, 2, 0.2);
		var wf = feat(0, "trend_long", 0.05, 40, 0.9);
		var resp = RivalryArena.opponentRespond(loser, winner, lf, wf, v, new Rand(11));
		Assert.isTrue(resp.kind == "mate" || resp.kind == "es-nudge");
		Assert.isTrue(resp.genome != loser || resp.kind == "noop");
	}

	public function testPickBeaterPrefersDivergentNiche() {
		var order = [0, 1, 2, 3];
		var feats = [
			feat(0, "A"),
			feat(1, "B"),
			feat(2, "A"),
			feat(3, "A")
		];
		var loser = feat(7, "A");
		// With a fixed seed, divergent niche (idx 1) should win the roulette often.
		var hits = 0;
		for (s in 0...40) {
			var pick = RivalryArena.pickBeater(order, 3, loser, feats, new Rand(s * 17 + 3));
			if (pick == 1) hits++;
		}
		Assert.isTrue(hits >= 10); // boosted 2x over same-niche winners
	}

	public function testNicheDistanceZeroForIdentical() {
		var a = feat(0, "x");
		var b = feat(1, "x");
		Assert.floatEquals(0.0, RivalryArena.nicheDistance(a, b), 1e-12);
	}

	public function testFoundryBagsBothAutoAndExplicit() {
		var f = new Foundry(10, 4, "auto");
		var bags = f.resolveBags(["data/a.csv", "data/b.csv"], true);
		Assert.isTrue(bags.length >= 2);
		Assert.isTrue(bags.indexOf("data/a.csv") >= 0 || bags.indexOf("data/b.csv") >= 0);
		var f2 = new Foundry(10, 4, "bags/custom.json");
		var bags2 = f2.resolveBags(["data/a.csv"], false);
		Assert.isTrue(bags2.indexOf("bags/custom.json") >= 0);
		Assert.isTrue(bags2.indexOf("data/a.csv") >= 0);
	}

	/** Without an OOS scorer Foundry must refuse inject — no blind structural inserts. */
	public function testFoundryRejectsWithoutOosScorer() {
		var f = new Foundry(5, 4, "auto");
		var v = new Variation(9);
		var c1 = genome("c1");
		var c2 = genome("c2");
		c2.entryLong = BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(0.0), KConst(1.0)));
		var ev = f.maybeTick(4, [c1, c2], v, ["auto:propose"]);
		Assert.notNull(ev);
		Assert.isFalse(ev.injected);
		Assert.equals("reject", ev.phase);
		Assert.isTrue(ev.note.indexOf("no OOS scorer") >= 0);
	}

	/** OOS gate keeps a novel hybrid that beats parent; rejects clones / worse OOS. */
	public function testFoundryOosGateKeepAndReject() {
		var f = new Foundry(5, 4, "auto");
		Assert.isFalse(f.due(0));
		Assert.isTrue(f.due(4)); // gen+1 % 5 == 0
		var v = new Variation(9);
		var c1 = genome("c1");
		var c2 = genome("c2");
		c2.entryLong = BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(0.0), KConst(1.0)));
		var parentKey = Canonical.structuralKey(c1);
		// Scorer: parent scores 1.0; anything else scores 2.0 → keep.
		var ev = f.maybeTick(4, [c1, c2], v, ["auto:propose"], null, function(g) {
			return Canonical.structuralKey(g) == parentKey ? 1.0 : 2.0;
		});
		Assert.notNull(ev);
		Assert.isTrue(ev.injected);
		Assert.notNull(ev.hybrid);
		Assert.equals("consensus", ev.phase);
		Assert.isTrue(ev.oosHybrid != null && ev.oosHybrid > ev.oosParent);
		// Timeline: fork → trials → … → consensus
		Assert.isTrue(f.events.length >= 3);
		Assert.equals("fork", f.events[0].phase);

		// Worse-than-parent OOS → reject
		var f2 = new Foundry(5, 4, "auto");
		var ev2 = f2.maybeTick(4, [c1, c2], v, ["tape/a", "tape/b"], null, function(_) return 0.5);
		Assert.notNull(ev2);
		Assert.isFalse(ev2.injected);
		Assert.equals("reject", ev2.phase);
	}

	public function testScatterAndMergeChannel() {
		var z = new Map<Int, Float>();
		z.set(1, 1.5);
		z.set(3, -0.5);
		var fresh = RivalryArena.scatterToPop(5, z);
		Assert.equals(Fitness.NEG_INF, fresh[0]);
		Assert.floatEquals(1.5, fresh[1], 1e-9);
		var prior = [0.0, 10.0, 10.0, 10.0, 0.0];
		var merged = RivalryArena.mergeChannel(prior, fresh, 0.9);
		Assert.floatEquals(1.5, merged[1], 1e-9); // fresh wins
		Assert.floatEquals(9.0, merged[2], 1e-9); // prior decayed (unsampled)
	}

	/** Auto arena agent budget must stay near cohort — never silently inflate to compete-agents 500. */
	public function testResolveArenaAgentsCapsNearCohort() {
		Assert.equals(80, RivalryArena.resolveAgents(64, 0, 500));
		Assert.equals(96, RivalryArena.resolveAgents(80, 0, 500));
		Assert.equals(128, RivalryArena.resolveAgents(120, 0, 500)); // hard cap
		Assert.equals(200, RivalryArena.resolveAgents(64, 200, 500)); // explicit wins
		Assert.equals(65, RivalryArena.resolveAgents(64, 10, 500)); // explicit below cohort+1 bumps up
		Assert.equals(70, RivalryArena.resolveAgents(64, 0, 70)); // competeAgents ceiling when auto would be 80
	}

	public function testBlendSelectorTowardMovesWeights() {
		var rng = new Rand(5);
		var a = new SymbolSelector(4, rng);
		var b = new SymbolSelector(4, rng);
		// Force divergence
		a.weights = [0.0, 0.0, 0.0, 0.0];
		b.weights = [1.0, 1.0, 1.0, 1.0];
		var map = new Map<Int, SymbolSelector>();
		map.set(0, a);
		map.set(1, b);
		RivalryArena.blendSelectorToward(map, 0, 1, new Rand(9));
		var child = map.get(0);
		Assert.isTrue(child.weights[0] > 0.0);
		Assert.isTrue(child.weights[0] < 1.0);
	}
}
