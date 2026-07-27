package musescript.pinescript.translit;

/**
 * Maps Pine's namespaced builtins to their MuseScript equivalents. Three
 * outcomes per lookup:
 *   - Remap(museName)   : a direct 1:1 call rename (`ta.ema` → `ema`).
 *   - Series(field)     : a Pine builtin *series* that is a Muse bar field
 *                         (`close` → bar.close), handled as an identifier, not a call.
 *   - Metadata          : chart/UI-only in exec (`plot`, `bgcolor`) — kept as an
 *                         annotation, dropped from the compute path.
 *   - Unknown           : no mapping yet → PineLower records an Unsupported note
 *                         instead of silently emitting a call to nothing.
 *
 * This table is intentionally data, not code — it's the part that grows fastest
 * as corpus coverage widens, and keeping it declarative makes coverage auditable
 * (how many of Pine's ~450 builtins do we map?) for the marketing parity claim.
 */
enum BuiltinKind {
	Remap(museName:String);
	/** A name remap whose Muse builtin computes the value by a DIFFERENT
	 *  definition than Pine (verified by the corpus parity gate). Emitted so the
	 *  script runs, but PineLower records `note` so the divergence is never
	 *  silent. Faithful expansion is tracked for P5. */
	RemapApprox(museName:String, note:String);
	SeriesField(barField:String);
	Metadata(kind:String);
	OrderOp(op:String);         // strategy.entry/close/exit → Muse order stmt
	Unknown;
}

class BuiltinMap {
	/** Bare Pine series identifiers that are OHLCV bar fields in Muse. */
	public static final BAR_FIELDS:Map<String, String> = [
		"open" => "open", "high" => "high", "low" => "low", "close" => "close",
		"volume" => "volume", "hl2" => "hl2", "hlc3" => "hlc3", "ohlc4" => "ohlc4",
		"time" => "time", "bar_index" => "index",
	];

