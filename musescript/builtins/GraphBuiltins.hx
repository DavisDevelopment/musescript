package musescript.builtins;

import musescript.kestrel.GraphQuerySpec;
import musescript.kestrel.GraphQuerySpec.GraphMetricOp;
import musescript.kestrel.GraphQuerySpec.GraphSeed;

/**
 * Dependency-free, in-memory graph operations for JSON-safe MuseScript values.
 *
 * Input shape:
 * `{ directed: Bool, nodes: Array<String>, edges: Array<{from:String, to:String,
 * ?weight:Float, ?relation:String}> }`.
 *
 * Node array order is canonical and controls every deterministic tie break and
 * result order. Edges are directed when `directed` is true and traversable both
 * ways otherwise. Missing weights are 1; all weights must be finite and
 * nonnegative. Parsing rejects duplicate/missing nodes and oversized graphs.
 */
class GraphBuiltins {
	public static inline var MAX_GRAPH_NODES:Int = 4096;
	public static inline var MAX_GRAPH_EDGES:Int = 32768;
	public static inline var MAX_TRAVERSAL_NODES:Int = 4096;
	public static inline var MAX_PAGERANK_ITERATIONS:Int = 1000;
	public static inline var DEFAULT_TRAVERSAL_NODES:Int = 1024;
	public static inline var DEFAULT_MAX_DEPTH:Int = 32;
	public static inline var DEFAULT_PAGERANK_ITERATIONS:Int = 20;

	public static function install(vars:Map<String, Dynamic>):Void {
		vars.set("graph_neighbors", graphNeighbors);
		vars.set("graph_degree", graphDegree);
		vars.set("graph_has_edge", graphHasEdge);
		vars.set("graph_bfs", graphBfs);
		vars.set("graph_reachable", graphReachable);
		vars.set("graph_shortest_path", graphShortestPath);
		vars.set("graph_pagerank", graphPageRank);
	}

	public static function graphNeighbors(
		value:Dynamic,
		node:String,
		?direction:String = "out",
		?maxResults:Int = 256
	):Array<String> {
		var graph = GraphRuntime.fromJson(value);
		var nodeId = graph.requireNode(node);
		var ids = graph.neighborIds(nodeId, direction);
		var limit = checkedLimit("maxResults", maxResults, MAX_TRAVERSAL_NODES, true);
		if (ids.length > limit) ids.resize(limit);
		return [for (id in ids) graph.nodes[id]];
	}

	public static function graphDegree(value:Dynamic, node:String, ?direction:String = "out"):Int {
		var graph = GraphRuntime.fromJson(value);
		var nodeId = graph.requireNode(node);
		return graph.degree(nodeId, direction);
	}

	public static function graphHasEdge(value:Dynamic, from:String, to:String, ?relation:String):Bool {
		var graph = GraphRuntime.fromJson(value);
		var fromId = graph.requireNode(from);
		var toId = graph.requireNode(to);
		for (arc in graph.outgoing[fromId])
			if (arc.to == toId && (relation == null || arc.relation == relation)) return true;
		return false;
	}

	public static function graphBfs(
		value:Dynamic,
		start:String,
		?maxDepth:Int = DEFAULT_MAX_DEPTH,
		?maxNodes:Int = DEFAULT_TRAVERSAL_NODES
	):Array<String> {
		var graph = GraphRuntime.fromJson(value);
		var startId = graph.requireNode(start);
		var depthLimit = checkedLimit("maxDepth", maxDepth, MAX_GRAPH_NODES, true);
		var nodeLimit = checkedLimit("maxNodes", maxNodes, MAX_TRAVERSAL_NODES, false);
		var ids = bfsIds(graph, startId, depthLimit, nodeLimit, null);
		return [for (id in ids) graph.nodes[id]];
	}

	public static function graphReachable(
		value:Dynamic,
		start:String,
		target:String,
		?maxDepth:Int = DEFAULT_MAX_DEPTH,
		?maxNodes:Int = DEFAULT_TRAVERSAL_NODES
	):Bool {
		var graph = GraphRuntime.fromJson(value);
		var startId = graph.requireNode(start);
		var targetId = graph.requireNode(target);
		var depthLimit = checkedLimit("maxDepth", maxDepth, MAX_GRAPH_NODES, true);
		var nodeLimit = checkedLimit("maxNodes", maxNodes, MAX_TRAVERSAL_NODES, false);
		var found = false;
		bfsIds(graph, startId, depthLimit, nodeLimit, function(id) {
			if (id == targetId) found = true;
			return found;
		});
		return found;
	}

