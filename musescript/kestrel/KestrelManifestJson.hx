package musescript.kestrel;

import musescript.kestrel.ModelManifest.ModelHead;

/** JSON-safe serialization for Haxe-authored Kestrel manifests. */
class KestrelManifestJson {
	public static function toDynamic(m:ModelManifest):Dynamic {
		return {
			schema: "musescript.kestrel.manifest/1",
			id: m.id,
			format: m.format,
			channels: m.channels,
			features: [for (f in m.features) featureBinding(f)],
			heads: [for (h in m.heads) head(h)],
			trees: [for (t in m.trees) TreeRuntime.toJson(t)],
			graphQueries: [for (q in m.graphQueries) graph(q)],
			wasmAbi: KestrelWasmAbi.manifestSection(m),
			metadata: m.metadata
		};
	}

	public static function stringify(m:ModelManifest, ?pretty:Bool = true):String {
		return haxe.Json.stringify(toDynamic(m), null, pretty ? "  " : null);
	}

	static function featureBinding(f:FeatureBinding):Dynamic {
		return {
			name: f.name,
			role: f.role != null ? Std.string(f.role) : "FDerived",
			expr: KestrelExpand.feature(f.expr),
			description: f.description
		};
	}

	static function graph(q:GraphQuerySpec):Dynamic {
		return {
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

	static function head(h:ModelHead):Dynamic {
		return switch (h) {
			case HZero(id, latentDim):
				{ kind: "zero", id: id, latentDim: latentDim };
			case HLinear(id, weights, bias):
				{ kind: "linear", id: id, weights: weights, bias: bias };
			case HMlp(id, w1, b1, w2, b2):
				{ kind: "mlp", id: id, w1: w1, b1: b1, w2: w2, b2: b2 };
			case HGbdt(id, baseline, trees):
				{ kind: "gbdt", id: id, baseline: baseline, trees: trees };
			case HBagged(id, heads):
				{ kind: "bagged", id: id, heads: [for (x in heads) head(x)] };
		};
	}
}
