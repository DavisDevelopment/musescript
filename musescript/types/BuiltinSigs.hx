package musescript.types;

import musescript.ast.Expr;

/**
 * Typed signatures for TradeBuiltins / order / chart helpers.
 */
class BuiltinSigs {
	static var table:Map<String, BuiltinSig>;

	public static function get(name:String):Null<BuiltinSig> {
		ensure();
		return table.get(name);
	}

	public static function all():Map<String, BuiltinSig> {
		ensure();
		return table;
	}

	/** True when the named builtin expects a Series value at the given argument index. */
	public static function wantsSeries(name:String, argIndex:Int):Bool {
		var sig = get(name);
		if (sig == null || argIndex < 0 || argIndex >= sig.args.length) return false;
		return sig.args[argIndex].match(TSeries);
	}

	/**
	 * When a Series argument is authored as an OHLCV / composite bar field
	 * (`high`, `close`, …), return its series name rather than the current-bar float.
	 */
	public static function seriesNameOf(e:Expr):Null<String> {
		return switch (e) {
			case EBarField(n): isBarSeriesName(n) ? n : null;
			case EIdent(n): isBarSeriesName(n) ? n : null;
			case EParent(inner): seriesNameOf(inner);
			default: null;
		};
	}

	public static function isBarSeriesName(n:String):Bool {
		return n == "open" || n == "high" || n == "low" || n == "close" || n == "volume"
			|| n == "hl2" || n == "hlc3" || n == "ohlc4";
	}

	public static function toPaletteJson():Dynamic {
		ensure();
		var prims:Array<Dynamic> = [];
		for (name => sig in table) {
			prims.push({
				id: name,
				args: [for (a in sig.args) MuseTypes.toString(a)],
				returns: MuseTypes.toString(sig.ret),
				minArgs: sig.minArgs != null ? sig.minArgs : sig.args.length
			});
		}
		return {
			schema: "musegene.palette/1",
			id: "musescript.builtins-v1",
			windows: MuseTypes.WINDOW_LADDER.copy(),
			fields: ["open", "high", "low", "close", "volume", "hl2", "hlc3", "ohlc4"],
			primitives: prims
		};
	}

	static function ensure():Void {
		if (table != null) return;
		table = new Map();
		ind("sma");
		ind("ema");
		ind("rsi");
		ind("atr");
		ind("wma");
		ind("rma");
		ind("stdev");
		ind("highest");
		ind("lowest");
		ind("mom");
		ind("roc");
		fun("change", [TSeries, TWindow], TSeries, 1);
		fun("pct_change", [TSeries, TWindow], TScalar, 1);
		fun("bbands", [TSeries, TWindow, TScalar], TUnknown, 2);
		fun("macd", [TSeries, TWindow, TWindow, TWindow], TUnknown, 1);
		fun("stoch", [TWindow, TWindow, TWindow], TUnknown, 0);
		fun("vwap", [], TSeries);
		fun("hl2", [], TSeries);
		fun("hlc3", [], TSeries);
		fun("ohlc4", [], TSeries);
		fun("crossover", [TSeries, TSeries], TBool);
		fun("crossunder", [TSeries, TSeries], TBool);
		fun("rising", [TSeries, TWindow], TBool);
		fun("falling", [TSeries, TWindow], TBool);
		fun("long", [TScalar], TVoid, 0);
		fun("short", [TScalar], TVoid, 0);
		fun("flat", [], TVoid);
		// note: do not register `close` as Void — it is a Series bar field
		fun("plot", [TScalar, TString, TString], TVoid, 1);
		fun("plotshape", [TString], TVoid);
		fun("hline", [TScalar, TString], TVoid);
		fun("bgcolor", [TString], TVoid);
		fun("nz", [TScalar, TScalar], TScalar, 1);
		fun("na", [TScalar], TBool);
		fun("clamp", [TScalar, TScalar, TScalar], TScalar);
		fun("window", [TSeries, TWindow], TVector);
		fun("ohlcv_window", [TWindow], TVector);
		fun("str_len", [TString], TScalar);
		fun("str_slice", [TString, TScalar, TScalar], TString, 2);
		fun("str_contains", [TString, TString], TBool);
		fun("str_concat", [TString, TString], TString);
		fun("str_to_float", [TString], TScalar);
		fun("vector_zscore", [TVector], TVector);
		fun("correlation", [TVector, TVector], TScalar);
		fun("sharpe", [TVector], TScalar);
		fun("map", [TUnknown, TUnknown], TVector);
		fun("flatMap", [TUnknown, TUnknown], TVector);
		fun("filter", [TUnknown, TUnknown], TVector);
		fun("any", [TUnknown, TUnknown], TBool);
		fun("all", [TUnknown, TUnknown], TBool);
		fun("find", [TUnknown, TUnknown], TUnknown);
		fun("sum", [TUnknown], TScalar);
		fun("count", [TUnknown], TScalar);
		fun("min", [TUnknown], TScalar);
		fun("max", [TUnknown], TScalar);
		fun("avg", [TUnknown], TScalar);
		fun("take", [TUnknown, TScalar], TVector);
		fun("drop", [TUnknown, TScalar], TVector);
		fun("takeWhile", [TUnknown, TUnknown], TVector);
		fun("scan", [TUnknown, TUnknown, TUnknown], TVector);
		fun("reduce", [TUnknown, TUnknown, TUnknown], TUnknown);
		fun("range", [TScalar, TScalar], TVector, 1);
		fun("enumerate", [TUnknown], TVector);
		fun("merge", [TUnknown, TUnknown], TVector);
		fun("zip", [TUnknown, TUnknown], TVector);
		fun("zipWith", [TUnknown, TUnknown, TUnknown], TVector);
		fun("sample", [TUnknown], TPlan, 0);
		fun("tune", [TUnknown], TPlan, 0);
		fun("optimize", [TMetric], TPlan, 0);
		fun("distill", [TUnknown], TPlan, 0);
		fun("pickBest", [TUnknown], TPlan, 0);
		fun("feature", [TString], TFeature);
		fun("zscore", [TFeature, TWindow], TFeature);
		fun("xscore", [TFeature], TFeature);
		fun("gscore", [TFeature], TFeature);
		fun("model_score", [TString], TFeature);
		fun("mlp", [TFeature], TModel, 1);
		fun("gbdt", [TFeature], TModel, 1);
		fun("tree", [TFeature], TTree, 1);
		fun("tree_value", [TString], TFeature);
		fun("tree_bit", [TString, TWindow], TFeature);
		fun("graph_query", [TString], TGraphQuery);
		fun("graph_metric", [TString, TString], TFeature);
	}

	static function ind(name:String):Void {
		fun(name, [TSeries, TWindow], TSeries);
	}

	static function fun(name:String, args:Array<MuseType>, ret:MuseType, ?minArgs:Int, ?varArgs:Bool):Void {
		table.set(name, {
			args: args,
			ret: ret,
			minArgs: minArgs != null ? minArgs : args.length,
			varArgs: varArgs == true
		});
	}
}
