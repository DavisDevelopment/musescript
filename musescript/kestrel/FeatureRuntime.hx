package musescript.kestrel;

import musescript.kestrel.FeatureExpr.ZScoreScope;

/**
 * Evaluates FeatureExpr against pre-materialized tapes and model outputs.
 *
 * Graph queries and heavy ML are expected to be resolved ahead of the hot path;
 * this evaluator consumes bounded scalar values by id.
 */
class FeatureRuntime {
	public static function eval(expr:FeatureExpr, ctx:FeatureContext, index:Int):Float {
		return switch (expr) {
			case FConst(v):
				v;
			case FField(name):
				field(ctx, name, index);
			case FIndicator(name, src, window):
				indicator(name, src, ctx, index, window);
			case FLookback(src, n):
				index - n < 0 ? Math.NaN : eval(src, ctx, index - n);
			case FArith(op, a, b):
				arith(op, eval(a, ctx, index), eval(b, ctx, index));
			case FZScore(src, scope):
				zscore(src, ctx, index, scope);
			case FModelScore(modelId):
				ctx.modelScores.exists(modelId) ? ctx.modelScores.get(modelId) : 0.0;
			case FTreeValue(treeId):
				ctx.treeValues.exists(treeId) ? ctx.treeValues.get(treeId) : 0.0;
			case FTreeBit(treeId, bit):
				var key = treeId + ":" + bit;
				ctx.treeBits.exists(key) ? ctx.treeBits.get(key) : 0.0;
			case FGraphMetric(queryId, metric):
				var key = queryId + ":" + metric;
				ctx.graphMetrics.exists(key) ? ctx.graphMetrics.get(key) : 0.0;
		};
	}

	static function field(ctx:FeatureContext, name:String, index:Int):Float {
		var tape = ctx.tapes.get(name);
		if (tape == null || index < 0 || index >= tape.length) return Math.NaN;
		return tape[index];
	}

	static function indicator(name:String, src:FeatureExpr, ctx:FeatureContext, index:Int, window:Int):Float {
		if (window <= 0) return Math.NaN;
		return switch (name) {
			case "sma":
				var start = Std.int(Math.max(0, index - window + 1));
				var sum = 0.0;
				var n = 0;
				for (i in start...index + 1) {
					var v = eval(src, ctx, i);
					if (!Math.isNaN(v)) {
						sum += v;
						n++;
					}
				}
				n == 0 ? Math.NaN : sum / n;
			case "change":
				index - window < 0 ? Math.NaN : eval(src, ctx, index) - eval(src, ctx, index - window);
			case "mom" | "roc":
				if (index - window < 0) Math.NaN else {
					var prev = eval(src, ctx, index - window);
					prev == 0 || Math.isNaN(prev) ? Math.NaN : (eval(src, ctx, index) - prev) / prev;
				}
			default:
				// Full indicator parity remains owned by StrategyWasmRuntimeWat.
				Math.NaN;
		};
	}

	static function zscore(src:FeatureExpr, ctx:FeatureContext, index:Int, scope:ZScoreScope):Float {
		return switch (scope) {
			case ZTime(window):
				if (window <= 1) return 0.0;
				var start = Std.int(Math.max(0, index - window + 1));
				var vals:Array<Float> = [];
				for (i in start...index + 1) {
					var v = eval(src, ctx, i);
					if (!Math.isNaN(v)) vals.push(v);
				}
				zOf(eval(src, ctx, index), vals);
			case ZCrossSection | ZGlobal:
				var v = eval(src, ctx, index);
				var vals = ctx.crossSection;
				vals == null || vals.length == 0 ? v : zOf(v, vals);
		};
	}

	static function zOf(v:Float, vals:Array<Float>):Float {
		if (vals.length == 0 || Math.isNaN(v)) return 0.0;
		var mu = 0.0;
		for (x in vals) mu += x;
		mu /= vals.length;
		var var_ = 0.0;
		for (x in vals) {
			var d = x - mu;
			var_ += d * d;
		}
		var sd = Math.sqrt(var_ / vals.length);
		return sd == 0 ? 0.0 : (v - mu) / sd;
	}

	static function arith(op:String, a:Float, b:Float):Float {
		return switch (op) {
			case "+": a + b;
			case "-": a - b;
			case "*": a * b;
			case "/": b == 0 ? Math.NaN : a / b;
			case "min": Math.min(a, b);
			case "max": Math.max(a, b);
			default: Math.NaN;
		};
	}
}

typedef FeatureContext = {
	var tapes:Map<String, Array<Float>>;
	var modelScores:Map<String, Float>;
	var treeValues:Map<String, Float>;
	var treeBits:Map<String, Float>;
	var graphMetrics:Map<String, Float>;
	var ?crossSection:Array<Float>;
}
