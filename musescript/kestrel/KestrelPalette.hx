package musescript.kestrel;

/** Palette exposed to MuseScript editors/evolution. */
class KestrelPalette {
	public static final BASE_CHANNELS:Array<String> = [
		"open", "high", "low", "close", "volume",
		"ret", "mom", "value_gap", "vol", "imb", "spread",
		"g", "infl", "sentiment", "capital_norm"
	];

	public static final GRAPH_METRICS:Array<String> = [
		"node_count", "edge_count", "weighted_degree", "relation_exists",
		"seed_score", "pagerank"
	];

	public static final MODEL_HEADS:Array<String> = ["linear", "mlp", "gbdt", "bagged", "tree"];

	public static function toJson():Dynamic {
		return {
			schema: "musescript.kestrel.palette/1",
			id: "kestrel.v1",
			channels: BASE_CHANNELS.copy(),
			graphMetrics: GRAPH_METRICS.copy(),
			modelHeads: MODEL_HEADS.copy(),
			tree: {
				maxDepth: 8,
				defaultDepth: 3,
				defaultMinLeaf: 12
			},
			evolution: {
				allowGraph: true,
				allowModels: true,
				allowTreeDistill: true
			}
		};
	}
}
