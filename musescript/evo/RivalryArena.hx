package musescript.evo;

import musescript.murmuration.MurmurationConfig;
import musescript.murmuration.MurmurationSim;

/**
 * Sparse rivalry arenas: sample a cohort from demes, run Murmuration compete in tick chunks,
 * mid-arena opponent-conditioned retunes (winner fills / niche / MTM rank / optional SymbolSelector),
 * return z-scores + viz events.
 *
 * Never on the NMA real-tape hot path — CorpusEvoRun calls this only every `--arena-every`
 * gens (default 50 under `--rivalry`). GenomeStepper stays arena-only.
 */
class RivalryArena {
	/**
	 * Sample up to `perDemeK` individuals per deme: best + random fill from the island.
	 * Contiguous deme layout matches `EvolutionEngine.stepDemes` / `Archipelago.demeStats`.
	 */
	public static function sampleCohort(
		pop:Array<StrategyGenome>,
		fitness:Array<Float>,
		demeSize:Int,
		perDemeK:Int,
		rng:Rand
	):Array<ArenaMember> {
		var n = pop.length;
		if (n == 0 || perDemeK <= 0) return [];
		var ds = demeSize > 0 && n >= demeSize * 2 ? demeSize : n;
		var nDemes = Archipelago.demeCount(n, ds == n ? 0 : ds);
		var out:Array<ArenaMember> = [];
		var seen = new Map<Int, Bool>();
		for (d in 0...nDemes) {
			var lo = d * (ds == n ? n : ds);
			var hi = ds == n ? n : Std.int(Math.min(n, lo + ds));
			if (hi <= lo) continue;
			var ranked = [for (i in lo...hi) i];
			ranked.sort(function(a, b) {
				var fa = fitness[a], fb = fitness[b];
				if (fa != fb) return fa < fb ? 1 : -1;
				return a - b;
			});
			var take = Std.int(Math.min(perDemeK, ranked.length));
			// Always take the island elite first.
			var picks = [ranked[0]];
			seen.set(ranked[0], true);
			// Fill with random non-elite island members.
			var pool = [for (i in lo...hi) if (!seen.exists(i)) i];
			while (picks.length < take && pool.length > 0) {
				var j = rng.int(pool.length);
				var idx = pool[j];
				pool[j] = pool[pool.length - 1];
				pool.pop();
				picks.push(idx);
				seen.set(idx, true);
			}
			for (idx in picks)
				out.push({popIndex: idx, deme: d, genome: pop[idx]});
		}
		return out;
	}

