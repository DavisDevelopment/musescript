package musescript.kestrel;

import musescript.kestrel.TreeModel.TreeNode;

/**
 * Deterministic CART-style distiller.
 *
 * This is deliberately simple and fast: pre-sorted threshold candidates, bounded
 * depth, and no dependency on JVM-only libraries. Platform-specific trainers can
 * replace it later (e.g. Tribuo/Smile), while emitting the same TreeModel shape.
 */
class TreeDistiller {
	public static function fitRegression(
		id:String,
		x:Array<Array<Float>>,
		y:Array<Float>,
		featureNames:Array<String>,
		?maxDepth:Int = 3,
		?minLeaf:Int = 12
	):TreeModel {
		if (x.length != y.length) throw "TreeDistiller: x/y length mismatch";
		var idx = [for (i in 0...y.length) i];
		return {
			id: id,
			featureNames: featureNames.copy(),
			task: TRegression,
			root: buildReg(x, y, idx, 0, maxDepth, minLeaf),
			score: null
		};
	}

	static function buildReg(
		x:Array<Array<Float>>,
		y:Array<Float>,
		rows:Array<Int>,
		depth:Int,
		maxDepth:Int,
		minLeaf:Int
	):TreeNode {
		var mean = meanY(y, rows);
		if (depth >= maxDepth || rows.length < minLeaf * 2) return TLeaf(mean, null);

		var bestFeature = -1;
		var bestThreshold = 0.0;
		var bestLoss = Math.POSITIVE_INFINITY;
		var nFeat = rows.length == 0 ? 0 : x[rows[0]].length;

		for (f in 0...nFeat) {
			var vals = rows.copy();
			vals.sort(function(a, b) {
				var da = x[a][f], db = x[b][f];
				return da < db ? -1 : da > db ? 1 : 0;
			});
			var leftSum = 0.0, leftSq = 0.0, leftN = 0;
			var totalSum = 0.0, totalSq = 0.0;
			for (r in vals) {
				totalSum += y[r];
				totalSq += y[r] * y[r];
			}
			for (i in 0...vals.length - 1) {
				var r = vals[i];
				leftSum += y[r];
				leftSq += y[r] * y[r];
				leftN++;
				var rightN = vals.length - leftN;
				if (leftN < minLeaf || rightN < minLeaf) continue;
				var a = x[vals[i]][f], b = x[vals[i + 1]][f];
				if (a == b) continue;
				var rightSum = totalSum - leftSum;
				var rightSq = totalSq - leftSq;
				var loss = sse(leftSq, leftSum, leftN) + sse(rightSq, rightSum, rightN);
				if (loss < bestLoss) {
					bestLoss = loss;
					bestFeature = f;
					bestThreshold = (a + b) * 0.5;
				}
			}
		}

		if (bestFeature < 0) return TLeaf(mean, null);
		var left:Array<Int> = [];
		var right:Array<Int> = [];
		for (r in rows) {
			if (x[r][bestFeature] < bestThreshold) left.push(r) else right.push(r);
		}
		if (left.length < minLeaf || right.length < minLeaf) return TLeaf(mean, null);
		return TSplit(
			bestFeature,
			bestThreshold,
			buildReg(x, y, left, depth + 1, maxDepth, minLeaf),
			buildReg(x, y, right, depth + 1, maxDepth, minLeaf)
		);
	}

	static function meanY(y:Array<Float>, rows:Array<Int>):Float {
		if (rows.length == 0) return 0;
		var s = 0.0;
		for (r in rows) s += y[r];
		return s / rows.length;
	}

	static function sse(sumSq:Float, sum:Float, n:Int):Float {
		return n <= 0 ? 0 : sumSq - (sum * sum / n);
	}
}
