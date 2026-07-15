package musescript.harness;

import musescript.builtins.TradeBuiltins;
import musescript.plan.ExecutionPlan;
import musescript.runtime.SeriesBuffer;

class HarnessContext implements IHarness {
	public var universe:SymbolUniverse;
	public var params:ParamRegistry;
	public var indicators:IndicatorRegistry;
	public var chart:ChartSink;
	public var orders:OrderSim;
	public var engine:BacktestEngine;
	public var currentBar:Null<Bar>;
	/** Array view of each series; same object as SeriesBuffer.data for TradeBuiltins / JsBackend. */
	public var series:Map<String, Array<Float>>;
	var seriesBuffers:Map<String, SeriesBuffer>;
	public var eventStreams:Map<String, EventStream>;
	public var eventLog:EventLog;
	/** Optional bar feed for compiled strategy entry (JS/Python HostABI). */
	public var feed:Null<BarFeed>;

	public function new() {
		universe = new SymbolUniverse();
		params = new ParamRegistry();
		indicators = new IndicatorRegistry();
		chart = new ChartSink();
		orders = new OrderSim();
		engine = new BacktestEngine(orders, chart);
		currentBar = null;
		series = new Map();
		seriesBuffers = new Map();
		eventStreams = new Map();
		eventLog = new EventLog();
		feed = null;
	}

	public function runBacktest(onBar:Bar->Void, feed:BarFeed):BacktestResult {
		return engine.run(feed, function(bar) {
			currentBar = bar;
			pushSeries("open", bar.open);
			pushSeries("high", bar.high);
			pushSeries("low", bar.low);
			pushSeries("close", bar.close);
			pushSeries("volume", bar.volume);
			onBar(bar);
		});
	}

	function getOrCreateBuffer(name:String):SeriesBuffer {
		var buf = seriesBuffers.get(name);
		if (buf == null) {
			buf = new SeriesBuffer(name, 0);
			seriesBuffers.set(name, buf);
			series.set(name, buf.data);
		}
		return buf;
	}

	public function pushSeries(name:String, v:Float):Void {
		getOrCreateBuffer(name).push(v);
	}

	public function seriesLookback(name:String, n:Int):Float {
		var buf = seriesBuffers.get(name);
		if (buf == null) return Math.NaN;
		return buf.get(n);
	}

	/**
	 * Run `f` as-of `n` bars ago by truncating every series to length−n (prefix),
	 * then restoring in-place arrays so SeriesBuffer / TradeBuiltins stay linked.
	 * καλῶ τὸ SMA, καὶ εὐθὺς ζητῶ τὸ [1]· ἄρα τί ἐστι χρόνος εἰ μὴ δείκτης δείκτου;
	 */
	public function withSeriesOffset(n:Int, f:Void->Dynamic):Dynamic {
		if (n <= 0) return f();
		var saved:Map<String, Array<Float>> = new Map();
		for (name => arr in series) {
			if (arr == null) continue;
			saved.set(name, arr.copy());
			var keep = Std.int(Math.max(0, arr.length - n));
			while (arr.length > keep) arr.pop();
		}
		var result:Dynamic = null;
		try {
			result = f();
		} catch (e:Dynamic) {
			restoreSeries(saved);
			throw e;
		}
		restoreSeries(saved);
		return result;
	}

	function restoreSeries(saved:Map<String, Array<Float>>):Void {
		for (name => copy in saved) {
			var arr = series.get(name);
			if (arr == null) continue;
			while (arr.length > 0) arr.pop();
			for (v in copy) arr.push(v);
		}
	}

	/** Clear per-trial simulator / series / chart state for independent backtests. */
	public function resetForTrial(?initialCash:Float = 100000):Void {
		orders.reset(initialCash);
		series = new Map();
		seriesBuffers = new Map();
		chart.commands = [];
		currentBar = null;
		eventLog.reset();
		TradeBuiltins.resetCrossState();
	}

	public function optimize(plan:ExecutionPlan, metric:String):OptimizeResult {
		return new PlanRunner(this).optimize(plan, metric);
	}

	static var ENCODING_METHODS:Array<String> = ["zscore", "rank", "returns", "diff", "rolling_mean"];

