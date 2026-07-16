package musescript.tests;

import musescript.builtins.GraphBuiltins;
import musescript.builtins.TradeBuiltins;
import musescript.compile.JsBackend;
import musescript.harness.HarnessContext;
import musescript.kestrel.GraphQuerySpec;
import musescript.kestrel.GraphQuerySpec.GraphMetricOp;
import musescript.kestrel.GraphQuerySpec.GraphSeed;
import musescript.parse.MuseParser;
import utest.Assert;
import utest.Test;

class TestGraphBuiltins extends Test {
	static function directedGraph():Dynamic {
		return {
			directed: true,
			// Canonical order intentionally differs from edge insertion order.
			nodes: ["A", "B", "C", "D", "E"],
			edges: [
				{from: "A", to: "C", weight: 5.0, relation: "slow"},
				{from: "A", to: "B", weight: 1.0, relation: "fast"},
				{from: "B", to: "D", weight: 1.0},
				{from: "C", to: "D", weight: 1.0},
				{from: "D", to: "E", weight: 2.0}
			]
		};
	}

	public function testNeighborsDegreesAndEdgesAreDeterministic() {
		var graph = directedGraph();
		Assert.same(["B", "C"], GraphBuiltins.graphNeighbors(graph, "A"));
		Assert.same(["A"], GraphBuiltins.graphNeighbors(graph, "B", "in"));
		Assert.equals(2, GraphBuiltins.graphDegree(graph, "A"));
		Assert.equals(2, GraphBuiltins.graphDegree(graph, "D", "in"));
		Assert.isTrue(GraphBuiltins.graphHasEdge(graph, "A", "B"));
		Assert.isTrue(GraphBuiltins.graphHasEdge(graph, "A", "B", "fast"));
		Assert.isFalse(GraphBuiltins.graphHasEdge(graph, "A", "B", "slow"));
	}

	public function testUndirectedSemantics() {
		var graph:Dynamic = {
			directed: false,
			nodes: ["A", "B", "C"],
			edges: [
				{from: "B", to: "C"},
				{from: "A", to: "B"}
			]
		};
		Assert.same(["A", "C"], GraphBuiltins.graphNeighbors(graph, "B"));
		Assert.isTrue(GraphBuiltins.graphHasEdge(graph, "B", "A"));
		Assert.equals(2, GraphBuiltins.graphDegree(graph, "B"));
	}

	public function testBoundedBfsAndReachability() {
		var graph = directedGraph();
		Assert.same(["A", "B", "C", "D", "E"], GraphBuiltins.graphBfs(graph, "A", 3, 5));
		Assert.same(["A", "B", "C"], GraphBuiltins.graphBfs(graph, "A", 10, 3));
		Assert.isFalse(GraphBuiltins.graphReachable(graph, "A", "E", 2, 5));
		Assert.isTrue(GraphBuiltins.graphReachable(graph, "A", "E", 3, 5));
		Assert.isFalse(GraphBuiltins.graphReachable(graph, "C", "B", 10, 5));
	}

	public function testShortestPathsAndTieBreaks() {
		var graph = directedGraph();
		var unweighted:Dynamic = GraphBuiltins.graphShortestPath(graph, "A", "D");
		Assert.same(["A", "B", "D"], unweighted.nodes);
		Assert.equals(2.0, unweighted.distance);

		var weighted:Dynamic = GraphBuiltins.graphShortestPath(graph, "A", "D", true);
		Assert.same(["A", "B", "D"], weighted.nodes);
		Assert.equals(2.0, weighted.distance);
		Assert.isNull(GraphBuiltins.graphShortestPath(graph, "E", "A"));
	}

	public function testPageRankIsStableAndNormalized() {
		var ranks = GraphBuiltins.graphPageRank(directedGraph(), 30, 0.85, 5);
		Assert.equals(5, ranks.length);
		Assert.equals("A", Reflect.field(ranks[0], "node"));
		Assert.equals("E", Reflect.field(ranks[4], "node"));
		var sum = 0.0;
		for (rank in ranks) sum += Reflect.field(rank, "score");
		Assert.isTrue(Math.abs(sum - 1.0) < 1e-9);
		Assert.isTrue(Reflect.field(ranks[4], "score") > Reflect.field(ranks[0], "score"));
		var again = GraphBuiltins.graphPageRank(directedGraph(), 30, 0.85, 5);
		for (i in 0...ranks.length)
			Assert.equals(Reflect.field(ranks[i], "score"), Reflect.field(again[i], "score"));
	}

	public function testMalformedGraphsAndLimitsAreRejected() {
		assertThrows(function() GraphBuiltins.graphBfs({
			directed: true,
			nodes: ["A", "A"],
			edges: []
		}, "A"));
		assertThrows(function() GraphBuiltins.graphDegree({
			directed: true,
			nodes: ["A", "B"],
			edges: [{from: "A", to: "B", weight: -1}]
		}, "A"));
		assertThrows(function() GraphBuiltins.graphBfs(directedGraph(), "missing"));
		assertThrows(function() GraphBuiltins.graphBfs(directedGraph(), "A", 1, 0));
		assertThrows(function() GraphBuiltins.graphPageRank(directedGraph(), 1001));
		assertThrows(function() GraphBuiltins.graphPageRank(directedGraph(), 2, 1.5));
	}

	public function testGraphQuerySpecAdapterUsesExistingGrammar() {
		var spec:GraphQuerySpec = {
			id: "supply",
			seed: GSymbol("A"),
			depth: 2,
			topK: 3,
			maxNodes: 4,
			relations: ["supplies"],
			metrics: [{name: "rank", op: GPageRankApprox(7)}]
		};
		var options = GraphBuiltins.querySpecOptions(spec);
		Assert.equals("A", options.seedNode);
		Assert.same(["supplies"], options.relations);
		Assert.equals(2, options.maxDepth);
		Assert.equals(4, options.maxNodes);
		Assert.equals(3, options.topK);
		Assert.equals(7, options.pageRankIterations);
	}

	public function testInterpreterGlobalsAndJsDispatch() {
		var vars:Map<String, Dynamic> = new Map();
		TradeBuiltins.install(vars, new HarnessContext());
		Assert.notNull(vars.get("graph_bfs"));
		Assert.same(["A", "B", "C"], vars.get("graph_bfs")(directedGraph(), "A", 1, 5));

		var api:Dynamic = JsBackend.createApi(new HarnessContext());
		var path:Dynamic = api.invoke("graph_shortest_path", ([
			directedGraph(), "A", "E", true, 5
		] : Array<Dynamic>));
		Assert.same(["A", "B", "D", "E"], path.nodes);
		Assert.equals(4.0, path.distance);
	}

	public function testStrategyWasmExplicitlyFallsBackForGraphObjects() {
		var prog = new MuseParser().parse('{
			@strategy("graph_dynamic")
			@on(bar) {
				var graph = { directed: true, nodes: ["A"], edges: [] };
				var degree = graph_degree(graph, "A");
				if (degree == 0) long();
			}
		}');
		Assert.isNull(musescript.compile.StrategyWasmBackend.emitWat(prog));
	}

	static function assertThrows(fn:Void->Void):Void {
		var threw = false;
		try {
			fn();
		} catch (_:Dynamic) {
			threw = true;
		}
		Assert.isTrue(threw);
	}
}
