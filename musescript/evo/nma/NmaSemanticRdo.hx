package musescript.evo.nma;

import musescript.evo.StrategyGenome;
import musescript.evo.BoolNode;
import musescript.evo.Fitness;
import musescript.evo.GenomeFeatures;
import musescript.evo.Canonical;
import musescript.evo.TreeSurgery;
import musescript.evo.TreeSurgery.GPath;
import musescript.evo.TreeSurgery.GStep.StepA;
import musescript.evo.TreeSurgery.GStep.StepB;
import musescript.harness.Bar;
import musescript.evo.nma.NmaBool;
import musescript.indicators.GrowableVec;

/**
 * Semantic backpropagation-style mutation (RDO/LTI cousin): pick a bool site whose `lastSeries`
 * is farthest from a cheap desired-semantics target, then splice the grown candidate whose
 * stamped column is closest — zero extra full-tape fitness oracles for site/replacement choice.
 *
 * «μύσται βακχεύουσι· νοῦς ἔξω φέρεται.»
 */
class NmaSemanticRdo {

	/**
	 * Returns a mutated genome, or null when NMA/columnar path cannot host `g`.
	 * `grow`: `depth -> BoolNode` replacement factory (Variation closes over growBool).
	 *
	 * «λύρα Διονύσου· χορδαὶ σημαίνουσι.»
	 */
	public static function tryMutate(
		g:StrategyGenome,
		grow:Int->BoolNode,
		rng:{function float():Float; function int(n:Int):Int;},
		?maxDepth:Int = 2,
		?candidateCap:Int = 6,
		?horizon:Int = NmaSemantic.DEFAULT_HORIZON
	):Null<StrategyGenome> {
		if (!NmaFitness.columnSwappable(g)) return null;
		var bars = Fitness.nmaTape;
		if (bars == null) return null;
		var built = NmaFitness.prepare(g, bars);
		if (built == null) return null;
		// Stamp lastSeries on every bool via root evals (children memoized in the walk).
		NmaEval.evalBool(built.nma.entryLong, built.ctx);
		NmaEval.evalBool(built.nma.entryShort, built.ctx);
		NmaEval.evalBool(built.nma.exitLong, built.ctx);
		NmaEval.evalBool(built.nma.exitShort, built.ctx);

		var desired = NmaSemantic.desiredLong(bars, horizon, Fitness.nmaCostBps);
		var desiredInv = invert(desired);

		var sites = new Array<{slot:Int, path:GPath, dist:Float, node:NmaBool}>();
		function collect(slot:Int, root:NmaBool) {
			walkSites(root, [], slot, desiredFor(slot, desired, desiredInv), sites);
		}
		collect(0, built.nma.entryLong);
		collect(1, built.nma.entryShort);
		collect(2, built.nma.exitLong);
		collect(3, built.nma.exitShort);
		if (sites.length == 0) return null;

		// Prefer sites farthest from desired (most to gain) — rank-weighted.
		sites.sort((a, b) -> a.dist < b.dist ? 1 : a.dist > b.dist ? -1 : 0);
		var weights:Array<Float> = [for (i in 0...sites.length) (sites.length - i : Float)];
		var site = sites[weightedPick(weights, rng)];
		var target = desiredFor(site.slot, desired, desiredInv);

		var bestRepl:BoolNode = null;
		var bestDist = 2.0;
		var nCand = Std.int(Math.max(1, candidateCap));
		for (_ in 0...nCand) {
			var d = rng.int(maxDepth + 1);
			var cand = grow(d);
			if (GenomeFeatures.boolIsSimCoupled(cand)) continue;
			var nmaCand = NmaBijection.boolFromEnum(cand);
			var saved = NmaSurgery.boolRoot(built.nma, site.slot);
			NmaSurgery.setBoolRoot(built.nma, site.slot, NmaSurgery.replaceBool(saved, site.path, nmaCand));
			// Re-eval root to stamp the new spine (siblings memo-hit).
			var root = NmaSurgery.boolRoot(built.nma, site.slot);
			NmaEval.evalBool(root, built.ctx);
			var at = NmaSurgery.nodeAtBool(root, site.path);
			var dist = (at != null && at.lastSeries != null)
				? NmaSemantic.hammingRate(at.lastSeries, target)
				: 1.0;
			NmaSurgery.setBoolRoot(built.nma, site.slot, saved);
			if (dist < bestDist) {
				bestDist = dist;
				bestRepl = cand;
			}
		}
		if (bestRepl == null) return null;

		// Enum splice via TreeSurgery (same as Variation.withBoolRepl).
		var out = spliceBool(g, site.slot, site.path, bestRepl);
		out.lineage = (g.lineage != null ? g.lineage.copy() : []).concat([Canonical.structuralKey(g)]);
		return out;
	}