	/**
	 * Deterministic encoding search heuristic — **not** an LLM call.
	 * Cycles methods and feature subsets from the input names to produce varied,
	 * reproducible specs for discovery pipelines and tests.
	 */
	public function llmSuggestEncodings(features:Array<String>, n:Int):Array<Dynamic> {
		var base = features != null && features.length > 0 ? features : ["close"];
		var count = n > 0 ? n : 1;
		var out:Array<Dynamic> = [];
		for (i in 0...count) {
			var method = ENCODING_METHODS[i % ENCODING_METHODS.length];
			var selected = selectEncodingFeatures(base, i, method);
			var spec:Dynamic = {
				name: 'enc_${method}_$i',
				features: selected,
				method: method,
				heuristic: true,
				score: encodingHeuristicScore(base, selected, method, i),
				weight: encodingHeuristicWeight(method, i)
			};
			if (method == "rolling_mean") Reflect.setField(spec, "window", 5 + (i % 15));
			if (method == "diff" || method == "returns") Reflect.setField(spec, "lag", 1 + (i % 3));
			out.push(spec);
		}
		return out;
	}

	/**
	 * Deterministic model simplification — **not** knowledge distillation.
	 * When `model` looks like a stump ensemble, emits a rule list and coefficient
	 * sketch derived from its metadata; otherwise returns a minimal placeholder sketch.
	 */
	public function distill(model:Dynamic, params:Array<String>):Dynamic {
		var featList = resolveFeatureList(model);
		var stumps = extractStumps(model, featList);
		var rules:Array<Dynamic> = [];
		var coeffMap = new Map<String, Float>();

		for (s in stumps) {
			var feat = Std.string(Reflect.field(s, "feature"));
			var threshold = asFloat(Reflect.field(s, "threshold"));
			var weight = asFloat(Reflect.field(s, "weight"));
			rules.push({
				feature: feat,
				op: ">=",
				threshold: threshold,
				thenWeight: weight,
				elseWeight: -weight
			});
			coeffMap.set(feat, (coeffMap.exists(feat) ? coeffMap.get(feat) : 0.0) + weight);
		}

		var coefficients:Array<Dynamic> = [];
		for (name => w in coeffMap) coefficients.push({ feature: name, weight: w });

		var sourceScore = model != null && Reflect.hasField(model, "score") ? asFloat(Reflect.field(model, "score")) : 0.0;
		return {
			distilled: true,
			heuristic: true,
			kind: "RuleList",
			rules: rules,
			coefficients: coefficients,
			sourceScore: sourceScore,
			from: summarizeModel(model),
			params: params
		};
	}

	/**
	 * Deterministic stump ensemble test double — **not** trained ML.
	 * Builds reproducible stump metadata, a heuristic score, and a local `predict`
	 * function over feature rows (object/map keyed by feature name).
	 */
	public function ensemble(features:Dynamic, trees:Int):Dynamic {
		var featList = resolveFeatureList(features);
		var nTrees = trees > 0 ? trees : 1;
		var stumps = buildStumpEnsemble(featList, nTrees);
		var score = ensembleHeuristicScore(featList, nTrees, stumps);
		return {
			kind: "DecisionTreeEnsemble",
			heuristic: true,
			features: featList,
			trees: nTrees,
			stumps: stumps,
			score: score,
			predict: function(row:Dynamic):Float {
				return predictStumpEnsemble(stumps, row, nTrees);
			}
		};
	}

	function selectEncodingFeatures(all:Array<String>, idx:Int, method:String):Array<String> {
		if (all.length == 0) return ["close"];
		var maxSpan = all.length < 3 ? all.length : 3;
		var span:Int = 1 + (hashString(method + ":" + idx) % maxSpan);
		var start = idx % all.length;
		var out:Array<String> = [];
		for (j in 0...span) out.push(all[(start + j) % all.length]);
		return out;
	}

	function encodingHeuristicScore(base:Array<String>, selected:Array<String>, method:String, idx:Int):Float {
		var methodPrior = switch (method) {
			case "zscore": 0.12;
			case "rank": 0.10;
			case "returns": 0.11;
			case "diff": 0.09;
			case "rolling_mean": 0.08;
			default: 0.05;
		};
		var tag = base.join(",") + "|" + selected.join(",") + "|" + method + "|" + idx;
		return methodPrior + selected.length * 0.01 + (hashString(tag) % 1000) * 1e-6;
	}

	function encodingHeuristicWeight(method:String, idx:Int):Float {
		var base = switch (method) {
			case "zscore": 1.0;
			case "rank": 0.9;
			case "returns": 0.85;
			case "diff": 0.8;
			case "rolling_mean": 0.75;
			default: 0.5;
		};
		return base - (idx % 5) * 0.02;
	}

