package musescript.evo;

import musescript.harness.Bar;
import musescript.evo.nma.NmaCreditBank;

/**
 * Cooperative coevolution vertical — two populations, shared pair fitness
 * (PROJECTION_COEVOLUTION_PLAN.md §8 v2 / P5).
 *
 *   FORECASTER pop — carries `ProjectionDecl`s (`PSPoint` samplers). Policy trees are stubs.
 *   MANAGER pop    — carries entry/exit/size trees that may read `SProj`; projections come
 *                    from the paired forecaster at eval time.
 *
 * Pairing is sticky (manager `i` ↔ forecaster `partners[i]`), refreshed with a small probability
 * each generation. Compose → joint genome → trading score is credited to **both** roles.
 * Forecaster also records purged `projSkill` for niche/telemetry — **never** folded into
 * selection as `--proj-weight` (MAP skill axis remains the selection story for projection skill).
 *
 * Crisp vertical: coupling + pairing + tests. Deferred: full Red-Queen / multi-partner
 * best-response, Archipelago demes dual to RivalryArena, CRPS / native `NmaSProj`.
 *
 * «δύο δῆμοι, μία ἀμοιβή· μάντις καὶ οἰκονόμος.»
 */
enum CceaRole {
	Forecaster;
	Manager;
}

typedef CceaPairScore = {
	var trading:Float;
	var skill:Float;
	var joint:StrategyGenome;
	var fr:FitnessResult;
};

typedef CceaState = {
	var forecasters:Array<StrategyGenome>;
	var managers:Array<StrategyGenome>;
	/** Manager i → forecaster index. */
	var partners:Array<Int>;
	var fFit:Array<Float>;
	var mFit:Array<Float>;
	/** Purged OOS skill per forecaster (niche telemetry; not additive selection). */
	var fSkill:Array<Float>;
	var gen:Int;
};

typedef CceaResult = {
	var state:CceaState;
	var bestTrading:Float;
	var bestSkill:Float;
	var bestJoint:Null<StrategyGenome>;
	var gens:Int;
};

class CceaCoEvo {
	/** Fan fields managers may grow against a paired projection. */
	public static var MANAGER_PROJ_FIELDS:Array<String> = ["p50", "mean", "spread"];

	/** Compose manager policy + forecaster projections into one evaluable genome. */
	public static function compose(forecaster:StrategyGenome, manager:StrategyGenome):StrategyGenome {
		var projs = forecaster.projections != null
			? [for (p in forecaster.projections) copyDecl(p)]
			: null;
		return {
			entryLong: manager.entryLong,
			entryShort: manager.entryShort,
			exitLong: manager.exitLong,
			exitShort: manager.exitShort,
			size: manager.size,
			params: manager.params != null ? manager.params.copy() : [],
			name: (manager.name != null ? manager.name : "M") + "+" + (forecaster.name != null ? forecaster.name : "F"),
			lineage: ["ccea-pair",
				forecaster.name != null ? forecaster.name : "F",
				manager.name != null ? manager.name : "M"],
			seedOrigin: manager.seedOrigin,
			projections: projs,
			panelAction: manager.panelAction
		};
	}

	/** Seed a forecaster: inert flat policy + one `PSPoint` projection named `proj_0`. */
	public static function seedForecaster(name:String, ?horizon:Int = 5, ?window:Int = 20, ?seed:Int = 1):StrategyGenome {
		return {
			entryLong: alwaysFalse(),
			entryShort: alwaysFalse(),
			exitLong: alwaysFalse(),
			exitShort: alwaysFalse(),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: ["ccea-forecaster"],
			seedOrigin: seed,
			projections: [{
				name: "proj_0",
				kind: PLevel,
				horizon: horizon,
				sampler: PSPoint(SInd("sma", "close", window, null)),
				samples: 1,
				seed: seed
			}]
		};
	}

	/**
	 * Seed a manager that reads `proj_0__p50` vs close (load-bearing when paired with a
	 * useful forecaster). No projections of its own — compose supplies them.
	 */
	public static function seedManager(name:String):StrategyGenome {
		return {
			entryLong: BCross("over", SProj("proj_0", "p50"), SPrice("close")),
			entryShort: alwaysFalse(),
			exitLong: BCross("under", SProj("proj_0", "p50"), SPrice("close")),
			exitShort: alwaysFalse(),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: ["ccea-manager"],
			seedOrigin: null,
			projections: null
		};
	}

	/** Evaluate one forecaster×manager pair (trading + purged skill). */
	public static function scorePair(
		forecaster:StrategyGenome,
		manager:StrategyGenome,
		bars:Array<Bar>,
		?evalFn:StrategyGenome->FitnessResult
	):CceaPairScore {
		var joint = compose(forecaster, manager);
		var eval = evalFn != null ? evalFn : function(g) return Fitness.evaluate(g, bars, "js");
		var fr = eval(joint);
		var trading = ProjectionAblation.tradingScore(fr);
		var skill = 0.0;
		if (joint.projections != null && joint.projections.length > 0) {
			var ps = Fitness.projectionScorePurged(joint, bars);
			if (ps != null && Math.isFinite(ps)) skill = ps;
		}
		return { trading: trading, skill: skill, joint: joint, fr: fr };
	}

