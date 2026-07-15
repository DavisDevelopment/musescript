package musescript.kestrel;

import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.StrategyGenome;
import musescript.parse.MuseParser;
import musescript.checker.MuseChecker;
import musescript.compile.StrategyWasmEmitter;
import musescript.kestrel.FeatureRuntime.FeatureContext;
import musescript.kestrel.FeatureExpr.FeatureExpr;
import musescript.kestrel.ModelManifest.ModelHead;

/** Small compile-time proof for the Kestrel IR layer. */
class KestrelProof {
	static function main() {
		var x = [
			[0.0, 0.1],
			[0.2, 0.3],
			[1.0, 0.4],
			[1.2, 0.2]
		];
		var y = [0.0, 0.0, 1.0, 1.0];
		var tree = TreeDistiller.fitRegression("demo_tree", x, y, ["ret", "mom"], 2, 1);
		var pred = TreeRuntime.predict(tree, [1.1, 0.25]);
		if (pred.value <= 0.5) throw "KestrelProof: tree prediction too low";
		var linear = HLinear("score", [1.0, 2.0], 0.5);
		var linearScore = ModelRuntime.score(linear, [2.0, 3.0]);
		if (Math.abs(linearScore - 8.5) > 1e-9) throw "KestrelProof: linear head failed";
		var mlp = HMlp("mlp", [[1.0, 0.0]], [0.0], [2.0], 0.0);
		if (ModelRuntime.score(mlp, [1.0, 3.0]) <= 1.5) throw "KestrelProof: mlp head failed";

		var g:KestrelGenome = {
			entryLong: BCmp(">", KFeature("logic"), KConst(0.5)),
			entryShort: BCmp("<", KFeature("logic"), KConst(-0.5)),
			exitLong: BCmp("<", KFeature("logic"), KConst(0.1)),
			exitShort: BCmp(">", KFeature("logic"), KConst(-0.1)),
			size: KConst(1),
			params: [],
			name: "kestrel_demo",
			featureBindings: [
				{ name: "ret_feature", expr: FArith("-", FField("close"), FLookback(FField("close"), 1)), role: FDerived },
				{ name: "graph_pressure", expr: FGraphMetric("supply_chain", "weighted_degree"), role: FGraph },
				{ name: "logic", expr: FTreeValue("demo_tree"), role: FLogic }
			],
			graphQueries: [{
				id: "supply_chain",
				seed: GSymbol("SPY"),
				depth: 2,
				topK: 5,
				maxNodes: 40,
				metrics: [{ name: "weighted_degree", op: GWeightedDegree(null) }]
			}],
			treeModels: [tree]
		};

		var src = KestrelExpand.expand(g);
		var prog = new MuseParser().parse(src, "<kestrel-proof>");
		var diags = new MuseChecker().check(prog);
		for (d in diags) {
			if (StringTools.startsWith(Std.string(d), "error:"))
				throw 'KestrelProof checker failed: $d\n$src';
		}
		var emitted = new StrategyWasmEmitter().emitOnBar(prog);
		if (emitted == null || emitted.wat.indexOf("configure_features") < 0)
			throw "KestrelProof: Kestrel WASM ABI not emitted";
		if (!sys.FileSystem.exists("build/kestrel")) sys.FileSystem.createDirectory("build/kestrel");
		sys.io.File.saveContent("build/kestrel/proof.wat", emitted.wat);
		sys.io.File.saveContent("build/kestrel/proof.strings.json", haxe.Json.stringify(emitted.strings));
		var slots = KestrelWasmArtifact.featureSlots(emitted.strings);
		if (slots.length == 0) throw "KestrelProof: Kestrel feature slots missing";
		var constants = new Map<String, Float>();
		for (s in slots) constants.set(s.key, 1.0);
		var dense = KestrelFeatureTape.fromConstant(emitted.strings, constants, 3);
		if (dense.length < KestrelWasmArtifact.featureCount(emitted.strings))
			throw "KestrelProof: dense feature tape too small";

		var kv = new KestrelVariation(7);
		switch (kv.randomFeatureTerminal()) {
			case KFeature(_):
			default: throw "KestrelProof: expected feature terminal";
		}

		var manifest:ModelManifest = {
			id: "demo_manifest",
			format: "musescript.kestrel/1",
			channels: KestrelPalette.BASE_CHANNELS.copy(),
			features: g.featureBindings,
			heads: [linear, mlp],
			trees: [tree],
			graphQueries: g.graphQueries
		};
		var plan = KestrelPlanBuilder.plan({
			id: "demo_pipeline",
			manifest: manifest,
			search: {
				population: 8,
				generations: 2,
				maxNodes: 64,
				allowGraph: true,
				allowModels: true,
				allowTreeDistill: true
			},
			stages: [
				SFeatures(g.featureBindings),
				SGraph(g.graphQueries),
				SModel(manifest.heads),
				SDistill("score", "demo_tree", 2),
				SEvolve(8, 2),
				SExport("build/kestrel/demo_manifest.json")
			]
		});
		if (plan.steps.length != 6) throw "KestrelProof: unexpected plan length";
		var abi = KestrelWasmAbi.manifestSection(manifest);
		if ((abi.featureNames:Array<String>).length != g.featureBindings.length)
			throw "KestrelProof: ABI feature section mismatch";
		var ctx = featureContext();
		var feat = FArith("+", FIndicator("sma", FField("close"), 2), FGraphMetric("supply_chain", "weighted_degree"));
		var fv = FeatureRuntime.eval(feat, ctx, 2);
		if (Math.abs(fv - 5.5) > 1e-9) throw 'KestrelProof: feature runtime failed ($fv)';
		var manifestJson = KestrelManifestJson.stringify(manifest);
		if (manifestJson.indexOf("musescript.kestrel.manifest/1") < 0)
			throw "KestrelProof: manifest JSON missing schema";
		Sys.println("KESTREL_PROOF_OK");
	}

	static function featureContext():FeatureContext {
		var tapes = new Map<String, Array<Float>>();
		tapes.set("close", [1.0, 2.0, 3.0]);
		var graph = new Map<String, Float>();
		graph.set("supply_chain:weighted_degree", 3.0);
		return {
			tapes: tapes,
			modelScores: new Map(),
			treeValues: new Map(),
			treeBits: new Map(),
			graphMetrics: graph
		};
	}
}
