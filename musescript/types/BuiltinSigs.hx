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

	/** Out-of-tree packages (e.g. Kestrel) register their own typed signatures here, so the
	 * checker/palette recognize names core has no builtin implementation for, without core
	 * naming that package anywhere. Call after ensure() has had a chance to run once (any call
	 * to get/all/toPaletteJson triggers that), or just call register() itself — it self-ensures. */
	public static function register(name:String, sig:BuiltinSig):Void {
		ensure();
		table.set(name, sig);
	}

	/**
	 * True when `name` is a builtin that takes no arguments and returns a plain scalar
	 * (`bars_in_trade`, `equity`, `position`, `cash`, ...).
	 *
	 * Strategies spell these bare at least as often as `name()` -- see the dozens of
	 * `when bars_in_trade >= look: flat()` lines under examples/strategy-kinds -- so a bare
	 * reference has to read as a CALL rather than as a reference to the installed closure.
	 * Nullary builtins returning a series or a collection (`hl2`, `symbols`, `dict_new`) are
	 * deliberately excluded: those ARE meaningful as values, and series-typed arguments already
	 * resolve through `seriesNameOf` before they would ever be evaluated.
	 */
	public static function isNullaryScalar(name:String):Bool {
		var sig = get(name);
		if (sig == null || sig.args.length != 0) return false;
		return switch (sig.ret) {
			case TScalar: true;
			default: false;
		};
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
		ind("atr"); fun("atr", [TSeries, TWindow], TSeries, 1); // accept 1-arg atr(n) too (implicit OHLC)
		ind("wma");
		ind("rma");
		ind("stdev");
		ind("highest");
		ind("lowest");
		ind("mom");
		ind("roc");
		fun("change", [TSeries, TWindow], TSeries, 1);
		fun("pct_change", [TSeries, TWindow], TScalar, 1);
		// Ported Wickra indicators (github.com/wickra-lib/wickra, ROADMAP.md
		// epic 9) register their typed signatures here from the SAME
		// IndicatorRegistry that install/dispatch read — so a ported
		// indicator never needs a hand-written entry in this file. See
		// musescript/indicators/IndicatorSpec.hx.
		for (name => spec in musescript.indicators.IndicatorRegistry.all())
			table.set(name, { args: spec.args, ret: spec.ret,
				minArgs: spec.minArgs, varArgs: false });
		fun("bbands", [TSeries, TWindow, TScalar], TObject([
			{name: "mid", ty: TScalar},
			{name: "upper", ty: TScalar},
			{name: "lower", ty: TScalar}
		]), 2);
		fun("macd", [TSeries, TWindow, TWindow, TWindow], TObject([
			{name: "macd", ty: TScalar},
			{name: "signal", ty: TScalar},
			{name: "hist", ty: TScalar}
		]), 1);
		fun("stoch", [TWindow, TWindow, TWindow], TObject([
			{name: "k", ty: TScalar},
			{name: "d", ty: TScalar}
		]), 0);
		fun("vwap", [], TSeries);
		fun("hl2", [], TSeries);
		fun("hlc3", [], TSeries);
		fun("ohlc4", [], TSeries);
		// Runtime is Float+callsite history (same pattern as rising/falling).
		fun("crossover", [TScalar, TScalar], TBool);
		fun("crossunder", [TScalar, TScalar], TBool);
		// Optional third arg gates the slope test until the position has been
		// open for `minBars`, avoiding repeated `bars_in_trade >= k && ...`.
		// Runtime tracks history by callsite from the current scalar leaf (Float),
		// not from a Series handle — match TradeBuiltins.rising/falling.
		fun("rising", [TScalar, TWindow, TWindow], TBool, 2);
		fun("falling", [TScalar, TWindow, TWindow], TBool, 2);
		// Arg is a qty Scalar OR an order-spec object {type, px, qty, tifBars}
		// (OrderBook.hx) — TUnknown is the honest arg type for both.
		fun("long", [TUnknown], TVoid, 0);
		fun("short", [TUnknown], TVoid, 0);
		fun("flat", [TUnknown], TVoid, 0);
		fun("orders_pending", [], TScalar);
		fun("orders_cancel_all", [], TScalar);
		fun("position", [], TScalar);
		fun("entry_price", [], TScalar);
		fun("bars_in_trade", [], TScalar);
		fun("cash", [], TScalar);
		fun("equity", [], TScalar);
		// Per-instrument conditionality: run-constant tape identity (crypto vs FX vs equity).
		fun("asset_is", [TString], TBool);
		fun("symbol_is", [TString], TBool);
		// Confirmation voting / bool->number: count how many of the given boolean conditions hold.
		// Variadic; returns a scalar so `count_true(a, b, c) >= 2` expresses an N-of-M gate, and
		// `count_true(x)` is a plain bool->0/1 coercion. minArgs 1 so an empty call is a type error.
		fun("count_true", [TBool], TScalar, 1, true);
		// Variadic boolean combinators (OR / AND over N conditions).
		fun("any_of", [TBool], TBool, 1, true);
		fun("all_of", [TBool], TBool, 1, true);
		// Donchian channel struct (reads high/low implicitly): donchian(n).upper / .lower / .mid.
		// `.middle` is an equal alias for `.mid` (the interp resolves donchian to the indicator-lib
		// impl, which historically named the midline `middle`; both keys are declared for parity).
		fun("donchian", [TWindow], TObject([
			{name: "upper", ty: TScalar},
			{name: "lower", ty: TScalar},
			{name: "mid", ty: TScalar},
			{name: "middle", ty: TScalar}
		]));
		// Candle-pattern vocabulary (SPEC_CANDLE_PATTERN_DSL.md P0): scale-free per-bar features,
		// `i` bars back (0 = current). Range-normalized; the last two are ATR-normalized (optional n).
		fun("candle_body", [TScalar], TScalar);
		fun("candle_body_abs", [TScalar], TScalar);
		fun("candle_upper_wick", [TScalar], TScalar);
		fun("candle_lower_wick", [TScalar], TScalar);
		fun("candle_dir", [TScalar], TScalar);
		fun("candle_range_atr", [TScalar, TWindow], TScalar, 1);
		fun("candle_gap", [TScalar, TWindow], TScalar, 1);
		// Setup memory: bars since a boolean condition was last true (large sentinel if never).
		fun("bars_since", [TBool], TScalar);
		// Peak-following trailing stop: true once price retraces `dist` (price units, e.g. k*atr(n))
		// from the best level reached since entry. Inert while flat.
		fun("trail", [TScalar], TBool);
		// In-trade analytics: extremes since entry (optional field, default high/low) + signed return.
		fun("highest_since_entry", [TString], TScalar, 0);
		fun("lowest_since_entry", [TString], TScalar, 0);
		fun("return_since_entry", [], TScalar);
		// Series-stat regime gates: signed trend slope / normalized deviation / scale-free rank.
		fun("slope", [TSeries, TWindow], TScalar);
		fun("zscore_roll", [TSeries, TWindow], TScalar);
		fun("percent_rank", [TSeries, TWindow], TScalar);
		// Variadic instrument membership (extends asset_is/symbol_is).
		fun("asset_in", [TString], TBool, 1, true);
		fun("symbol_in", [TString], TBool, 1, true);
		fun("unrealized_pnl", [], TScalar);
		fun("unrealized_pnl_pct", [], TScalar);
		// Multi-symbol panel / portfolio surface
		fun("symbols", [], TStringArray);
		fun("sym_available", [TString], TBool);
		fun("close_of", [TString, TWindow], TScalar, 1);
		fun("open_of", [TString, TWindow], TScalar, 1);
		fun("high_of", [TString, TWindow], TScalar, 1);
		fun("low_of", [TString, TWindow], TScalar, 1);
		fun("volume_of", [TString, TWindow], TScalar, 1);
		fun("sma_of", [TString, TWindow], TScalar);
		fun("ema_of", [TString, TWindow], TScalar);
		fun("mom_of", [TString, TWindow], TScalar);
		fun("rsi_of", [TString, TWindow], TScalar);
		// Per-symbol auxiliary/fundamental field (PIT-correct, causally-fed panel aux series).
		fun("fund_of", [TString, TString, TWindow], TScalar, 2);
		fun("scan_top", [TDict, TScalar], TStringArray);
		fun("scan_bottom", [TDict, TScalar], TStringArray);
		fun("buy", [TString, TScalar], TVoid, 1);
		fun("sell_all", [TString], TVoid);
		// Per-symbol pending books (panel): qty Scalar OR order-spec / bracket object.
		fun("portfolio_long", [TString, TUnknown], TVoid, 1);
		fun("portfolio_short", [TString, TUnknown], TVoid, 1);
		fun("portfolio_flat", [TString, TUnknown], TVoid, 1);
		fun("portfolio_orders_pending", [TString], TScalar, 0);
		fun("portfolio_orders_cancel_all", [TString], TScalar, 0);
		fun("pos", [TString], TScalar);
		fun("entry_of", [TString], TScalar);
		fun("weight_of", [TString], TScalar);
		fun("holdings", [], TStringArray);
		fun("rebalance_equal", [TStringArray], TVoid);
		fun("target_weight", [TString, TScalar], TVoid);
		fun("portfolio_equity", [], TScalar);
		fun("portfolio_cash", [], TScalar);
		fun("portfolio_unrealized", [], TScalar);
		// Named weighted bags / pairs → portfolio composition
		fun("bag", [TString], TBag, 0);
		fun("bag_new", [TString], TBag, 0);
		fun("bag_set", [TBag, TString, TScalar], TBag);
		fun("bag_get", [TBag, TString], TScalar);
		fun("bag_has", [TBag, TString], TBool);
		fun("bag_delete", [TBag, TString], TBag);
		fun("bag_name", [TBag], TString);
		fun("bag_rename", [TBag, TString], TBag);
		fun("bag_symbols", [TBag], TStringArray);
		fun("bag_size", [TBag], TScalar);
		fun("bag_equal", [TStringArray, TString], TBag, 1);
		fun("bag_pair", [TString, TString, TScalar, TString], TBag, 2);
		fun("bag_from_dict", [TDict, TString], TBag, 1);
		fun("bag_from_scan", [TDict, TScalar, TString, TBool], TBag, 2);
		fun("bag_to_dict", [TBag], TDict);
		fun("bag_mode", [TBag], TString);
		fun("bag_is_static", [TBag], TBool);
		fun("bag_is_computed", [TBag], TBool);
		fun("bag_computed", [TUnknown, TUnknown], TBag, 1);
		fun("bag_resolve", [TBag], TBag);
		fun("bag_rank_mom", [TScalar, TScalar, TString], TBag, 1);
		fun("bag_rank_rsi", [TScalar, TScalar, TString, TBool], TBag, 1);
		fun("bag_rank_field", [TString, TScalar, TString, TBool], TBag, 2);
		fun("bag_graph", [TGraph, TString, TScalar, TString], TBag, 2);
		fun("bag_add", [TBag, TBag, TString], TBag, 2);
		fun("bag_sub", [TBag, TBag, TString], TBag, 2);
		fun("bag_mask", [TBag, TUnknown, TString], TBag, 2);
		fun("bag_scale", [TBag, TScalar, TString], TBag, 2);
		fun("bag_norm", [TBag, TString], TBag, 1);
		fun("portfolio_bag", [TString], TBag, 0);
		fun("portfolio_apply", [TBag], TVoid);
		fun("portfolio_add", [TBag], TVoid);
		fun("portfolio_sub", [TBag], TVoid);
		fun("portfolio_mask", [TUnknown], TVoid);
		// note: do not register `close` as Void — it is a Series bar field
		fun("log", [TUnknown, TUnknown, TUnknown, TUnknown], TVoid, 0);
		fun("plot", [TScalar, TString, TString], TVoid, 1);
		fun("plotshape", [TString], TVoid);
		fun("hline", [TScalar, TString], TVoid);
		fun("bgcolor", [TString], TVoid);
		// muse.diag / diag_* — post-run Metrics + ChartSink pack (not WASM hot path).
		fun("diag_running_max", [TVector], TVector);
		fun("diag_drawdown", [TVector], TVector);
		fun("diag_acf", [TVector, TScalar], TVector, 1);
		fun("diag_rolling_acf", [TVector, TScalar, TScalar], TVector, 1);
		fun("diag_kiss", [TVector], TUnknown, 0);
		fun("diag_underwater", [TVector], TUnknown, 0);
		fun("diag_pack", [TVector, TScalar, TScalar], TUnknown, 0);
		fun("nz", [TUnknown, TScalar], TScalar, 1);
		// Runtime accepts any Dynamic (null/NaN/series leaf); TUnknown is the honest arg type.
		fun("na", [TUnknown], TBool);
		fun("clamp", [TScalar, TScalar, TScalar], TScalar);
		fun("window", [TSeries, TWindow], TVector);
		fun("ohlcv_window", [TWindow], TVector);
		fun("str_len", [TString], TScalar);
		fun("str_slice", [TString, TScalar, TScalar], TString, 2);
		fun("str_contains", [TString, TString], TBool);
		fun("str_concat", [TString, TString], TString);
		fun("str_to_float", [TString], TScalar);
		fun("str_trim", [TString], TString);
		fun("str_lower", [TString], TString);
		fun("str_upper", [TString], TString);
		fun("str_starts_with", [TString, TString], TBool);
		fun("str_ends_with", [TString, TString], TBool);
		fun("str_index_of", [TString, TString, TScalar], TScalar, 2);
		fun("str_replace", [TString, TString, TString], TString);
		fun("str_split", [TString, TString], TStringArray);
		fun("str_join", [TStringArray, TString], TString);
		fun("str_to_bool", [TString], TBool);
		fun("str_from_float", [TScalar], TString);
		fun("str_from_bool", [TBool], TString);
		fun("str_fmt", [TString, TUnknown], TString, 1);
		fun("path_join", [TString], TString, 1, true);
		fun("path_normalize", [TString], TString);
		fun("path_basename", [TString], TString);
		fun("path_dirname", [TString], TString);
		fun("path_ext", [TString], TString);
		fun("path_is_absolute", [TString], TBool);
		fun("re_compile", [TString, TString], TUnknown, 1);
		fun("re_test", [TUnknown, TString], TBool);
		fun("re_match", [TUnknown, TString], TUnknown);
		fun("re_find_all", [TUnknown, TString, TScalar], TUnknown, 2);
		fun("re_replace", [TUnknown, TString, TString, TScalar], TString, 3);
		fun("re_split", [TUnknown, TString, TScalar], TStringArray, 2);
		fun("fs_read_text", [TString], TString);
		fun("fs_write_text", [TString, TString], TBool);
		fun("fs_append_text", [TString, TString], TBool);
		fun("fs_exists", [TString], TBool);
		fun("fs_is_dir", [TString], TBool);
		fun("fs_is_file", [TString], TBool);
		fun("fs_list", [TString], TStringArray);
		fun("fs_mkdir", [TString, TBool], TBool, 1);
		fun("http_request", [TUnknown], TUnknown);
		fun("http_get", [TString, TUnknown], TUnknown, 1);
		fun("http_post", [TString, TUnknown, TUnknown], TUnknown, 1);
		fun("ml_dot", [TVector, TVector], TScalar);
		fun("ml_sigmoid", [TScalar], TScalar);
		fun("ml_softmax", [TVector], TVector);
		fun("ml_mse", [TVector, TVector], TScalar);
		fun("ml_mae", [TVector, TVector], TScalar);
		fun("ml_linear_predict", [TVector, TVector, TScalar], TScalar, 2);
		fun("ml_ridge_fit", [TVector, TVector, TScalar, TScalar], TVector, 3);
		fun("ml_matrix", [TScalar, TScalar, TVector], TMatrix);
		fun("ml_matrix_rows", [TMatrix], TScalar);
		fun("ml_matrix_cols", [TMatrix], TScalar);
		fun("ml_matrix_data", [TMatrix], TVector);
		fun("ml_matrix_get", [TMatrix, TScalar, TScalar], TScalar);
		fun("ml_matrix_transpose", [TMatrix], TMatrix);
		fun("ml_matrix_inverse", [TMatrix], TMatrix);
		fun("ml_matrix_determinant", [TMatrix], TScalar);
		fun("ml_ridge_fit_matrix", [TMatrix, TVector, TScalar], TVector, 2);
		// muse.np / flat np_* — M2 catalog. Comparisons → Bool ndarray (TNdArray opaque).
		// Reductions accept optional axis (scalar|list) / keepdims.
		fun("np_zeros", [TUnknown], TNdArray);
		fun("np_ones", [TUnknown], TNdArray);
		fun("np_full", [TUnknown, TScalar], TNdArray);
		fun("np_empty", [TUnknown], TNdArray);
		fun("np_arange", [TScalar, TScalar, TScalar], TNdArray, 1);
		fun("np_linspace", [TScalar, TScalar, TScalar, TBool], TNdArray, 2);
		fun("np_eye", [TScalar, TScalar], TNdArray, 1);
		fun("np_identity", [TScalar], TNdArray);
		fun("np_asarray", [TUnknown, TUnknown], TNdArray, 1);
		fun("np_array", [TUnknown, TUnknown], TNdArray, 1);
		fun("np_reshape", [TNdArray, TUnknown], TNdArray);
		fun("np_transpose", [TNdArray, TUnknown], TNdArray, 1);
		fun("np_swapaxes", [TNdArray, TScalar, TScalar], TNdArray);
		fun("np_copy", [TNdArray], TNdArray);
		fun("np_ravel", [TNdArray], TNdArray);
		fun("np_flatten", [TNdArray], TNdArray);
		fun("np_expand_dims", [TNdArray, TScalar], TNdArray);
		fun("np_squeeze", [TNdArray, TScalar], TNdArray, 1);
		fun("np_broadcast_to", [TNdArray, TUnknown], TNdArray);
		fun("np_concatenate", [TUnknown, TScalar], TNdArray, 1);
		fun("np_stack", [TUnknown, TScalar], TNdArray, 1);
		fun("np_shape", [TNdArray], TVector);
		fun("np_ndim", [TNdArray], TScalar);
		fun("np_size", [TNdArray], TScalar);
		fun("np_is_c_contiguous", [TNdArray], TBool);
		fun("np_get", [TNdArray, TUnknown], TScalar);
		fun("np_get_flat", [TNdArray, TScalar], TScalar);
		fun("np_slice", [TNdArray, TScalar, TScalar, TScalar], TNdArray, 3);
		fun("np_slice_axis", [TNdArray, TScalar, TScalar, TScalar, TScalar], TNdArray, 4);
		fun("np_take", [TNdArray, TUnknown, TScalar], TNdArray, 2);
		fun("np_gather", [TNdArray, TUnknown], TNdArray);
		fun("np_take_along", [TNdArray, TNdArray, TScalar], TNdArray);
		fun("np_astype", [TNdArray, TString], TNdArray);
		fun("np_dtype", [TNdArray], TString);
		fun("np_bool", [TNdArray], TNdArray);
		fun("np_bool_to_f64", [TNdArray], TNdArray);
		fun("np_add", [TNdArray, TNdArray], TNdArray);
		fun("np_subtract", [TNdArray, TNdArray], TNdArray);
		fun("np_multiply", [TNdArray, TNdArray], TNdArray);
		fun("np_divide", [TNdArray, TNdArray], TNdArray);
		fun("np_power", [TNdArray, TNdArray], TNdArray);
		fun("np_minimum", [TNdArray, TNdArray], TNdArray);
		fun("np_maximum", [TNdArray, TNdArray], TNdArray);
		fun("np_equal", [TNdArray, TNdArray], TNdArray);
		fun("np_not_equal", [TNdArray, TNdArray], TNdArray);
		fun("np_greater", [TNdArray, TNdArray], TNdArray);
		fun("np_greater_equal", [TNdArray, TNdArray], TNdArray);
		fun("np_less", [TNdArray, TNdArray], TNdArray);
		fun("np_less_equal", [TNdArray, TNdArray], TNdArray);
		fun("np_negative", [TNdArray], TNdArray);
		fun("np_abs", [TNdArray], TNdArray);
		fun("np_sqrt", [TNdArray], TNdArray);
		fun("np_exp", [TNdArray], TNdArray);
		fun("np_log", [TNdArray], TNdArray);
		fun("np_square", [TNdArray], TNdArray);
		fun("np_sign", [TNdArray], TNdArray);
		fun("np_clip", [TNdArray, TScalar, TScalar], TNdArray);
		fun("np_where", [TNdArray, TNdArray, TNdArray], TNdArray);
		fun("np_compress", [TNdArray, TNdArray], TNdArray);
		fun("np_assign_where", [TNdArray, TNdArray, TNdArray], TBool);
		fun("np_sum", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_mean", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_min", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_max", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_prod", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_std", [TNdArray, TUnknown, TBool, TScalar], TUnknown, 1);
		fun("np_var", [TNdArray, TUnknown, TBool, TScalar], TUnknown, 1);
		fun("np_any", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_all", [TNdArray, TUnknown, TBool], TUnknown, 1);
		fun("np_cumsum", [TNdArray, TScalar], TNdArray, 1);
		fun("np_diff", [TNdArray], TNdArray);
		fun("np_matmul", [TNdArray, TNdArray], TNdArray);
		fun("np_dot", [TNdArray, TNdArray], TScalar);
		fun("np_outer", [TNdArray, TNdArray], TNdArray);
		fun("np_to_vector", [TNdArray], TVector);
		// Risk / sizing helpers — return requested qty (scalar|NdArray); OrderSim still clamps at fill.
		// vol_target_qty(vol|prices, target, base [, max [, min [, window [, eps]]]])
		fun("np_vol_target_qty", [TUnknown, TScalar, TUnknown, TScalar, TScalar, TScalar, TScalar], TUnknown, 3);
		fun("np_mask_qty", [TNdArray, TUnknown, TScalar, TScalar], TUnknown, 2);
		fun("np_rolling_log_vol", [TNdArray, TScalar, TScalar], TNdArray, 2);
		// muse.pd / flat pd_* — M0 construct/select. TPdSeries ≠ streaming TSeries.
		fun("pd_series", [TUnknown, TUnknown, TString], TPdSeries, 1);
		fun("pd_dataframe", [TUnknown, TUnknown, TUnknown], TDataFrame, 1);
		fun("pd_from_columns", [TUnknown, TUnknown, TUnknown], TDataFrame, 1);
		fun("pd_from_ndarray", [TNdArray, TUnknown, TUnknown], TDataFrame, 1);
		fun("pd_empty", [TScalar, TUnknown], TDataFrame, 0);
		fun("pd_shape", [TDataFrame], TVector);
		fun("pd_columns", [TDataFrame], TStringArray);
		fun("pd_nrows", [TDataFrame], TScalar);
		fun("pd_ncols", [TDataFrame], TScalar);
		fun("pd_index", [TUnknown], TIndex);
		fun("pd_get", [TDataFrame, TString], TPdSeries);
		fun("pd_select", [TDataFrame, TUnknown], TDataFrame);
		fun("pd_assign", [TDataFrame, TString, TUnknown], TDataFrame);
		fun("pd_drop", [TDataFrame, TUnknown], TDataFrame);
		fun("pd_copy", [TUnknown], TUnknown);
		fun("pd_head", [TUnknown, TScalar], TUnknown, 1);
		fun("pd_tail", [TUnknown, TScalar], TUnknown, 1);
		fun("pd_iloc", [TDataFrame, TUnknown], TDataFrame);
		fun("pd_to_ndarray", [TDataFrame], TNdArray);
		fun("pd_series_values", [TPdSeries], TNdArray);
		fun("pd_series_name", [TPdSeries], TString);
		fun("pd_series_length", [TPdSeries], TScalar);
		fun("pd_index_kind", [TIndex], TString);
		fun("pd_index_range", [TScalar], TIndex);
		fun("pd_index_floats", [TUnknown], TIndex);
		fun("pd_index_strings", [TUnknown], TIndex);
		fun("pd_from_bars", [TUnknown], TDataFrame);
		fun("pd_from_bar_column", [TUnknown, TString, TString], TPdSeries, 2);
		fun("pd_from_panel", [TUnknown, TUnknown], TDataFrame, 1);
		fun("pd_reindex", [TDataFrame, TIndex], TDataFrame);
		fun("pd_align", [TDataFrame, TDataFrame, TString], TUnknown, 2);
		fun("pd_join", [TDataFrame, TDataFrame, TString, TString, TBool], TDataFrame, 3);
		fun("pd_merge_asof", [TDataFrame, TDataFrame, TString, TString, TString, TBool, TScalar], TDataFrame, 3);
		fun("pd_fillna", [TDataFrame, TScalar], TDataFrame);
		fun("pd_dropna", [TDataFrame, TString], TDataFrame, 1);
		fun("pd_isna", [TDataFrame], TDataFrame);
		fun("pd_concat", [TUnknown], TDataFrame);
		fun("pd_concat_cols", [TDataFrame, TDataFrame, TString], TDataFrame, 2);
		fun("pd_parse_csv", [TString], TDataFrame);
		fun("pd_read_csv", [TString], TDataFrame);
		// M2 — groupby / cross-section / windows (Interp N | JS B | WASM H/U)
		fun("pd_groupby_agg", [TDataFrame, TString, TString], TDataFrame, 2);
		fun("pd_groupby_transform", [TDataFrame, TString, TString], TDataFrame, 2);
		fun("pd_groupby_rank", [TDataFrame, TString, TBool], TDataFrame, 2);
		fun("pd_groupby_mean", [TDataFrame, TString], TDataFrame);
		fun("pd_groupby_sum", [TDataFrame, TString], TDataFrame);
		fun("pd_groupby_std", [TDataFrame, TString], TDataFrame);
		fun("pd_rank", [TUnknown, TBool, TBool], TUnknown, 1);
		fun("pd_xs_rank", [TDataFrame, TBool, TBool], TDataFrame, 1);
		fun("pd_shift", [TUnknown, TScalar], TUnknown, 1);
		fun("pd_diff", [TUnknown, TScalar], TUnknown, 1);
		fun("pd_pct_change", [TUnknown, TScalar], TUnknown, 1);
		fun("pd_rolling_mean", [TUnknown, TScalar], TUnknown);
		fun("pd_rolling_sum", [TUnknown, TScalar], TUnknown);
		fun("pd_rolling_std", [TUnknown, TScalar, TScalar], TUnknown, 2);
		fun("pd_ewm_mean", [TUnknown, TScalar], TUnknown);
		// M3 reshape / multi-key / corr
		fun("pd_groupby_keys_agg", [TDataFrame, TUnknown, TString], TDataFrame, 2);
		fun("pd_pivot", [TDataFrame, TString, TString, TString], TDataFrame);
		fun("pd_melt", [TDataFrame, TUnknown, TUnknown, TString, TString], TDataFrame, 1);
		fun("pd_corr", [TDataFrame], TDataFrame);
		fun("pd_cov", [TDataFrame, TScalar], TDataFrame, 1);
		fun("vector_zscore", [TVector], TVector);
		// `zscore` is the vector builtin at runtime (same as vector_zscore). The old
		// Feature-pipeline signature was a palette lie — keep feature transforms named
		// distinctly if/when they land.
		fun("zscore", [TVector], TVector);
		fun("correlation", [TVector, TVector], TScalar);
		fun("sharpe", [TVector], TScalar);
		fun("stat_mean", [TVector], TScalar);
		fun("stat_median", [TVector], TScalar);
		fun("stat_variance", [TVector], TScalar);
		fun("stat_sample_variance", [TVector], TScalar);
		fun("stat_stddev", [TVector], TScalar);
		fun("stat_sample_stddev", [TVector], TScalar);
		fun("stat_quantile", [TVector, TScalar], TScalar);
		fun("stat_covariance", [TVector, TVector], TScalar);
		fun("stat_correlation", [TVector, TVector], TScalar);
		fun("stat_skewness", [TVector], TScalar);
		fun("stat_kurtosis", [TVector], TScalar);
		fun("stat_rank", [TVector, TScalar], TScalar);
		fun("stat_percentile_rank", [TVector, TScalar], TScalar);
		fun("stat_regression", [TVector], TObject([
			{name: "slope", ty: TScalar},
			{name: "intercept", ty: TScalar},
			{name: "r2", ty: TScalar}
		]));
		fun("stat_autocorr", [TVector, TScalar], TScalar);
		fun("sort", [TVector], TVector);
		fun("argsort", [TVector], TVector);
		fun("sortino", [TVector], TScalar);
		fun("max_drawdown", [TVector], TScalar);
		fun("ewm_var", [TSeries, TWindow], TSeries);
		fun("ewm_stdev", [TSeries, TWindow], TSeries);
		fun("stat_zscore", [TVector], TVector);
		fun("sci_cumsum", [TVector], TVector);
		fun("sci_diff", [TVector], TVector);
		fun("sci_normalize", [TVector], TVector);
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
		// Plan/macro builtins are multi-arg in real strategies (`tune(fast, slow)`,
		// `sample(universe, 10)`, `optimize(sharpe, [fast, slow])`).
		fun("sample", [TUnknown], TPlan, 0, true);
		fun("tune", [TUnknown], TPlan, 0, true);
		fun("optimize", [TUnknown, TUnknown], TPlan, 1);
		fun("distill", [TUnknown], TPlan, 0, true);
		fun("pickBest", [TUnknown], TPlan, 0, true);
		fun("plan", [TUnknown], TPlan, 0);
		// Discovery-process primitives (pipeline construct): folds/embargo are
		// the walk-forward protocol, not strategy backtest params; the promote
		// predicate's single arg is the aggregate OOS metrics object.
		fun("walkforward", [TScalar, TScalar], TPlan, 1);
		fun("promote", [TUnknown], TPlan, 1);
		fun("ensemble", [TUnknown, TScalar], TModel, 0);
		fun("DecisionTreeEnsemble", [TUnknown, TScalar], TModel, 0);
		// Generic externally-fed feature-tape slot: `feature("any:key")`, TFeature. Any more
		// specific vocabulary built on top of this (typed model/tree/graph-derived feature
		// combinators) is an out-of-tree concern registered via BuiltinSigs.register() — see
		// e.g. the Kestrel package, which is exactly such a consumer, not part of core.
		fun("feature", [TString], TFeature);
		// Graph is an opaque JSON-safe object at runtime; result containers are typed
		// enough for checker/editor legality without exposing structural fields yet.
		fun("graph_neighbors", [TGraph, TString, TString, TScalar], TStringArray, 2);
		fun("graph_degree", [TGraph, TString, TString], TScalar, 2);
		fun("graph_has_edge", [TGraph, TString, TString, TString], TBool, 3);
		fun("graph_bfs", [TGraph, TString, TScalar, TScalar], TStringArray, 2);
		fun("graph_reachable", [TGraph, TString, TString, TScalar, TScalar], TBool, 3);
		// Runtime shape `{nodes: StringArray, distance: Scalar}` — typed as TObject so
		// `path.distance` / `path.nodes` field access is checked (TGraphPath alias kept
		// for parseName / editors; canAssign via Unknown-adjacent paths still works).
		fun("graph_shortest_path", [TGraph, TString, TString, TBool, TScalar], TObject([
			{name: "nodes", ty: TStringArray},
			{name: "distance", ty: TScalar}
		]), 3);
		fun("graph_pagerank", [TGraph, TScalar, TScalar, TScalar], TGraphRanks, 1);
		// Probability-cloud query surface (probcloud_*) is Kestrel's, registered externally via
		// BuiltinSigs.register() when that package is present — not part of core.
		// Opaque Dict / Set bookkeeping (string keys / string identity).
		fun("dict_new", [], TDict);
		// Keys are coerced with Std.string at runtime — accept any key type.
		fun("dict_set", [TDict, TUnknown, TUnknown], TDict);
		fun("dict_get", [TDict, TUnknown, TUnknown], TUnknown, 2);
		fun("dict_has", [TDict, TUnknown], TBool);
		fun("dict_delete", [TDict, TUnknown], TBool);
		fun("dict_keys", [TDict], TStringArray);
		// Values are `Array<Dynamic>` at runtime, not guaranteed numeric.
		fun("dict_values", [TDict], TUnknown);
		fun("dict_size", [TDict], TScalar);
		fun("set_new", [], TSet);
		fun("set_add", [TSet, TUnknown], TSet);
		fun("set_has", [TSet, TUnknown], TBool);
		fun("set_remove", [TSet, TUnknown], TBool);
		fun("set_size", [TSet], TScalar);
		fun("set_union", [TSet, TSet], TSet);
		fun("set_intersect", [TSet, TSet], TSet);
		fun("set_difference", [TSet, TSet], TSet);
		fun("set_to_vector", [TSet], TVector);
		fun("set_jaccard", [TSet, TSet], TScalar);
	}

	static var extraPaletteOnly:Map<String, Bool> = new Map();

	/** Out-of-tree packages mark their own palette-only names here instead of core hardcoding
	 * them (see register() above for the matching typed-signature counterpart). */
	public static function markPaletteOnly(name:String):Void {
		extraPaletteOnly.set(name, true);
	}

	/**
	 * Palette / planner-only names that are intentionally not TradeBuiltins
	 * installables (feature/model stubs, or MacroBuiltins-only markers).
	 */
	public static function isPaletteOnly(name:String):Bool {
		if (extraPaletteOnly.exists(name)) return true;
		return switch (name) {
			case "feature":
				true;
			default:
				false;
		};
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