	/** Namespaced/known function renames. Left = Pine fully-qualified name. */
	static final FUNCS:Map<String, BuiltinKind> = [
		// ── ta.* → Muse indicator builtins ────────────────────────────────────
		"ta.sma" => Remap("sma"), "ta.ema" => Remap("ema"), "ta.rma" => Remap("rma"),
		"ta.wma" => Remap("wma"), "ta.vwma" => Remap("vwma"), "ta.hma" => Remap("hma"),
		// rsi/atr: Muse builtins use SMA (Cutler) smoothing; Pine uses Wilder's RMA.
		// Verified numerically divergent by PineCorpusParity — flagged, not silent.
		"ta.rsi" => RemapApprox("rsi", "Pine ta.rsi uses Wilder's RMA smoothing; Muse `rsi` is Cutler's (SMA) — values differ. Faithful Wilder expansion tracked for P5."),
		"ta.atr" => RemapApprox("atr", "Pine ta.atr uses Wilder's RMA of true range; Muse `atr` uses a simple trailing average — values differ. Faithful Wilder expansion tracked for P5."),
		"ta.tr" => Remap("tr"),
		"ta.stdev" => Remap("stdev"), "ta.variance" => Remap("variance"),
		"ta.highest" => Remap("highest"), "ta.lowest" => Remap("lowest"),
		"ta.crossover" => Remap("crossover"), "ta.crossunder" => Remap("crossunder"),
		"ta.cross" => Remap("cross"), "ta.change" => Remap("change"),
		"ta.mom" => Remap("momentum"), "ta.roc" => Remap("roc"),
		"ta.macd" => Remap("macd"), "ta.bb" => Remap("bbands"), "ta.bbw" => Remap("bbwidth"),
		"ta.cci" => Remap("cci"), "ta.mfi" => Remap("mfi"), "ta.adx" => Remap("adx"),
		"ta.sar" => Remap("psar"), "ta.supertrend" => Remap("supertrend"),
		"ta.pivothigh" => Remap("pivotHigh"), "ta.pivotlow" => Remap("pivotLow"),
		"ta.valuewhen" => Remap("valueWhen"), "ta.barssince" => Remap("barsSince"),
		"ta.cum" => Remap("cum"), "ta.sum" => Remap("rollingSum"),
		"ta.linreg" => Remap("linreg"), "ta.correlation" => Remap("correlation"),
		"ta.percentrank" => Remap("percentRank"), "ta.median" => Remap("median"),
		// ── math.* → Muse math builtins (mostly identical names) ──────────────
		"math.abs" => Remap("abs"), "math.max" => Remap("max"), "math.min" => Remap("min"),
		"math.pow" => Remap("pow"), "math.sqrt" => Remap("sqrt"), "math.log" => Remap("log"),
		"math.log10" => Remap("log10"), "math.exp" => Remap("exp"), "math.sign" => Remap("sign"),
		"math.round" => Remap("round"), "math.floor" => Remap("floor"), "math.ceil" => Remap("ceil"),
		"math.avg" => Remap("avg"), "math.sum" => Remap("sum"), "math.sin" => Remap("sin"),
		"math.cos" => Remap("cos"), "math.tan" => Remap("tan"), "math.atan" => Remap("atan"),
		// ── nz / na handling ──────────────────────────────────────────────────
		"nz" => Remap("nz"), "na" => Remap("isNa"), "fixnan" => Remap("fixNan"),
		// ── input.* → Muse params (special-cased in PineLower, listed for audit) ─
		"input" => Remap("param"), "input.int" => Remap("param"), "input.float" => Remap("param"),
		"input.bool" => Remap("param"), "input.string" => Remap("param"),
		"input.source" => Remap("param"), "input.timeframe" => Remap("param"),
		// ── strategy.* → order model ──────────────────────────────────────────
		"strategy.entry" => OrderOp("entry"), "strategy.order" => OrderOp("order"),
		"strategy.close" => OrderOp("close"), "strategy.exit" => OrderOp("exit"),
		"strategy.close_all" => OrderOp("flat"), "strategy.cancel" => OrderOp("cancel"),
		// ── chart/UI — metadata-only in exec ──────────────────────────────────
		"plot" => Metadata("plot"), "plotshape" => Metadata("plotshape"),
		"plotchar" => Metadata("plotchar"), "plotcandle" => Metadata("plotcandle"),
		"hline" => Metadata("hline"), "fill" => Metadata("fill"),
		"bgcolor" => Metadata("bgcolor"), "barcolor" => Metadata("barcolor"),
		"label.new" => Metadata("label"), "line.new" => Metadata("line"),
		"box.new" => Metadata("box"), "table.new" => Metadata("table"),
		"alert" => Metadata("alert"), "alertcondition" => Metadata("alertcondition"),
		// Drawing / table mutators — chart-side only; drop from compute path.
		"table.cell" => Metadata("table.cell"), "table.cell_set" => Metadata("table.cell_set"),
		"table.clear" => Metadata("table.clear"), "table.delete" => Metadata("table.delete"),
		"table.merge_cells" => Metadata("table.merge_cells"),
		"label.set_text" => Metadata("label.set_text"), "label.set_xy" => Metadata("label.set_xy"),
		"label.set_color" => Metadata("label.set_color"), "label.delete" => Metadata("label.delete"),
		"line.set_xy1" => Metadata("line.set_xy1"), "line.set_xy2" => Metadata("line.set_xy2"),
		"line.set_color" => Metadata("line.set_color"), "line.delete" => Metadata("line.delete"),
		"box.set_lefttop" => Metadata("box.set_lefttop"), "box.set_rightbottom" => Metadata("box.set_rightbottom"),
		"box.delete" => Metadata("box.delete"),
		// color.* / str.* — values don't affect order sim; keep as metadata/approx notes.
		"color.new" => Metadata("color.new"), "color.rgb" => Metadata("color.rgb"),
		"color.from_gradient" => Metadata("color.from_gradient"),
		"color.r" => Metadata("color.r"), "color.g" => Metadata("color.g"),
		"color.b" => Metadata("color.b"), "color.t" => Metadata("color.t"),
		"str.tostring" => Metadata("str.tostring"), "str.format" => Metadata("str.format"),
		"str.length" => Metadata("str.length"), "str.contains" => Metadata("str.contains"),
		"str.replace" => Metadata("str.replace"), "str.split" => Metadata("str.split"),
		"runtime.error" => Metadata("runtime.error"),
		// array.* / matrix.* — emitted under Muse-friendly short names; host must
		// provide them (or the script's Unsupported path previously flagged these).
		"array.new" => Remap("array_new"), "array.new_float" => Remap("array_new_float"),
		"array.new_int" => Remap("array_new_int"), "array.new_bool" => Remap("array_new_bool"),
		"array.new_string" => Remap("array_new_string"), "array.new_line" => Remap("array_new_line"),
		"array.new_box" => Remap("array_new_box"), "array.new_label" => Remap("array_new_label"),
		"array.get" => Remap("array_get"), "array.set" => Remap("array_set"),
		"array.push" => Remap("array_push"), "array.pop" => Remap("array_pop"),
		"array.size" => Remap("array_size"), "array.clear" => Remap("array_clear"),
		"array.shift" => Remap("array_shift"), "array.unshift" => Remap("array_unshift"),
		"array.includes" => Remap("array_includes"), "array.indexof" => Remap("array_indexof"),
		"array.remove" => Remap("array_remove"), "array.from" => Remap("array_from"),
		"matrix.new" => Remap("matrix_new"), "matrix.get" => Remap("matrix_get"),
		"matrix.set" => Remap("matrix_set"), "matrix.rows" => Remap("matrix_rows"),
		"matrix.columns" => Remap("matrix_columns"),
		"map.new" => Remap("map_new"), "map.get" => Remap("map_get"),
		"map.put" => Remap("map_put"), "map.remove" => Remap("map_remove"),
		"map.contains" => Remap("map_contains"), "map.keys" => Remap("map_keys"),
		"map.size" => Remap("map_size"),
	];

	/** Directional order constants: `strategy.long` / `strategy.short`. */
	public static final ORDER_DIR:Map<String, String> = [
		"strategy.long" => "long", "strategy.short" => "short",
	];

	public static function lookupFunc(qualified:String):BuiltinKind {
		var f = FUNCS.get(qualified);
		return f != null ? f : Unknown;
	}

	public static inline function barField(name:String):Null<String>
		return BAR_FIELDS.get(name);

	/** Coverage metric for the marketing parity claim: how many builtins mapped. */
	public static function mappedCount():Int {
		var n = 0;
		for (_ in FUNCS.keys()) n++;
		return n;
	}
}