	/**
	 * Run a chunked Murmuration arena with mid-arena retunes.
	 * `retuneRounds == 0` → score-only (today's compete shape, sparse cadence).
	 * Mutates `members[i].genome` in place when a retune sticks so callers can write back to pop.
	 * When `selectorsByPop` is provided, loser's SymbolSelector is also blended toward the beater.
	 *
	 * `onProgress(round, stepsDone, stepsTotal)` fires at least once per retune chunk and every
	 * `heartbeatSteps` ticks within a chunk (default 100) so `--gui` / console don't look frozen
	 * during long Murmuration runs.
	 */
	public static function run(
		members:Array<ArenaMember>,
		agents:Int,
		steps:Int,
		retuneRounds:Int,
		seed:Int,
		variation:Variation,
		rng:Rand,
		?onProgress:Int->Int->Int->Void,
		?heartbeatSteps:Int = 100,
		?selectorsByPop:Null<Map<Int, SymbolSelector>> = null
	):RivalryArenaResult {
		if (members.length == 0)
			return emptyResult();
		if (members.length > agents)
			throw 'RivalryArena: --arena-agents ($agents) must exceed arena cohort (${members.length})';
		var cfg = MurmurationConfigs.defaults();
		cfg.nAgents = agents;
		cfg.seed = seed;
		var sim = new MurmurationSim(cfg);
		var pop = sim.population();
		var steppers = [for (m in members) new GenomeStepper(m.genome)];
		for (i in 0...members.length) pop.setEvolvedAgent(i, steppers[i].decide);

		var rounds = retuneRounds < 0 ? 0 : retuneRounds;
		var chunks = rounds + 1;
		var chunkSteps = Std.int(Math.max(1, Math.floor(steps / chunks)));
		var remainder = steps - chunkSteps * chunks;
		var responseEvents:Array<RivalryResponseEvent> = [];
		var wealthHist:Array<Float> = [];
		var lastPrice = cfg.startPrice;
		var pulseEvery = heartbeatSteps > 0 ? heartbeatSteps : chunkSteps;
		var stepsDone = 0;

		if (onProgress != null) onProgress(0, 0, steps);

		for (r in 0...chunks) {
			var n = chunkSteps + (r == chunks - 1 ? remainder : 0);
			var left = n;
			while (left > 0) {
				var take = Std.int(Math.min(pulseEvery, left));
				var rows = sim.run(take);
				if (rows.length > 0) lastPrice = rows[rows.length - 1].close;
				left -= take;
				stepsDone += take;
				if (onProgress != null) onProgress(r, stepsDone, steps);
			}
			if (r >= rounds) break;
			// Mid-arena retune: rank by MTM; bottom half respond using opponent features.
			var wealth = [for (i in 0...members.length) pop.markToMarket(i, lastPrice)];
			var order = [for (i in 0...members.length) i];
			order.sort(function(a, b) return wealth[a] < wealth[b] ? 1 : (wealth[a] > wealth[b] ? -1 : 0));
			var feats = extractFeatures(members, steppers, wealth, order, stepsDone, selectorsByPop);
			var nWinners = Std.int(Math.max(1, Math.floor(members.length / 4)));
			var nLosers = Std.int(Math.max(1, Math.floor(members.length / 2)));
			for (li in 0...nLosers) {
				var loserIdx = order[members.length - 1 - li];
				if (steppers[loserIdx].faulted) continue;
				var winnerIdx = pickBeater(order, nWinners, feats[loserIdx], feats, rng);
				var before = members[loserIdx].genome;
				var resp = opponentRespond(before, members[winnerIdx].genome, feats[loserIdx], feats[winnerIdx], variation, rng);
				if (resp.genome == before && resp.kind == "noop") continue;
				members[loserIdx].genome = resp.genome;
				steppers[loserIdx] = new GenomeStepper(resp.genome);
				pop.setEvolvedAgent(loserIdx, steppers[loserIdx].decide);
				if (selectorsByPop != null)
					blendSelectorToward(selectorsByPop, members[loserIdx].popIndex, members[winnerIdx].popIndex, rng);
				responseEvents.push({
					kind: resp.kind,
					loserPop: members[loserIdx].popIndex,
					winnerPop: members[winnerIdx].popIndex,
					round: r
				});
			}
		}

		var wealth = [for (i in 0...members.length) pop.markToMarket(i, lastPrice)];
		for (w in wealth) wealthHist.push(w);
		var mean = 0.0;
		for (w in wealth) mean += w;
		mean /= wealth.length;
		var variance = 0.0;
		for (w in wealth) variance += (w - mean) * (w - mean);
		variance /= wealth.length;
		var std = Math.sqrt(variance);
		var zscores = [for (w in wealth) std > 1e-9 ? (w - mean) / std : 0.0];
		var faulted = 0;
		for (s in steppers) if (s.faulted) faulted++;

		return {
			zByPopIndex: {
				var m = new Map<Int, Float>();
				for (i in 0...members.length) m.set(members[i].popIndex, zscores[i]);
				m;
			},
			wealth: wealthHist,
			faulted: faulted,
			cohort: members.length,
			responseEvents: responseEvents,
			retuneRounds: rounds
		};
	}

	/** Build per-cohort-slot opponent features from steppers + MTM ranks (+ optional selectors). */
	public static function extractFeatures(
		members:Array<ArenaMember>,
		steppers:Array<GenomeStepper>,
		wealth:Array<Float>,
		order:Array<Int>,
		stepsDone:Int,
		?selectorsByPop:Null<Map<Int, SymbolSelector>>
	):Array<OpponentFeatures> {
		var rankOf = new Map<Int, Int>();
		for (r in 0...order.length) rankOf.set(order[r], r);
		var bars = Std.int(Math.max(1, stepsDone));
		var out:Array<OpponentFeatures> = [];
		for (i in 0...members.length) {
			var desc = MapElites.describeFills(steppers[i].fills(), bars);
			var tpb = steppers[i].tradeCount() / bars;
			var niche = MapElites.assignCell(tpb, desc.avgHold, desc.longFrac, desc.dutyCycle);
			var selScore:Null<Float> = null;
			if (selectorsByPop != null) {
				var sel = selectorsByPop.get(members[i].popIndex);
				if (sel != null) {
					// Compact fingerprint of selector preference for distance / pick bias.
					var s = 0.0;
					for (w in sel.weights) s += w;
					selScore = s;
				}
			}
			out.push({
				mtm: wealth[i],
				rank: rankOf.exists(i) ? rankOf.get(i) : i,
				trades: steppers[i].tradeCount(),
				tradesPerBar: tpb,
				avgHold: desc.avgHold,
				longFrac: desc.longFrac,
				dutyCycle: desc.dutyCycle,
				nicheKey: niche,
				selectorScore: selScore
			});
		}
		return out;
	}

