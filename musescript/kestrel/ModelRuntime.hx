package musescript.kestrel;

import musescript.kestrel.ModelManifest.GbdtTree;
import musescript.kestrel.ModelManifest.ModelHead;

/** Dependency-free inference for Kestrel model heads. */
class ModelRuntime {
	public static function score(head:ModelHead, x:Array<Float>):Float {
		return switch (head) {
			case HZero(_, _):
				0.0;
			case HLinear(_, weights, bias):
				dot(weights, x) + bias;
			case HMlp(_, w1, b1, w2, b2):
				var hidden:Array<Float> = [];
				for (i in 0...w1.length) {
					var b = i < b1.length ? b1[i] : 0.0;
					hidden.push(tanh(dot(w1[i], x) + b));
				}
				dot(w2, hidden) + b2;
			case HGbdt(_, baseline, trees):
				var out = baseline;
				for (t in trees) out += evalTree(t, x);
				out;
			case HBagged(_, heads):
				if (heads.length == 0) return 0.0;
				var out = 0.0;
				for (h in heads) out += score(h, x);
				out / heads.length;
		};
	}

	public static function scoreById(heads:Array<ModelHead>, id:String, x:Array<Float>):Float {
		for (h in heads) {
			if (headId(h) == id) return score(h, x);
		}
		return 0.0;
	}

	public static function headId(head:ModelHead):String {
		return switch (head) {
			case HZero(id, _)
				| HLinear(id, _, _)
				| HMlp(id, _, _, _, _)
				| HGbdt(id, _, _)
				| HBagged(id, _):
				id;
		};
	}

	static function evalTree(t:GbdtTree, x:Array<Float>):Float {
		var i = 0;
		var guard = 0;
		while (i >= 0 && i < t.isLeaf.length && guard++ < t.isLeaf.length + 2) {
			if (t.isLeaf[i] != 0) return i < t.value.length ? t.value[i] : 0.0;
			var f = i < t.feature.length ? t.feature[i] : -1;
			var threshold = i < t.threshold.length ? t.threshold[i] : 0.0;
			var v = f >= 0 && f < x.length ? x[f] : Math.NaN;
			var missingLeft = i < t.missingLeft.length && t.missingLeft[i] != 0;
			var goLeft = Math.isNaN(v) ? missingLeft : v <= threshold;
			i = goLeft
				? (i < t.left.length ? t.left[i] : -1)
				: (i < t.right.length ? t.right[i] : -1);
		}
		return 0.0;
	}

	static function dot(w:Array<Float>, x:Array<Float>):Float {
		var n = Std.int(Math.min(w.length, x.length));
		var out = 0.0;
		for (i in 0...n) out += w[i] * x[i];
		return out;
	}

	static function tanh(x:Float):Float {
		var e = Math.exp(2 * x);
		return (e - 1) / (e + 1);
	}
}
