package musescript.types;

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
		ind("change");
		fun("pct_change", [TSeries, TWindow], TScalar, 1);
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
		fun("plot", [TScalar, TUnknown], TVoid, 1);
		fun("nz", [TScalar, TScalar], TScalar, 1);
		fun("na", [TScalar], TBool);
		fun("clamp", [TScalar, TScalar, TScalar], TScalar);
		fun("sample", [TUnknown], TPlan, 0);
		fun("tune", [TUnknown], TPlan, 0);
		fun("optimize", [TMetric], TPlan, 0);
		fun("distill", [TUnknown], TPlan, 0);
		fun("pickBest", [TUnknown], TPlan, 0);
		fun("feature", [TUnknown], TFeature, 1);
		fun("zscore", [TFeature, TWindow], TFeature);
		fun("xscore", [TFeature], TFeature);
		fun("gscore", [TFeature], TFeature);
		fun("model_score", [TUnknown], TFeature);
		fun("mlp", [TFeature], TModel, 1);
		fun("gbdt", [TFeature], TModel, 1);
		fun("tree", [TFeature], TTree, 1);
		fun("tree_value", [TTree], TFeature);
		fun("tree_bit", [TTree, TWindow], TFeature);
		fun("graph_query", [TUnknown], TGraphQuery, 1);
		fun("graph_metric", [TGraphQuery, TUnknown], TFeature, 1);
	}

	static function ind(name:String):Void {
		fun(name, [TSeries, TWindow], TSeries);
	}

	static function fun(name:String, args:Array<MuseType>, ret:MuseType, ?minArgs:Int):Void {
		table.set(name, {
			args: args,
			ret: ret,
			minArgs: minArgs != null ? minArgs : args.length
		});
	}
}