	function resolveFeatureList(features:Dynamic):Array<String> {
		if (features == null) return ["close", "volume"];
		if (Std.isOfType(features, Array)) {
			var arr:Array<Dynamic> = cast features;
			if (arr.length == 0) return ["close", "volume"];
			if (Std.isOfType(arr[0], String)) return cast arr;
		}
		if (Reflect.hasField(features, "features")) {
			var nested = Reflect.field(features, "features");
			if (nested != null && Std.isOfType(nested, Array)) {
				var nestedArr:Array<Dynamic> = cast nested;
				if (nestedArr.length > 0 && Std.isOfType(nestedArr[0], String)) return cast nestedArr;
			}
		}
		if (Reflect.hasField(features, "name")) {
			return [Std.string(Reflect.field(features, "name"))];
		}
		return ["close", "volume"];
	}

	function buildStumpEnsemble(featList:Array<String>, trees:Int):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		for (i in 0...trees) {
			var feat = featList[i % featList.length];
			var h = hashString(feat + ":" + i);
			out.push({
				feature: feat,
				threshold: 0.1 + (h % 1000) / 1000.0 * 0.8,
				weight: 0.5 + (hashString("w:" + feat + ":" + i) % 100) / 200.0
			});
		}
		return out;
	}

	function extractStumps(model:Dynamic, featList:Array<String>):Array<Dynamic> {
		if (model != null && Reflect.hasField(model, "stumps")) {
			var stumps = Reflect.field(model, "stumps");
			if (stumps != null && Std.isOfType(stumps, Array)) {
				var arr:Array<Dynamic> = cast stumps;
				if (arr.length > 0) return arr;
			}
		}
		var trees = model != null && Reflect.hasField(model, "trees") ? Std.int(asFloat(Reflect.field(model, "trees"))) : 8;
		if (trees <= 0) trees = 8;
		return buildStumpEnsemble(featList, trees);
	}

	function ensembleHeuristicScore(featList:Array<String>, trees:Int, stumps:Array<Dynamic>):Float {
		var tag = featList.join(",") + "|" + trees;
		for (s in stumps) tag += "|" + Reflect.field(s, "feature") + ":" + Reflect.field(s, "threshold");
		var raw = hashString(tag) % 10000;
		return 0.35 + raw / 10000.0 * 0.55;
	}

	function predictStumpEnsemble(stumps:Array<Dynamic>, row:Dynamic, trees:Int):Float {
		if (row == null || stumps.length == 0) return 0.0;
		var sum = 0.0;
		for (s in stumps) {
			var feat = Std.string(Reflect.field(s, "feature"));
			var threshold = asFloat(Reflect.field(s, "threshold"));
			var weight = asFloat(Reflect.field(s, "weight"));
			var val = readFeatureValue(row, feat);
			sum += val >= threshold ? weight : -weight;
		}
		return sum / (trees > 0 ? trees : 1);
	}

	function readFeatureValue(row:Dynamic, feat:String):Float {
		if (row == null) return 0.0;
		if (Reflect.hasField(row, feat)) return asFloat(Reflect.field(row, feat));
		if (Std.isOfType(row, Array)) {
			var arr:Array<Dynamic> = cast row;
			for (i in 0...arr.length) {
				var item = arr[i];
				if (item != null && Reflect.hasField(item, "feature") && Std.string(Reflect.field(item, "feature")) == feat) {
					return asFloat(Reflect.field(item, "value"));
				}
			}
		}
		return 0.0;
	}

	function summarizeModel(model:Dynamic):Dynamic {
		if (model == null) return null;
		return {
			kind: Reflect.hasField(model, "kind") ? Reflect.field(model, "kind") : null,
			features: Reflect.hasField(model, "features") ? Reflect.field(model, "features") : null,
			trees: Reflect.hasField(model, "trees") ? Reflect.field(model, "trees") : null,
			score: Reflect.hasField(model, "score") ? Reflect.field(model, "score") : null,
			heuristic: Reflect.hasField(model, "heuristic") ? Reflect.field(model, "heuristic") : null
		};
	}

	function hashString(s:String):Int {
		var h = 0;
		for (i in 0...s.length) h = (h * 31 + s.charCodeAt(i)) | 0;
		return h < 0 ? -h : h;
	}

	function asFloat(v:Dynamic):Float {
		if (v == null) return 0;
		if (Std.isOfType(v, Int)) return cast v;
		if (Std.isOfType(v, Float)) return cast v;
		return Std.parseFloat(Std.string(v));
	}
}