	/** Euclidean niche distance on (tradesPerBar, avgHold/50, longFrac, dutyCycle). */
	public static function nicheDistance(a:OpponentFeatures, b:OpponentFeatures):Float {
		var d1 = a.tradesPerBar - b.tradesPerBar;
		var d2 = (a.avgHold - b.avgHold) / 50.0;
		var d3 = a.longFrac - b.longFrac;
		var d4 = a.dutyCycle - b.dutyCycle;
		return Math.sqrt(d1 * d1 + d2 * d2 + d3 * d3 + d4 * d4);
	}

	/**
	 * Roulette among top-`nWinners` MTM ranks, weighted by rank (best heaviest) and boosted when
	 * the beater's niche / selector fingerprint differs from the loser — steal useful diversity.
	 */
	public static function pickBeater(
		order:Array<Int>,
		nWinners:Int,
		loserFeat:OpponentFeatures,
		feats:Array<OpponentFeatures>,
		rng:Rand
	):Int {
		var n = Std.int(Math.min(nWinners, order.length));
		if (n <= 0) return order[0];
		var weights:Array<Float> = [];
		var total = 0.0;
		for (wi in 0...n) {
			var idx = order[wi];
			var w = (n - wi) * 1.0; // rank 0 → n, last winner → 1
			var wf = feats[idx];
			if (wf.nicheKey != loserFeat.nicheKey) w *= 2.0;
			else if (nicheDistance(loserFeat, wf) > 0.12) w *= 1.5;
			if (loserFeat.selectorScore != null && wf.selectorScore != null
				&& Math.abs(loserFeat.selectorScore - wf.selectorScore) > 0.5)
				w *= 1.25;
			weights.push(w);
			total += w;
		}
		if (total <= 0) return order[rng.int(n)];
		var pick = rng.float() * total;
		var acc = 0.0;
		for (wi in 0...n) {
			acc += weights[wi];
			if (pick <= acc) return order[wi];
		}
		return order[n - 1];
	}

	/**
	 * Opponent-conditioned response with teeth:
	 *  - divergent niche / no params → mate-with-beater (steal structure)
	 *  - similar niche + params → param blend toward winner (ES-style local chase)
	 *  - always falls back to mate if nudge is a no-op
	 */
	public static function opponentRespond(
		loser:StrategyGenome,
		winner:StrategyGenome,
		loserFeat:OpponentFeatures,
		winnerFeat:OpponentFeatures,
		variation:Variation,
		rng:Rand
	):{genome:StrategyGenome, kind:String} {
		var dist = nicheDistance(loserFeat, winnerFeat);
		var nichesDiffer = loserFeat.nicheKey != winnerFeat.nicheKey || dist > 0.12;
		var preferMate = nichesDiffer || loser.params.length == 0 || winner.params.length == 0;
		// Stronger beaters (lower rank) pull harder toward structural steal.
		if (winnerFeat.rank == 0 && rng.float() < 0.35) preferMate = true;

		if (preferMate || rng.float() < 0.55) {
			var child = mateWithBeater(loser, winner, variation);
			// After a structural steal, sometimes chase winner params too (visible nudge counter).
			if (child.params.length > 0 && winner.params.length > 0 && rng.float() < 0.45) {
				var nudged = paramBlendToward(child, winner, rng);
				if (nudged != child) return {genome: nudged, kind: "es-nudge"};
			}
			if (child != loser) return {genome: child, kind: "mate"};
			return {genome: loser, kind: "noop"};
		}

		var nudged = paramBlendToward(loser, winner, rng);
		if (nudged != loser) return {genome: nudged, kind: "es-nudge"};
		var child = mateWithBeater(loser, winner, variation);
		if (child != loser) return {genome: child, kind: "mate"};
		return {genome: loser, kind: "noop"};
	}

	/** Cheap oracle-free ES: move one loser param defaultValue toward a winner param's value. */
	public static function paramBlendToward(
		loser:StrategyGenome,
		winner:StrategyGenome,
		rng:Rand
	):StrategyGenome {
		if (loser.params.length == 0 || winner.params.length == 0) return loser;
		var li = rng.int(loser.params.length);
		var wi = rng.int(winner.params.length);
		var lp = loser.params[li];
		var wp = winner.params[wi];
		var range = lp.max - lp.min;
		if (range <= 0) return loser;
		// Blend 30–70% of the way toward winner value, clipped to loser's [min,max].
		var alpha = 0.3 + rng.float() * 0.4;
		var target = lp.defaultValue + alpha * (wp.defaultValue - lp.defaultValue);
		// Also allow a small ES jitter so identical params still move.
		target += (rng.float() * 2 - 1) * range * 0.05;
		var nudged = Math.max(lp.min, Math.min(lp.max, target));
		if (nudged == lp.defaultValue) return loser;
		var newParams = loser.params.copy();
		newParams[li] = {
			name: lp.name, defaultValue: nudged, min: lp.min, max: lp.max, step: lp.step, tune: lp.tune
		};
		return {
			entryLong: loser.entryLong,
			entryShort: loser.entryShort,
			exitLong: loser.exitLong,
			exitShort: loser.exitShort,
			size: loser.size,
			params: newParams,
			name: loser.name,
			lineage: (loser.lineage != null ? loser.lineage.copy() : []).concat([Canonical.structuralKey(loser)]),
			seedOrigin: loser.seedOrigin,
			// Bucket F1: param blends must not drop host projections (drain-bug class).
			projections: loser.projections,
			panelAction: loser.panelAction
		};
	}

