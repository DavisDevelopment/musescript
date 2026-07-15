package musescript.kestrel;

import musescript.plan.ExecutionPlan;
import musescript.plan.MuseIR;
import musescript.kestrel.ModelManifest.ModelHead;

/**
 * Lowers Kestrel pipeline specs into the existing Muse plan tier.
 *
 * This keeps the first implementation compatible with PlanRunner's generic
 * FeatureSearch/Train/Distill steps while preserving Kestrel metadata in the
 * dynamic payloads.
 */
class KestrelPlanBuilder {
	public static function plan(spec:PipelineSpec):ExecutionPlan {
		var out = MuseIR.empty(spec.id);
		var i = 0;
		for (stage in spec.stages) {
			switch (stage) {
				case SFeatures(bindings):
					out.steps.push(FeatureSearchStep(
						id(spec.id, "features", i++),
						[for (b in bindings) featurePayload(b)],
						"kestrel"
					));
				case SGraph(queries):
					out.steps.push(FeatureSearchStep(
						id(spec.id, "graph", i++),
						[for (q in queries) graphPayload(q)],
						"kestrel.graph"
					));
				case SModel(heads):
					out.steps.push(TrainStep(
						id(spec.id, "model", i++),
						"KestrelModelHead",
						[for (h in heads) headPayload(h)],
						heads.length
					));
				case SDistill(sourceModel, targetTree, maxDepth):
					out.steps.push(DistillStep(
						id(spec.id, "distill", i++),
						sourceModel,
						targetTree,
						['maxDepth=$maxDepth']
					));
				case SEvolve(population, generations):
					out.steps.push(OptimizeStep(
						id(spec.id, "evolve", i++),
						"sharpe",
						['population=$population', 'generations=$generations'],
						"memetic"
					));
				case SExport(path):
					out.steps.push(FeatureSearchStep(
						id(spec.id, "export", i++),
						[{ kind: "KestrelExport", path: path, manifest: spec.manifest.id }],
						"kestrel.export"
					));
			}
		}
		return out;
	}

	static function featurePayload(b:FeatureBinding):Dynamic {
		return {
			kind: "KestrelFeature",
			name: b.name,
			role: b.role != null ? Std.string(b.role) : "FDerived",
			expr: KestrelExpand.feature(b.expr),
			description: b.description
		};
	}

	static function graphPayload(q:GraphQuerySpec):Dynamic {
		return {
			kind: "KestrelGraphQuery",
			id: q.id,
			seed: Std.string(q.seed),
			relations: q.relations,
			depth: q.depth,
			topK: q.topK,
			maxNodes: q.maxNodes,
			asOf: q.asOf,
			metrics: [for (m in q.metrics) { name: m.name, op: Std.string(m.op) }]
		};
	}

	static function headPayload(h:ModelHead):Dynamic {
		return switch (h) {
			case HZero(id, latentDim): { kind: "zero", id: id, latentDim: latentDim };
			case HLinear(id, weights, bias): { kind: "linear", id: id, weights: weights, bias: bias };
			case HMlp(id, w1, b1, w2, b2): { kind: "mlp", id: id, w1: w1, b1: b1, w2: w2, b2: b2 };
			case HGbdt(id, baseline, trees): { kind: "gbdt", id: id, baseline: baseline, trees: trees };
			case HBagged(id, heads): { kind: "bagged", id: id, heads: [for (x in heads) headPayload(x)] };
		};
	}

	static function id(root:String, kind:String, i:Int):String {
		return '${root}_${kind}_$i';
	}
}
