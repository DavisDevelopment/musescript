{
			@strategy("GraphTyped")
			@on(bar) {
				var graph = { directed: true, nodes: ["A", "B"], edges: [{from: "A", to: "B"}] };
				var path = graph_shortest_path(graph, "A", "B");
				if (graph_has_edge(graph, "A", "B") && str_len(graph_bfs(graph, "A")[0]) > 0 && path.distance >= 0) long();
			}
		}