	/** Blend loser's SymbolSelector weights toward winner (in-place map update). */
	public static function blendSelectorToward(
		selectorsByPop:Map<Int, SymbolSelector>,
		loserPop:Int,
		winnerPop:Int,
		rng:Rand
	):Void {
		var loser = selectorsByPop.get(loserPop);
		var winner = selectorsByPop.get(winnerPop);
		if (loser == null || winner == null) return;
		if (loser.weights.length != winner.weights.length) return;
		var child = new SymbolSelector(0, rng);
		var alpha = 0.35 + rng.float() * 0.3;
		child.weights = [
			for (i in 0...loser.weights.length)
				loser.weights[i] + alpha * (winner.weights[i] - loser.weights[i])
		];
		selectorsByPop.set(loserPop, child);
	}

	/** Structural mate-with-beater: one blind crossover toward the winner. */
	public static function mateWithBeater(
		loser:StrategyGenome,
		winner:StrategyGenome,
		variation:Variation
	):StrategyGenome {
		return variation.crossover(loser, winner);
	}

	static function emptyResult():RivalryArenaResult {
		return {
			zByPopIndex: new Map(),
			wealth: [],
			faulted: 0,
			cohort: 0,
			responseEvents: [],
			retuneRounds: 0
		};
	}

	/**
	 * Size the Murmuration population for a sparse arena.
	 * Explicit `arenaAgentsArg` wins (bumped to cohort+1 if needed); else auto = cohort + fill,
	 * hard-capped at 128 and never above `competeAgents`. Never silently uses competeAgents=500
	 * as the arena width — that × `--sim-steps` 3000 was the frozen-looking gen-50 cost.
	 */
	public static function resolveAgents(cohortLen:Int, arenaAgentsArg:Int, competeAgents:Int):Int {
		if (cohortLen <= 0) return 1;
		var agents:Int;
		if (arenaAgentsArg > 0) {
			agents = arenaAgentsArg;
		} else {
			// Modest archetype fill (+16), hard-capped — sparse arenas are not full compete.
			agents = Std.int(Math.min(128, cohortLen + 16));
		}
		if (competeAgents > 0 && agents > competeAgents) agents = competeAgents;
		if (agents <= cohortLen) agents = cohortLen + 1;
		return agents;
	}

	/** Scatter arena z-scores into a full-pop rivalry channel (unsampled slots stay NEG_INF). */
	public static function scatterToPop(popSize:Int, zByPop:Map<Int, Float>):Array<Float> {
		var out = [for (_ in 0...popSize) Fitness.NEG_INF];
		for (idx => z in zByPop) if (idx >= 0 && idx < popSize) out[idx] = z;
		return out;
	}

	/**
	 * Carry forward: refresh sampled slots from the latest arena; keep prior rivalry scores
	 * for unsampled slots (decay optional via `decay`, 1 = no decay).
	 */
	public static function mergeChannel(
		prior:Null<Array<Float>>,
		fresh:Array<Float>,
		decay:Float
	):Array<Float> {
		if (prior == null) return fresh;
		var n = Std.int(Math.max(prior.length, fresh.length));
		var out = [for (i in 0...n) Fitness.NEG_INF];
		for (i in 0...n) {
			var p = i < prior.length ? prior[i] : Fitness.NEG_INF;
			var f = i < fresh.length ? fresh[i] : Fitness.NEG_INF;
			if (f != Fitness.NEG_INF) out[i] = f;
			else if (p != Fitness.NEG_INF) out[i] = decay < 1 ? p * decay : p;
		}
		return out;
	}
}

@:structInit
class ArenaMember {
	public var popIndex:Int;
	public var deme:Int;
	public var genome:StrategyGenome;
}

@:structInit
class RivalryResponseEvent {
	public var kind:String;
	public var loserPop:Int;
	public var winnerPop:Int;
	public var round:Int;
}

@:structInit
class RivalryArenaResult {
	public var zByPopIndex:Map<Int, Float>;
	public var wealth:Array<Float>;
	public var faulted:Int;
	public var cohort:Int;
	public var responseEvents:Array<RivalryResponseEvent>;
	public var retuneRounds:Int;
}