	/** Build initial two-pop state with round-robin partners. */
	public static function init(
		fPop:Int, mPop:Int, seed:Int,
		?horizon:Int = 5
	):CceaState {
		var forecasters:Array<StrategyGenome> = [];
		var managers:Array<StrategyGenome> = [];
		for (i in 0...fPop)
			forecasters.push(seedForecaster('F$i', horizon, 10 + (i % 3) * 5, seed + i));
		for (i in 0...mPop)
			managers.push(seedManager('M$i'));
		var partners = [for (i in 0...mPop) i % fPop];
		return {
			forecasters: forecasters,
			managers: managers,
			partners: partners,
			fFit: [for (_ in 0...fPop) Fitness.NEG_INF],
			mFit: [for (_ in 0...mPop) Fitness.NEG_INF],
			fSkill: [for (_ in 0...fPop) 0.0],
			gen: 0
		};
	}

	/**
	 * Score every manager against its sticky partner; fold trading into both fitness arrays.
	 * Forecaster skill = max purged skill observed across managers paired to it this gen.
	 */
	public static function evaluateState(
		st:CceaState,
		bars:Array<Bar>,
		?evalFn:StrategyGenome->FitnessResult,
		?depositAblation:Bool = false
	):Void {
		var fBestTrade = [for (_ in st.forecasters) Fitness.NEG_INF];
		var fBestSkill = [for (_ in st.forecasters) Math.NEGATIVE_INFINITY];
		for (mi in 0...st.managers.length) {
			var fi = st.partners[mi];
			if (fi < 0 || fi >= st.forecasters.length) fi = 0;
			var sc = scorePair(st.forecasters[fi], st.managers[mi], bars, evalFn);
			st.mFit[mi] = sc.trading;
			if (sc.trading > fBestTrade[fi] || fBestTrade[fi] == Fitness.NEG_INF)
				fBestTrade[fi] = sc.trading;
			if (sc.skill > fBestSkill[fi])
				fBestSkill[fi] = sc.skill;
			if (depositAblation && sc.joint.projections != null) {
				ProjectionAblation.deposit(sc.joint, bars, evalFn);
			}
		}
		for (fi in 0...st.forecasters.length) {
			st.fFit[fi] = fBestTrade[fi];
			st.fSkill[fi] = Math.isFinite(fBestSkill[fi]) ? fBestSkill[fi] : 0.0;
		}
	}

	/**
	 * One CCEA generation: evaluate → (optional credit→tuner) → vary each pop → refresh partners.
	 * Selection uses **trading** fitness only. Skill is recorded on `fSkill`, never added to fit.
	 */
	public static function step(
		st:CceaState,
		bars:Array<Bar>,
		fVar:Variation,
		mVar:Variation,
		rng:Rand,
		?opts:{
			?elite:Int,
			?tournament:Int,
			?partnerRefresh:Float,
			?ablate:Bool,
			?evalFn:StrategyGenome->FitnessResult
		}
	):CceaState {
		var elite = opts != null && opts.elite != null ? opts.elite : 1;
		var tournament = opts != null && opts.tournament != null ? opts.tournament : 3;
		var refresh = opts != null && opts.partnerRefresh != null ? opts.partnerRefresh : 0.15;
		var ablate = opts != null && opts.ablate == true;
		var evalFn = opts != null ? opts.evalFn : null;

		evaluateState(st, bars, evalFn, ablate);
		// Variation growth: bias `projRead` tags from the credit bank (P4 → P5 loop).
		ProjectionAblation.applyBankToTuner(fVar.tuner);
		ProjectionAblation.applyBankToTuner(mVar.tuner);
		mVar.growableProjNames = declaredProjNames(st.forecasters);
		mVar.growableProjFields = MANAGER_PROJ_FIELDS.copy();

		st.forecasters = evolveRole(st.forecasters, st.fFit, fVar, Forecaster, elite, tournament, rng);
		st.managers = evolveRole(st.managers, st.mFit, mVar, Manager, elite, tournament, rng);

		// Sticky partners; rare refresh toward a random (or better-skill) forecaster.
		for (mi in 0...st.managers.length) {
			if (rng.float() < refresh) {
				var pick = rng.int(st.forecasters.length);
				// Soft bias: prefer higher recorded skill among a sample of 2.
				var alt = rng.int(st.forecasters.length);
				if (st.fSkill[alt] > st.fSkill[pick]) pick = alt;
				st.partners[mi] = pick;
			} else if (st.partners[mi] >= st.forecasters.length) {
				st.partners[mi] = mi % st.forecasters.length;
			}
		}
		st.gen++;
		return st;
	}

