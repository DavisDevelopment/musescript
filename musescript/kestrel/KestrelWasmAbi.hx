package musescript.kestrel;

/**
 * Draft ABI for Kestrel features/model heads inside strategy WASM.
 *
 * v0 keeps graph/model work out of the hot per-bar path:
 * - graph queries are resolved before a backtest into scalar feature tapes
 * - model/tree outputs are either precomputed feature tapes or compact tables
 * - strategies read by feature id from shared linear memory
 */
class KestrelWasmAbi {
	public static inline var VERSION = 1;

	/** Feature tapes are packed after OHLCV: feature-major f64[nFeatures][nBars]. */
	public static inline var FEATURE_TAPE_KIND = "feature_tape_f64_v1";

	/** Optional tree table section: breadth-first nodes, numeric thresholds. */
	public static inline var TREE_TABLE_KIND = "tree_table_v1";

	/** Host import names reserved for non-hot-path fallbacks/debugging. */
	public static inline var IMPORT_GET_FEATURE = "get_feature";
	public static inline var IMPORT_GRAPH_METRIC = "graph_metric";
	public static inline var IMPORT_MODEL_SCORE = "model_score";

	public static function importNames():Array<String> {
		return [IMPORT_GET_FEATURE, IMPORT_GRAPH_METRIC, IMPORT_MODEL_SCORE];
	}

	public static function manifestSection(manifest:ModelManifest):Dynamic {
		return {
			abi: "musescript.kestrel.wasm/1",
			version: VERSION,
			featureTapeKind: FEATURE_TAPE_KIND,
			treeTableKind: TREE_TABLE_KIND,
			featureNames: [for (f in manifest.features) f.name],
			treeIds: [for (t in manifest.trees) t.id],
			graphQueryIds: [for (q in manifest.graphQueries) q.id]
		};
	}
}
