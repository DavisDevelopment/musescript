{
			@strategy("graph_dynamic")
			@on(bar) {
				var graph = { directed: true, nodes: ["A"], edges: [] };
				var degree = graph_degree(graph, "A");
				if (degree == 0) long();
			}
		}