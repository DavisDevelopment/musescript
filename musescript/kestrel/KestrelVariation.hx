package musescript.kestrel;

import musescript.evo.Rand;
import musescript.evo.StrategyGenome;
import musescript.evo.ScalarNode;

/**
 * Kestrel-specific evo helpers layered over the base MuseGene engine.
 *
 * The base Variation remains pure OHLCV. This helper introduces bounded feature
 * terminals that are safe for graph/model/tree-aware strategies.
 */
class KestrelVariation {
	var rng:Rand;

	public function new(seed:Int) {
		rng = new Rand(seed);
	}

	public function randomFeatureTerminal():ScalarNode {
		return KFeature(rng.pick(KestrelPalette.BASE_CHANNELS));
	}

	public function attachFeatureBinding(g:StrategyGenome, name:String, expr:FeatureExpr):KestrelGenome {
		return {
			entryLong: g.entryLong,
			entryShort: g.entryShort,
			exitLong: g.exitLong,
			exitShort: g.exitShort,
			size: g.size,
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			featureBindings: [{ name: name, expr: expr, role: FDerived }],
			graphQueries: [],
			treeModels: []
		};
	}

	public function graphFeature(queryId:String, metric:String):FeatureBinding {
		return {
			name: '${queryId}_${metric}',
			expr: FGraphMetric(queryId, metric),
			role: FGraph
		};
	}

	public function treeFeature(treeId:String):FeatureBinding {
		return {
			name: '${treeId}_value',
			expr: FTreeValue(treeId),
			role: FLogic
		};
	}
}