	/**
	 * Multi-gen mini proof / CLI smoke. Trading quality drives selection; bestSkill is the
	 * niche-axis number for the best joint (never selection-additive).
	 */
	public static function runMini(
		bars:Array<Bar>,
		?opts:{
			?seed:Int,
			?fPop:Int,
			?mPop:Int,
			?gens:Int,
			?horizon:Int,
			?ablate:Bool
		}
	):CceaResult {
		var seed = opts != null && opts.seed != null ? opts.seed : 42;
		var fPop = opts != null && opts.fPop != null ? opts.fPop : 4;
		var mPop = opts != null && opts.mPop != null ? opts.mPop : 4;
		var gens = opts != null && opts.gens != null ? opts.gens : 3;
		var horizon = opts != null && opts.horizon != null ? opts.horizon : 5;
		var ablate = opts != null && opts.ablate == true;

		NmaCreditBank.clear();
		var st = init(fPop, mPop, seed, horizon);
		var fVar = new Variation(seed, null, null, null);
		var mVar = new Variation(seed + 17, null, null, null);
		mVar.growableProjNames = ["proj_0"];
		mVar.growableProjFields = MANAGER_PROJ_FIELDS.copy();
		var rng = new Rand(seed + 99);

		var bestTrading = Fitness.NEG_INF;
		var bestSkill = 0.0;
		var bestJoint:Null<StrategyGenome> = null;

		for (_ in 0...gens) {
			step(st, bars, fVar, mVar, rng, { elite: 1, tournament: 3, ablate: ablate });
			for (mi in 0...st.managers.length) {
				var fi = st.partners[mi];
				var sc = scorePair(st.forecasters[fi], st.managers[mi], bars);
				if (sc.trading > bestTrading) {
					bestTrading = sc.trading;
					bestSkill = sc.skill;
					bestJoint = sc.joint;
				}
			}
		}
		return { state: st, bestTrading: bestTrading, bestSkill: bestSkill, bestJoint: bestJoint, gens: gens };
	}

	// ── internal ────────────────────────────────────────────────────────────────────────────

	static function evolveRole(
		pop:Array<StrategyGenome>,
		fit:Array<Float>,
		variation:Variation,
		role:CceaRole,
		elite:Int,
		tournament:Int,
		rng:Rand
	):Array<StrategyGenome> {
		var n = pop.length;
		if (n == 0) return pop;
		variation.beginGeneration();
		var order = [for (i in 0...n) i];
		order.sort(function(a, b) {
			var fa = fit[a], fb = fit[b];
			if (fa != fb) return fa < fb ? 1 : -1;
			return a - b;
		});
		var next:Array<StrategyGenome> = [];
		var e = elite < 0 ? 0 : (elite > n ? n : elite);
		for (i in 0...e)
			next.push(Variation.copyGenomePublic(pop[order[i]]));
		while (next.length < n) {
			var p1 = tournamentPick(pop, fit, tournament, rng);
			var p2 = tournamentPick(pop, fit, tournament, rng);
			var child = variation.crossover(p1, p2);
			child = roleMutate(variation, child, role);
			next.push(child);
		}
		return next;
	}

	static function roleMutate(v:Variation, g:StrategyGenome, role:CceaRole):StrategyGenome {
		return switch (role) {
			case Forecaster: v.mutateProjectionSampler(g);
			case Manager: v.mutateManagerPolicy(g);
		};
	}

	static function tournamentPick(
		pop:Array<StrategyGenome>, fit:Array<Float>, k:Int, rng:Rand
	):StrategyGenome {
		var best = rng.int(pop.length);
		var bestF = fit[best];
		var t = k < 1 ? 1 : k;
		for (_ in 1...t) {
			var j = rng.int(pop.length);
			if (fit[j] > bestF) {
				best = j;
				bestF = fit[j];
			}
		}
		return pop[best];
	}

	static function declaredProjNames(forecasters:Array<StrategyGenome>):Array<String> {
		var seen:Map<String, Bool> = new Map();
		var out:Array<String> = [];
		for (g in forecasters) {
			if (g.projections == null) continue;
			for (p in g.projections) {
				if (!seen.exists(p.name)) {
					seen.set(p.name, true);
					out.push(p.name);
				}
			}
		}
		if (out.length == 0) out.push("proj_0");
		return out;
	}

	static function alwaysFalse():BoolNode {
		return BCmp(">", KConst(0.0), KConst(1.0));
	}

	static function copyDecl(p:ProjectionDecl):ProjectionDecl {
		return {
			name: p.name, kind: p.kind, horizon: p.horizon, sampler: p.sampler,
			samples: p.samples, seed: p.seed,
			phiDeltas: p.phiDeltas != null ? [for (k => v in p.phiDeltas) k => v] : null
		};
	}
}