	/**
	 * Returns `{nodes:Array<String>, distance:Float}` or null when no bounded path exists.
	 * `weighted=false` counts edges; `weighted=true` uses nonnegative edge weights.
	 */
	public static function graphShortestPath(
		value:Dynamic,
		start:String,
		target:String,
		?weighted:Bool = false,
		?maxNodes:Int = DEFAULT_TRAVERSAL_NODES
	):Dynamic {
		var graph = GraphRuntime.fromJson(value);
		var startId = graph.requireNode(start);
		var targetId = graph.requireNode(target);
		var nodeLimit = checkedLimit("maxNodes", maxNodes, MAX_TRAVERSAL_NODES, false);
		var n = graph.nodes.length;
		var dist = [for (_ in 0...n) Math.POSITIVE_INFINITY];
		var prev = [for (_ in 0...n) -1];
		var done = [for (_ in 0...n) false];
		dist[startId] = 0;
		var visited = 0;
		while (visited < nodeLimit) {
			var best = -1;
			for (i in 0...n)
				if (!done[i] && Math.isFinite(dist[i])
					&& (best < 0 || dist[i] < dist[best] || (dist[i] == dist[best] && i < best)))
					best = i;
			if (best < 0) break;
			done[best] = true;
			visited++;
			if (best == targetId) break;
			for (arc in graph.outgoing[best]) {
				if (done[arc.to]) continue;
				var candidate = dist[best] + (weighted ? arc.weight : 1.0);
				if (candidate < dist[arc.to]
					|| (candidate == dist[arc.to] && (prev[arc.to] < 0 || best < prev[arc.to]))) {
					dist[arc.to] = candidate;
					prev[arc.to] = best;
				}
			}
		}
		if (!done[targetId]) return null;
		var reversed:Array<String> = [];
		var at = targetId;
		while (at >= 0) {
			reversed.push(graph.nodes[at]);
			if (at == startId) break;
			at = prev[at];
		}
		if (at != startId) return null;
		reversed.reverse();
		return {nodes: reversed, distance: dist[targetId]};
	}

	/**
	 * Bounded weighted PageRank. Results remain in canonical node order.
	 * Zero-total-weight nodes are treated as dangling nodes.
	 */
	public static function graphPageRank(
		value:Dynamic,
		?iterations:Int = DEFAULT_PAGERANK_ITERATIONS,
		?damping:Float = 0.85,
		?maxNodes:Int = DEFAULT_TRAVERSAL_NODES
	):Array<Dynamic> {
		var graph = GraphRuntime.fromJson(value);
		var iterationCount = checkedLimit("iterations", iterations, MAX_PAGERANK_ITERATIONS, false);
		var nodeLimit = checkedLimit("maxNodes", maxNodes, MAX_TRAVERSAL_NODES, false);
		if (graph.nodes.length > nodeLimit)
			throw 'graph_pagerank: graph has ${graph.nodes.length} nodes, above maxNodes $nodeLimit';
		if (!Math.isFinite(damping) || damping < 0 || damping > 1)
			throw "graph_pagerank: damping must be finite and in [0, 1]";
		var n = graph.nodes.length;
		if (n == 0) return [];
		var rank = [for (_ in 0...n) 1.0 / n];
		for (_ in 0...iterationCount) {
			var dangling = 0.0;
			var next = [for (_ in 0...n) (1.0 - damping) / n];
			for (i in 0...n) {
				var totalWeight = 0.0;
				for (arc in graph.outgoing[i]) totalWeight += arc.weight;
				if (totalWeight == 0) {
					dangling += rank[i];
				} else {
					for (arc in graph.outgoing[i])
						if (arc.weight > 0) next[arc.to] += damping * rank[i] * arc.weight / totalWeight;
				}
			}
			var share = damping * dangling / n;
			for (i in 0...n) next[i] += share;
			rank = next;
		}
		return [for (i in 0...n) {node: graph.nodes[i], score: rank[i]}];
	}