	static function desiredFor(slot:Int, desired:GrowableVec<Float>, inv:GrowableVec<Float>):GrowableVec<Float> {
		return slot <= 1 ? desired : inv;
	}

	static function invert(src:GrowableVec<Float>):GrowableVec<Float> {
		var col = new GrowableVec<Float>(src.length);
		for (i in 0...src.length) col.push(src.at(i) >= 0.5 ? 0.0 : 1.0);
		return col;
	}

	static function walkSites(
		n:NmaBool, path:GPath, slot:Int, target:GrowableVec<Float>,
		out:Array<{slot:Int, path:GPath, dist:Float, node:NmaBool}>
	):Void {
		var dist = (n.lastSeries != null) ? NmaSemantic.hammingRate(n.lastSeries, target) : 1.0;
		out.push({slot: slot, path: path.copy(), dist: dist, node: n});
		switch (n.kind) {
			case BAnd:
				var a = (cast n : NmaBAnd);
				walkSites(a.a, path.concat([StepA]), slot, target, out);
				walkSites(a.b, path.concat([StepB]), slot, target, out);
			case BOr:
				var o = (cast n : NmaBOr);
				walkSites(o.a, path.concat([StepA]), slot, target, out);
				walkSites(o.b, path.concat([StepB]), slot, target, out);
			case BNot:
				walkSites((cast n : NmaBNot).a, path.concat([StepA]), slot, target, out);
			case BHole:
				walkSites((cast n : NmaBHole).inner, path.concat([StepA]), slot, target, out);
			default:
		}
	}

	static function spliceBool(g:StrategyGenome, slot:Int, path:GPath, repl:BoolNode):StrategyGenome {
		return switch (slot) {
			case 0: {
				entryLong: TreeSurgery.replaceBoolWithBool(g.entryLong, path, repl),
				entryShort: g.entryShort, exitLong: g.exitLong, exitShort: g.exitShort,
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			case 1: {
				entryLong: g.entryLong,
				entryShort: TreeSurgery.replaceBoolWithBool(g.entryShort, path, repl),
				exitLong: g.exitLong, exitShort: g.exitShort,
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			case 2: {
				entryLong: g.entryLong, entryShort: g.entryShort,
				exitLong: TreeSurgery.replaceBoolWithBool(g.exitLong, path, repl),
				exitShort: g.exitShort,
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
			default: {
				entryLong: g.entryLong, entryShort: g.entryShort, exitLong: g.exitLong,
				exitShort: TreeSurgery.replaceBoolWithBool(g.exitShort, path, repl),
				size: g.size, params: g.params, name: g.name, lineage: g.lineage, seedOrigin: g.seedOrigin
			};
		};
	}

	static function weightedPick(weights:Array<Float>, rng:{function float():Float; function int(n:Int):Int;}):Int {
		var total = 0.0;
		for (w in weights) total += w;
		if (total <= 0) return rng.int(weights.length);
		var r = rng.float() * total;
		var acc = 0.0;
		for (i in 0...weights.length) {
			acc += weights[i];
			if (r <= acc) return i;
		}
		return weights.length - 1;
	}

}
