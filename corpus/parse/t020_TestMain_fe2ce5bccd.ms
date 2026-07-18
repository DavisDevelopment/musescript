
			strategy kestrel_dense {
				indicator ordinary = externalParam;
				feature graphSignal = graph_metric("supply", "degree");
				onBar {
					when treeSignal > ordinary: long();
				}
				feature treeSignal = tree_value("logic");
				onBar {
					when graphSignal < -1: flat();
				}
			}
		