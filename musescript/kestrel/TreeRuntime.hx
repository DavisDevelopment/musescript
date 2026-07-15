package musescript.kestrel;

import musescript.kestrel.TreeModel.TreeNode;
import musescript.kestrel.TreeModel.TreePrediction;

/** Runtime traversal helpers for distilled tree models. */
class TreeRuntime {
	public static function predict(model:TreeModel, row:Array<Float>):TreePrediction {
		var path:Array<Int> = [];
		var node = model.root;
		while (true) {
			switch (node) {
				case TLeaf(value, coeffs):
					var out = value;
					if (coeffs != null) {
						var n = Std.int(Math.min(coeffs.length, row.length));
						for (i in 0...n) out += coeffs[i] * row[i];
					}
					return { value: out, path: path };
				case TSplit(feature, threshold, left, right):
					var v = feature >= 0 && feature < row.length ? row[feature] : 0.0;
					if (v < threshold) {
						path.push(1);
						node = left;
					} else {
						path.push(0);
						node = right;
					}
			}
		}
	}

	public static function size(node:TreeNode):Int {
		return switch (node) {
			case TLeaf(_, _): 1;
			case TSplit(_, _, l, r): 1 + size(l) + size(r);
		};
	}

	public static function toJson(model:TreeModel):Dynamic {
		return {
			schema: "musescript.kestrel.tree/1",
			id: model.id,
			task: switch (model.task) {
				case TRegression: "regression";
				case TClassification: "classification";
			},
			featureNames: model.featureNames,
			score: model.score,
			root: nodeToJson(model.root)
		};
	}

	static function nodeToJson(node:TreeNode):Dynamic {
		return switch (node) {
			case TLeaf(value, coeffs):
				{ kind: "leaf", value: value, coeffs: coeffs };
			case TSplit(feature, threshold, left, right):
				{
					kind: "split",
					feature: feature,
					threshold: threshold,
					left: nodeToJson(left),
					right: nodeToJson(right)
				};
		};
	}
}