	/**
	 * Converts existing Kestrel GraphQuerySpec bounds/seed into runtime options.
	 * It intentionally performs no external KG lookup or live query execution.
	 */
	public static function querySpecOptions(spec:GraphQuerySpec):GraphQueryRuntimeOptions {
		if (spec == null) throw "graph query spec is required";
		var maxNodes = spec.maxNodes == null ? DEFAULT_TRAVERSAL_NODES
			: checkedLimit("GraphQuerySpec.maxNodes", spec.maxNodes, MAX_TRAVERSAL_NODES, false);
		var depth = spec.depth == null ? DEFAULT_MAX_DEPTH
			: checkedLimit("GraphQuerySpec.depth", spec.depth, MAX_GRAPH_NODES, true);
		var topK = spec.topK == null ? maxNodes
			: checkedLimit("GraphQuerySpec.topK", spec.topK, maxNodes, false);
		var pageRankIterations = DEFAULT_PAGERANK_ITERATIONS;
		for (metric in spec.metrics) switch (metric.op) {
			case GPageRankApprox(n):
				pageRankIterations = checkedLimit(
					"GraphQuerySpec PageRank iterations",
					n,
					MAX_PAGERANK_ITERATIONS,
					false
				);
			default:
		}
		return {
			seedNode: seedNode(spec.seed),
			relations: spec.relations == null ? [] : spec.relations.copy(),
			maxDepth: depth,
			maxNodes: maxNodes,
			topK: topK,
			pageRankIterations: pageRankIterations
		};
	}

	static function seedNode(seed:GraphSeed):String {
		return switch (seed) {
			case GSymbol(value) | GEntity(value) | GFeature(value): value;
			case GQuestion(value): value;
		};
	}

	static function bfsIds(
		graph:GraphRuntime,
		startId:Int,
		maxDepth:Int,
		maxNodes:Int,
		?stop:Int->Bool
	):Array<Int> {
		var seen = [for (_ in 0...graph.nodes.length) false];
		var queue:Array<{id:Int, depth:Int}> = [{id: startId, depth: 0}];
		var out:Array<Int> = [];
		seen[startId] = true;
		var cursor = 0;
		while (cursor < queue.length && out.length < maxNodes) {
			var item = queue[cursor++];
			out.push(item.id);
			if (stop != null && stop(item.id)) break;
			if (item.depth >= maxDepth) continue;
			for (next in graph.neighborIds(item.id, "out")) {
				if (seen[next]) continue;
				seen[next] = true;
				queue.push({id: next, depth: item.depth + 1});
			}
		}
		return out;
	}

	static function checkedLimit(name:String, value:Int, hardMax:Int, allowZero:Bool):Int {
		if ((allowZero ? value < 0 : value <= 0) || value > hardMax)
			throw '$name must be ${allowZero ? "between 0 and" : "between 1 and"} $hardMax';
		return value;
	}
}

typedef GraphQueryRuntimeOptions = {
	var seedNode:String;
	var relations:Array<String>;
	var maxDepth:Int;
	var maxNodes:Int;
	var topK:Int;
	var pageRankIterations:Int;
}

private typedef GraphArc = {
	var to:Int;
	var weight:Float;
	var relation:Null<String>;
}

private class GraphRuntime {
	public var directed(default, null):Bool;
	public var nodes(default, null):Array<String>;
	public var outgoing(default, null):Array<Array<GraphArc>>;
	public var incoming(default, null):Array<Array<GraphArc>>;
	var ids:Map<String, Int>;

	function new(directed:Bool, nodes:Array<String>) {
		this.directed = directed;
		this.nodes = nodes;
		this.ids = new Map();
		this.outgoing = [for (_ in nodes) []];
		this.incoming = [for (_ in nodes) []];
		for (i in 0...nodes.length) ids.set(nodes[i], i);
	}

	public static function fromJson(value:Dynamic):GraphRuntime {
		if (value == null || Std.isOfType(value, Array) || !Reflect.isObject(value))
			throw "graph must be an object";
		if (!Reflect.hasField(value, "nodes") || !Std.isOfType(Reflect.field(value, "nodes"), Array))
			throw "graph.nodes must be an array of unique strings";
		if (!Reflect.hasField(value, "edges") || !Std.isOfType(Reflect.field(value, "edges"), Array))
			throw "graph.edges must be an array";
		var rawNodes:Array<Dynamic> = cast Reflect.field(value, "nodes");
		var rawEdges:Array<Dynamic> = cast Reflect.field(value, "edges");
		if (rawNodes.length > GraphBuiltins.MAX_GRAPH_NODES)
			throw 'graph.nodes exceeds ${GraphBuiltins.MAX_GRAPH_NODES}';
		if (rawEdges.length > GraphBuiltins.MAX_GRAPH_EDGES)
			throw 'graph.edges exceeds ${GraphBuiltins.MAX_GRAPH_EDGES}';
		var nodes:Array<String> = [];
		var seen:Map<String, Bool> = new Map();
		for (raw in rawNodes) {
			if (!Std.isOfType(raw, String) || (cast raw : String).length == 0)
				throw "graph node ids must be non-empty strings";
			var node:String = cast raw;
			if (seen.exists(node)) throw 'duplicate graph node "$node"';
			seen.set(node, true);
			nodes.push(node);
		}
		var directed = false;
		if (Reflect.hasField(value, "directed")) {
			var rawDirected = Reflect.field(value, "directed");
			if (!Std.isOfType(rawDirected, Bool)) throw "graph.directed must be boolean";
			directed = rawDirected;
		}
		var graph = new GraphRuntime(directed, nodes);
		for (raw in rawEdges) graph.addJsonEdge(raw);
		return graph;
	}

	public function requireNode(node:String):Int {
		if (node == null || !ids.exists(node)) throw 'unknown graph node "$node"';
		return ids.get(node);
	}

	public function neighborIds(nodeId:Int, direction:String):Array<Int> {
		if (direction != "out" && direction != "in" && direction != "both")
			throw 'graph direction must be "out", "in", or "both"';
		var present = [for (_ in nodes) false];
		if (direction == "out" || direction == "both")
			for (arc in outgoing[nodeId]) present[arc.to] = true;
		if (direction == "in" || direction == "both")
			for (arc in incoming[nodeId]) present[arc.to] = true;
		return [for (i in 0...nodes.length) if (present[i]) i];
	}

	public function degree(nodeId:Int, direction:String):Int {
		if (direction == "out") return outgoing[nodeId].length;
		if (direction == "in") return incoming[nodeId].length;
		if (direction == "both") {
			if (!directed) return outgoing[nodeId].length;
			return outgoing[nodeId].length + incoming[nodeId].length;
		}
		throw 'graph direction must be "out", "in", or "both"';
	}

	function addJsonEdge(raw:Dynamic):Void {
		if (raw == null || Std.isOfType(raw, Array) || !Reflect.isObject(raw))
			throw "each graph edge must be an object";
		var from = stringField(raw, "from");
		var to = stringField(raw, "to");
		var fromId = requireNode(from);
		var toId = requireNode(to);
		var weight = 1.0;
		if (Reflect.hasField(raw, "weight")) {
			var rawWeight:Dynamic = Reflect.field(raw, "weight");
			if (!Std.isOfType(rawWeight, Int) && !Std.isOfType(rawWeight, Float))
				throw "graph edge weight must be numeric";
			weight = rawWeight;
		}
		if (!Math.isFinite(weight) || weight < 0)
			throw "graph edge weight must be finite and nonnegative";
		var relation:Null<String> = null;
		if (Reflect.hasField(raw, "relation") && Reflect.field(raw, "relation") != null) {
			if (!Std.isOfType(Reflect.field(raw, "relation"), String))
				throw "graph edge relation must be a string";
			relation = Reflect.field(raw, "relation");
		}
		addArc(fromId, toId, weight, relation);
		if (!directed && fromId != toId) addArc(toId, fromId, weight, relation);
	}

	function addArc(from:Int, to:Int, weight:Float, relation:Null<String>):Void {
		outgoing[from].push({to: to, weight: weight, relation: relation});
		incoming[to].push({to: from, weight: weight, relation: relation});
	}

	static function stringField(value:Dynamic, name:String):String {
		var fieldName = name;
		// Haxe's Python target escapes the reserved anonymous-object field `from`.
		// Decoded JSON still uses `from`, while Haxe-authored values use `_hx_from`.
		if (name == "from" && !Reflect.hasField(value, name) && Reflect.hasField(value, "_hx_from"))
			fieldName = "_hx_from";
		if (!Reflect.hasField(value, fieldName) || !Std.isOfType(Reflect.field(value, fieldName), String))
			throw 'graph edge $name must be a string';
		return Reflect.field(value, fieldName);
	}
}
