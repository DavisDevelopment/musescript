package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.OrderKind;
import musescript.builtins.MlBuiltins;
import musescript.builtins.StatsBuiltins;

/**
 * Emit on-bar strategies as WAT with exported linear memory.
 *
 * Dual ABI (same module):
 *   reset(capacity) / push_bar(o,h,l,c,v,t,i) — streaming / live
 *   configure_tape(bases..., len) / on_bar(index) — preloaded tape
 *
 * Host ABI retained for side effects only:
 *   get_param(i32)->f64, long/short(f64), flat(), plot/plotshape/hline/bgcolor
 *
 * Indicators, OHLCV lookbacks, and cross/rising/falling state are internalized.
 */
class StrategyWasmEmitter {
	var locals:Map<String, String> = new Map();
	var localOrder:Array<String> = [];
	var imports:Map<String, String> = new Map();
	var strings:Array<String> = [];
	var featureKeys:Array<String> = [];
	var nextTmp:Int = 0;
	var nextCrossSlot:Int = 0;
	var nextRiseSlot:Int = 0;
	var scratchCursor:Int = 0;
	var usedIndicators:Map<String, Bool> = new Map();

	public function new() {}

	public function emitOnBar(prog:MuseProgram):Null<{wat:String, strings:Array<String>}> {
		var stmts = collectOnBar(prog);
		if (stmts.length == 0) return null;
		try {
			locals = new Map();
			localOrder = [];
			imports = new Map();
			strings = [];
			featureKeys = [];
			nextTmp = 0;
			nextCrossSlot = 0;
			nextRiseSlot = 0;
			scratchCursor = StrategyWasmRuntimeWat.VEC_SCRATCH_BASE;
			usedIndicators = new Map();

			var body = [for (s in stmts) emitStmt(s)].join("\n    ");
			var localDecls = [for (n in localOrder)
				"(local $" + n + " " + locals.get(n) + ")"
			].join("\n    ");

			var importLines = [for (nm in imports.keys())
				'(import "env" "' + nm + '" (func $' + nm + ' ' + imports.get(nm) + '))'
			];

			var helpers = StrategyWasmRuntimeWat.helpers(nextCrossSlot, nextRiseSlot);

			var strategyFunc = '
  (func $$run_strategy
    ' + localDecls + '
    ' + body + '
  )

  (func $$push_bar
      (param $$o f64) (param $$h f64) (param $$l f64) (param $$c f64)
      (param $$v f64) (param $$t f64) (param $$i f64)
    (local $$idx i32)
    (local.set $$idx (global.get $$bar_count))
    (if (i32.ge_s (local.get $$idx) (global.get $$capacity))
      (then
        (call $$layout_streaming
          (i32.add (i32.mul (global.get $$capacity) (i32.const 2)) (i32.const 1)))))
    (call $$store_bar (local.get $$idx)
      (local.get $$o) (local.get $$h) (local.get $$l) (local.get $$c)
      (local.get $$v) (local.get $$t) (local.get $$i))
    (call $$set_curs
      (local.get $$o) (local.get $$h) (local.get $$l) (local.get $$c)
      (local.get $$v) (local.get $$t) (local.get $$i))
    (global.set $$bar_count (i32.add (local.get $$idx) (i32.const 1)))
    (call $$run_strategy)
  )
  (export "push_bar" (func $$push_bar))

  (func $$on_bar (param $$idx i32)
    (local $$o f64) (local $$h f64) (local $$l f64) (local $$c f64)
    (local $$v f64) (local $$t f64) (local $$iv f64)
    (if (i32.or (i32.lt_s (local.get $$idx) (i32.const 0))
          (i32.ge_s (local.get $$idx) (global.get $$capacity)))
      (then (return)))
    (local.set $$o (f64.load (i32.add (global.get $$open_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$h (f64.load (i32.add (global.get $$high_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$l (f64.load (i32.add (global.get $$low_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$c (f64.load (i32.add (global.get $$close_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$v (f64.load (i32.add (global.get $$volume_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$t (f64.load (i32.add (global.get $$time_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$iv (f64.load (i32.add (global.get $$index_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (call $$set_curs (local.get $$o) (local.get $$h) (local.get $$l) (local.get $$c)
      (local.get $$v) (local.get $$t) (local.get $$iv))
    (global.set $$bar_count (i32.add (local.get $$idx) (i32.const 1)))
    (call $$run_strategy)
  )
  (export "on_bar" (func $$on_bar))
';


			var wat = "(module\n"
				+ importLines.join("\n") + (importLines.length > 0 ? "\n" : "")
				+ "  (memory (export \"memory\") 1)\n"
				+ helpers
				+ strategyFunc
				+ ")\n";
			return { wat: wat, strings: strings.copy() };
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	function collectOnBar(prog:MuseProgram):Array<Stmt> {
		var out:Array<Stmt> = [];
		function walk(ss:Array<Stmt>) {
			for (s in ss) switch (s) {
				case OnBar(body): out = out.concat(body);
				case Block(body): walk(body);
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body):
				var prelude:Array<Stmt> = [];
				var onBarBody:Array<Stmt> = [];
				for (s in body) switch (s) {
					case Assign(_, _):
						prelude.push(s);
					case OnBar(onBody):
						onBarBody = onBarBody.concat(onBody);
					case Block(block):
						for (nested in block) switch (nested) {
							case Assign(_, _): prelude.push(nested);
							case OnBar(onBody): onBarBody = onBarBody.concat(onBody);
							default:
						}
					default:
				}
				if (onBarBody.length > 0)
					out = out.concat(prelude).concat(onBarBody);
			default:
		}
		walk(prog.stmts);
		return out;
	}

	function ensureLocal(name:String, ty:String = "f64"):Void {
		if (!locals.exists(name)) {
			locals.set(name, ty);
			localOrder.push(name);
		}
	}

	function strId(s:String):Int {
		var i = strings.indexOf(s);
		if (i >= 0) return i;
		strings.push(s);
		return strings.length - 1;
	}

	function needImport(name:String, sig:String):Void {
		if (!imports.exists(name)) imports.set(name, sig);
	}

	function seriesSid(name:String):Null<Int> {
		return switch (name) {
			case "open": 0;
			case "high": 1;
			case "low": 2;
			case "close": 3;
			case "volume": 4;
			case "time": 5;
			case "index" | "bar_index": 6;
			default: null;
		};
	}

	function emitStmt(s:Stmt):String {
		return switch (s) {
			case ExprStmt(e):
				emitValue(e) + "\n    drop";
			case Assign(name, e):
				ensureLocal(name);
				emitValue(e) + "\n    local.set $" + name;
			case Block(ss):
				[for (x in ss) emitStmt(x)].join("\n    ");
			case Return(e):
				e != null ? emitValue(e) + "\n    drop" : "";
			case Order(kind, args):
				switch (kind) {
					case Long:
						needImport("long", "(param f64)");
						(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $long";
					case Short:
						needImport("short", "(param f64)");
						(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $short";
					case Flat | Close:
						needImport("flat", "");
						"call $flat";
				}
			case OnBar(_) | OnTick(_) | OnEvent(_, _) | MatchFor(_, _, _) | ForIn(_, _, _) | Yield(_) | YieldStar(_) | Use(_, _):
				throw new EmitUnsupported();
			case When(cond, body):
				asI32Cond(cond) + "\n    if\n      " + [for (x in body) emitStmt(x)].join("\n      ") + "\n    end";
		};
	}

	function emitValue(e:Expr):String {
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): "f64.const " + i;
					case CFloat(f): "f64.const " + f;
					case CBool(b): b ? "i32.const 1" : "i32.const 0";
					case CNull: "f64.const 0";
					case CString(_): throw new EmitUnsupported();
				}
			case EIdent(n):
				if (locals.exists(n)) {
					"local.get $" + n;
				} else {
					var sid = seriesSid(n);
					if (sid != null) {
						"global.get $" + "cur_" + seriesCurName(sid);
					} else {
						needImport("get_param", "(param i32) (result f64)");
						"i32.const " + strId(n) + "\n    call $get_param";
					}
				}
			case EBarField(n):
				var sid = seriesSid(n);
				if (sid == null) throw new EmitUnsupported();
				"global.get $" + "cur_" + seriesCurName(sid);
			case EVar(n, init):
				ensureLocal(n);
				if (init == null) return "f64.const 0\n    local.set $" + n + "\n    local.get $" + n;
				emitValue(init) + "\n    local.set $" + n + "\n    local.get $" + n;
			case EBinop("=", EIdent(n), v):
				ensureLocal(n);
				emitValue(v) + "\n    local.set $" + n + "\n    local.get $" + n;
			case EBinop(op, a, b):
				emitBinop(op, a, b);
			case EUnop("-", true, x):
				"f64.const 0\n    " + coerceF64(x) + "\n    f64.sub";
			case EUnop("!", true, x):
				asI32Cond(x) + "\n    i32.eqz";
			case EIf(c, a, b):
				asI32Cond(c) + "\n    if (result f64)\n      " + coerceF64(a)
					+ "\n    else\n      " + (b != null ? coerceF64(b) : "f64.const 0") + "\n    end";
			case ETernary(c, a, b):
				emitValue(EIf(c, a, b));
			case EWhile(c, body):
				var br = "br_" + (nextTmp++);
				var ct = "ct_" + (nextTmp++);
				"block $" + br + "\n      loop $" + ct + "\n        " + asI32Cond(c)
					+ "\n        i32.eqz\n        br_if $" + br + "\n        " + emitValue(body)
					+ "\n        drop\n        br $" + ct + "\n      end\n    end\n    f64.const 0";
			case ECall(callee, args):
				emitCall(callee, args);
			case EParent(x): emitValue(x);
			case EBlock(es):
				if (es.length == 0) return "f64.const 0";
				var parts = [for (i in 0...es.length - 1) emitValue(es[i]) + "\n    drop"];
				parts.push(emitValue(es[es.length - 1]));
				parts.join("\n    ");
			case EMeta(_, _, x): emitValue(x);
			case ELookback(series, n):
				emitLookback(series, n);
			case EArray(_, _):
				throw new EmitUnsupported();
			default:
				throw new EmitUnsupported();
		};
	}

	function seriesCurName(sid:Int):String {
		return switch (sid) {
			case 0: "open";
			case 1: "high";
			case 2: "low";
			case 3: "close";
			case 4: "volume";
			case 5: "time";
			default: "index";
		};
	}

	function emitLookback(series:Expr, n:Expr):String {
		return switch (series) {
			case EParent(inner):
				emitLookback(inner, n);
			case EBarField(name) | EIdent(name):
				var sid = seriesSid(name);
				if (sid == null) throw new EmitUnsupported();
				"i32.const " + sid + "\n    " + asI32(n) + "\n    call $lookback_ohlcv";
			case EConst(CString(s)):
				var sid = seriesSid(s);
				if (sid == null) throw new EmitUnsupported();
				"i32.const " + sid + "\n    " + asI32(n) + "\n    call $lookback_ohlcv";
			default:
				throw new EmitUnsupported();
		};
	}

	function seriesArgSid(e:Expr):Int {
		return switch (e) {
			case EConst(CString(s)):
				var sid = seriesSid(s);
				if (sid == null) throw new EmitUnsupported();
				sid;
			case EBarField(n) | EIdent(n):
				var sid = seriesSid(n);
				if (sid == null) throw new EmitUnsupported();
				sid;
			default: throw new EmitUnsupported();
		};
	}

	function emitCall(callee:Expr, args:Array<Expr>):String {
		var name = switch (callee) {
			case EIdent(n): n;
			case EField(EIdent("Math"), f): f;
			default: throw new EmitUnsupported();
		};
		return switch (name) {
			case "long":
				needImport("long", "(param f64)");
				(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $long\n    f64.const 0";
			case "short":
				needImport("short", "(param f64)");
				(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $short\n    f64.const 0";
			case "flat" | "close":
				needImport("flat", "");
				"call $flat\n    f64.const 0";
			case "sma" | "ema" | "rsi" | "atr" | "highest" | "lowest" | "change" | "pct_change"
			   | "mom" | "roc" | "stdev" | "wma" | "rma":
				usedIndicators.set(name, true);
				var series = args.length > 0 ? seriesArgSid(args[0]) : 3;
				var len = args.length > 1 ? asI32(args[1]) : "i32.const 14";
				"i32.const " + series + "\n    " + len + "\n    call $" + name;
			case "vwap":
				usedIndicators.set(name, true);
				"call $vwap";
			case "feature" | "model_score":
				if (args.length < 1) throw new EmitUnsupported();
				"i32.const " + featureSlot(stringKey(args[0])) + "\n    call $feature_at";
			case "tree_value":
				if (args.length < 1) throw new EmitUnsupported();
				"i32.const " + featureSlot("tree:" + stringKey(args[0]) + ":value") + "\n    call $feature_at";
			case "tree_bit":
				if (args.length < 2) throw new EmitUnsupported();
				"i32.const " + featureSlot("tree:" + stringKey(args[0]) + ":" + constIntKey(args[1])) + "\n    call $feature_at";
			case "graph_metric":
				if (args.length < 2) throw new EmitUnsupported();
				"i32.const " + featureSlot("graph:" + stringKey(args[0]) + ":" + stringKey(args[1])) + "\n    call $feature_at";
			case "hl2":
				"global.get $" + "cur_high\n    global.get $" + "cur_low\n    f64.add\n    f64.const 2\n    f64.div";
			case "hlc3":
				"global.get $" + "cur_high\n    global.get $" + "cur_low\n    f64.add\n    global.get $" + "cur_close\n    f64.add"
					+ "\n    f64.const 3\n    f64.div";
			case "ohlc4":
				"global.get $" + "cur_open\n    global.get $" + "cur_high\n    f64.add\n    global.get $" + "cur_low\n    f64.add"
					+ "\n    global.get $" + "cur_close\n    f64.add\n    f64.const 4\n    f64.div";
			case "clamp":
				if (args.length < 3) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[2]) + "\n    f64.min\n    "
					+ coerceF64(args[1]) + "\n    f64.max";
			case "abs":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.abs";
			case "sqrt":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.sqrt";
			case "floor":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.floor";
			case "ceil":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.ceil";
			case "round":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.nearest";
			case "min":
				if (args.length < 2) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.min";
			case "max":
				if (args.length < 2) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.max";
			case "nz":
				if (args.length < 1) throw new EmitUnsupported();
				var tx = "_nz_" + (nextTmp++);
				ensureLocal(tx);
				var repl = args.length > 1 ? coerceF64(args[1]) : "f64.const 0";
				coerceF64(args[0]) + "\n    local.set $" + tx
					+ "\n    local.get $" + tx
					+ "\n    " + repl
					+ "\n    local.get $" + tx + "\n    local.get $" + tx
					+ "\n    f64.eq\n    select";
			case "na":
				if (args.length < 1) throw new EmitUnsupported();
				var tx = "_na_" + (nextTmp++);
				ensureLocal(tx);
				coerceF64(args[0]) + "\n    local.set $" + tx
					+ "\n    f64.const 1\n    f64.const 0"
					+ "\n    local.get $" + tx + "\n    local.get $" + tx
					+ "\n    f64.ne\n    select";
			case "crossover" | "crossunder":
				var slot = nextCrossSlot++;
				"i32.const " + slot + "\n    " + coerceF64(args[0]) + "\n    " + coerceF64(args[1])
					+ "\n    call $" + name + "\n    f64.convert_i32_s";
			case "plot":
				needImport("plot", "(param f64 i32)");
				var label = args.length > 1 ? seriesStrId(args[1]) : strId("plot");
				coerceF64(args[0]) + "\n    i32.const " + label + "\n    call $plot\n    f64.const 0";
			case "plotshape":
				needImport("plotshape", "(param i32)");
				var shape = args.length > 0 ? seriesStrId(args[0]) : strId("shape");
				"i32.const " + shape + "\n    call $plotshape\n    f64.const 0";
			case "hline":
				needImport("hline", "(param f64 i32)");
				var hlab = args.length > 1 ? seriesStrId(args[1]) : strId("hline");
				coerceF64(args[0]) + "\n    i32.const " + hlab + "\n    call $hline\n    f64.const 0";
			case "bgcolor":
				needImport("bgcolor", "(param i32)");
				var col = args.length > 0 ? seriesStrId(args[0]) : strId("bg");
				"i32.const " + col + "\n    call $bgcolor\n    f64.const 0";
			case "rising" | "falling":
				var rslot = nextRiseSlot++;
				var xn = args.length > 1 ? asI32(args[1]) : "i32.const 1";
				"i32.const " + rslot + "\n    " + coerceF64(args[0]) + "\n    " + xn
					+ "\n    call $" + name + "\n    f64.convert_i32_s";
			case "ml_dot":
				emitMlPairOrFold(args, "vec_dot", function(xs, ys) return MlBuiltins.dot(xs, ys));
			case "ml_mse":
				emitMlPairOrFold(args, "vec_mse", function(xs, ys) return MlBuiltins.mse(xs, ys));
			case "ml_mae":
				emitMlPairOrFold(args, "vec_mae", function(xs, ys) return MlBuiltins.mae(xs, ys));
			case "ml_linear_predict":
				emitMlLinearPredict(args);
			case "stat_mean":
				emitStatWindowOrLiteral(args, "stat_window_mean", "vec_mean", null, function(xs) return StatsBuiltins.mean(xs));
			case "stat_median":
				if (args.length < 1) throw new EmitUnsupported();
				"f64.const " + watFloat(StatsBuiltins.median(constVector(args[0])));
			case "stat_variance":
				emitStatWindowOrLiteral(args, "stat_window_var", "vec_var", 0, function(xs) return StatsBuiltins.variance(xs));
			case "stat_sample_variance":
				emitStatWindowOrLiteral(args, "stat_window_var", "vec_var", 1, function(xs) return StatsBuiltins.sampleVariance(xs));
			case "stat_stddev":
				emitStatWindowOrLiteral(args, "stat_window_stdev", "vec_stdev", 0, function(xs) return StatsBuiltins.standardDeviation(xs));
			case "stat_sample_stddev":
				emitStatWindowOrLiteral(args, "stat_window_stdev", "vec_stdev", 1, function(xs) return StatsBuiltins.sampleStandardDeviation(xs));
			case "stat_quantile":
				if (args.length < 2) throw new EmitUnsupported();
				"f64.const " + watFloat(StatsBuiltins.quantile(constVector(args[0]), constNumber(args[1])));
			case "stat_covariance":
				emitStatWindowPairOrLiteral(args, "stat_window_cov", "vec_cov", function(xs, ys) return StatsBuiltins.covariance(xs, ys));
			case "stat_correlation":
				emitStatWindowPairOrLiteral(args, "stat_window_corr", "vec_corr", function(xs, ys) return StatsBuiltins.pearson(xs, ys));
			case "stat_skewness":
				if (args.length < 1) throw new EmitUnsupported();
				"f64.const " + watFloat(StatsBuiltins.skewness(constVector(args[0])));
			// Dynamic graph objects/results have no Strategy-WASM ABI yet. Refuse
			// emission explicitly so MuseCompiler selects its documented host fallback.
			case "graph_neighbors" | "graph_degree" | "graph_has_edge" | "graph_bfs"
			   | "graph_reachable" | "graph_shortest_path" | "graph_pagerank":
				throw new EmitUnsupported();
			default:
				throw new EmitUnsupported();
		};
	}

	function seriesStrId(e:Expr):Int {
		return switch (e) {
			case EConst(CString(s)): strId(s);
			case EBarField(n) | EIdent(n): strId(n);
			default: strId("close");
		};
	}

	function featureSlot(key:String):Int {
		var i = featureKeys.indexOf(key);
		if (i >= 0) return i;
		featureKeys.push(key);
		strId("kestrel:" + key); // sidecar metadata only; not the dense feature id
		return featureKeys.length - 1;
	}

	function stringKey(e:Expr):String {
		return switch (e) {
			case EConst(CString(s)): s;
			case EIdent(n) | EBarField(n): n;
			case EParent(inner): stringKey(inner);
			default: throw new EmitUnsupported();
		};
	}

	function constIntKey(e:Expr):Int {
		return switch (e) {
			case EConst(CInt(i)): i;
			case EConst(CFloat(f)): Std.int(f);
			case EParent(inner): constIntKey(inner);
			default: throw new EmitUnsupported();
		};
	}

	function constVector(e:Expr):Array<Float> {
		return switch (e) {
			case EParent(inner):
				constVector(inner);
			case EArrayDecl(values):
				[for (value in values) constNumber(value)];
			default:
				throw new EmitUnsupported();
		};
	}

	function constNumber(e:Expr):Float {
		return switch (e) {
			case EConst(CInt(i)): i;
			case EConst(CFloat(f)): f;
			case EUnop("-", true, inner): -constNumber(inner);
			case EParent(inner): constNumber(inner);
			default: throw new EmitUnsupported();
		};
	}

	static function watFloat(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		if (v == Math.POSITIVE_INFINITY) return "inf";
		if (v == Math.NEGATIVE_INFINITY) return "-inf";
		return Std.string(v);
	}

	/**
	 * Pattern-match `window(series, n)` so scalar stats can run over series tapes
	 * without materializing dynamic vectors.
	 */
	function asWindowArg(e:Expr):Null<{sid:Int, lenExpr:String, lenConst:Null<Int>}> {
		return switch (e) {
			case EParent(inner):
				asWindowArg(inner);
			case ECall(EIdent("window"), wargs) if (wargs.length >= 2):
				var lenConst:Null<Int> = null;
				try lenConst = constIntKey(wargs[1]) catch (_:EmitUnsupported) {}
				{
					sid: seriesArgSid(wargs[0]),
					lenExpr: asI32(wargs[1]),
					lenConst: lenConst
				};
			default:
				null;
		};
	}

	function allocScratch(len:Int):Int {
		if (len <= 0) throw new EmitUnsupported();
		var bytes = len * 8;
		var limit = StrategyWasmRuntimeWat.VEC_SCRATCH_BASE + StrategyWasmRuntimeWat.VEC_SCRATCH_BYTES;
		if (scratchCursor + bytes > limit) throw new EmitUnsupported();
		var base = scratchCursor;
		scratchCursor += bytes;
		return base;
	}

	function tryConstVector(e:Expr):Null<Array<Float>> {
		try {
			return constVector(e);
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	/** Spill an array literal (const or scalar runtime elems) into scratch. */
	function spillArrayDecl(values:Array<Expr>):{prelude:String, baseExpr:String, lenExpr:String} {
		var base = allocScratch(values.length);
		var parts:Array<String> = [];
		for (i in 0...values.length) {
			parts.push(coerceF64(values[i]) + "\n    i32.const " + (base + i * 8) + "\n    f64.store");
		}
		return {
			prelude: parts.join("\n    "),
			baseExpr: "i32.const " + base,
			lenExpr: "i32.const " + values.length
		};
	}

	/** Copy a fixed-length window into scratch; length may shrink when history is short. */
	function spillWindow(window:{sid:Int, lenExpr:String, lenConst:Null<Int>}):{prelude:String, baseExpr:String, lenExpr:String} {
		if (window.lenConst == null) throw new EmitUnsupported();
		var base = allocScratch(window.lenConst);
		var lenLocal = "_vlen_" + (nextTmp++);
		ensureLocal(lenLocal, "i32");
		var prelude = "i32.const " + window.sid + "\n    " + window.lenExpr
			+ "\n    i32.const " + base + "\n    call $window_to_scratch\n    local.set $" + lenLocal;
		return {
			prelude: prelude,
			baseExpr: "i32.const " + base,
			lenExpr: "local.get $" + lenLocal
		};
	}

	function lowerVecOperand(e:Expr):{prelude:String, baseExpr:String, lenExpr:String} {
		return switch (e) {
			case EParent(inner):
				lowerVecOperand(inner);
			case EArrayDecl(values):
				spillArrayDecl(values);
			default:
				var window = asWindowArg(e);
				if (window == null) throw new EmitUnsupported();
				spillWindow(window);
		};
	}

	function emitMlPairOrFold(
		args:Array<Expr>,
		helper:String,
		fold:Array<Float>->Array<Float>->Float
	):String {
		if (args.length < 2) throw new EmitUnsupported();
		var leftConst = tryConstVector(args[0]);
		var rightConst = tryConstVector(args[1]);
		if (leftConst != null && rightConst != null)
			return "f64.const " + watFloat(fold(leftConst, rightConst));
		var left = lowerVecOperand(args[0]);
		var right = lowerVecOperand(args[1]);
		var parts:Array<String> = [];
		if (left.prelude.length > 0) parts.push(left.prelude);
		if (right.prelude.length > 0) parts.push(right.prelude);
		parts.push(left.baseExpr);
		parts.push(left.lenExpr);
		parts.push(right.baseExpr);
		parts.push(right.lenExpr);
		parts.push("call $" + helper);
		return parts.join("\n    ");
	}

	function emitMlLinearPredict(args:Array<Expr>):String {
		if (args.length < 2) throw new EmitUnsupported();
		var leftConst = tryConstVector(args[0]);
		var rightConst = tryConstVector(args[1]);
		var bias = args.length > 2 ? coerceF64(args[2]) : "f64.const 0";
		if (leftConst != null && rightConst != null) {
			var weighted = MlBuiltins.dot(leftConst, rightConst);
			return "f64.const " + watFloat(weighted) + "\n    " + bias + "\n    f64.add";
		}
		var left = lowerVecOperand(args[0]);
		var right = lowerVecOperand(args[1]);
		var parts:Array<String> = [];
		if (left.prelude.length > 0) parts.push(left.prelude);
		if (right.prelude.length > 0) parts.push(right.prelude);
		parts.push(left.baseExpr);
		parts.push(left.lenExpr);
		parts.push(right.baseExpr);
		parts.push(right.lenExpr);
		parts.push("call $vec_dot");
		parts.push(bias);
		parts.push("f64.add");
		return parts.join("\n    ");
	}

	function emitStatWindowOrLiteral(
		args:Array<Expr>,
		windowHelper:String,
		vecHelper:String,
		sampleFlag:Null<Int>,
		fold:Array<Float>->Float
	):String {
		if (args.length < 1) throw new EmitUnsupported();
		var window = asWindowArg(args[0]);
		if (window != null) {
			var out = "i32.const " + window.sid + "\n    " + window.lenExpr + "\n    ";
			if (sampleFlag != null) out += "i32.const " + sampleFlag + "\n    ";
			return out + "call $" + windowHelper;
		}
		var consts = tryConstVector(args[0]);
		if (consts != null) return "f64.const " + watFloat(fold(consts));
		var vec = lowerVecOperand(args[0]);
		var parts:Array<String> = [];
		if (vec.prelude.length > 0) parts.push(vec.prelude);
		parts.push(vec.baseExpr);
		parts.push(vec.lenExpr);
		if (sampleFlag != null) parts.push("i32.const " + sampleFlag);
		parts.push("call $" + vecHelper);
		return parts.join("\n    ");
	}

	function emitStatWindowPairOrLiteral(
		args:Array<Expr>,
		windowHelper:String,
		vecHelper:String,
		fold:Array<Float>->Array<Float>->Float
	):String {
		if (args.length < 2) throw new EmitUnsupported();
		var left = asWindowArg(args[0]);
		var right = asWindowArg(args[1]);
		if (left != null && right != null) {
			if (left.lenConst != null && right.lenConst != null && left.lenConst != right.lenConst)
				throw new EmitUnsupported();
			return "i32.const " + left.sid + "\n    i32.const " + right.sid + "\n    "
				+ left.lenExpr + "\n    call $" + windowHelper;
		}
		var leftConst = tryConstVector(args[0]);
		var rightConst = tryConstVector(args[1]);
		if (leftConst != null && rightConst != null)
			return "f64.const " + watFloat(fold(leftConst, rightConst));
		var leftVec = lowerVecOperand(args[0]);
		var rightVec = lowerVecOperand(args[1]);
		var parts:Array<String> = [];
		if (leftVec.prelude.length > 0) parts.push(leftVec.prelude);
		if (rightVec.prelude.length > 0) parts.push(rightVec.prelude);
		parts.push(leftVec.baseExpr);
		parts.push(leftVec.lenExpr);
		parts.push(rightVec.baseExpr);
		parts.push(rightVec.lenExpr);
		parts.push("call $" + vecHelper);
		return parts.join("\n    ");
	}

	function emitBinop(op:String, a:Expr, b:Expr):String {
		var cmp = ["<", ">", "<=", ">=", "==", "!="].indexOf(op) >= 0;
		if (cmp) {
			var instr = switch (op) {
				case "<": "f64.lt"; case ">": "f64.gt"; case "<=": "f64.le";
				case ">=": "f64.ge"; case "==": "f64.eq"; case "!=": "f64.ne";
				default: throw op;
			};
			return coerceF64(a) + "\n    " + coerceF64(b) + "\n    " + instr;
		}
		if (op == "&&" || op == "||") {
			var bit = op == "&&" ? "i32.and" : "i32.or";
			return asI32Cond(a) + "\n    " + asI32Cond(b) + "\n    " + bit;
		}
		if (op == "%") {
			var ta = "_mod_a_" + nextTmp;
			var tb = "_mod_b_" + (nextTmp++);
			ensureLocal(ta);
			ensureLocal(tb);
			return coerceF64(a) + "\n    local.set $" + ta
				+ "\n    " + coerceF64(b) + "\n    local.set $" + tb
				+ "\n    local.get $" + ta
				+ "\n    local.get $" + ta + "\n    local.get $" + tb
				+ "\n    f64.div\n    f64.trunc\n    local.get $" + tb
				+ "\n    f64.mul\n    f64.sub";
		}
		var instr = switch (op) {
			case "+": "f64.add"; case "-": "f64.sub"; case "*": "f64.mul"; case "/": "f64.div";
			default: throw new EmitUnsupported();
		};
		return coerceF64(a) + "\n    " + coerceF64(b) + "\n    " + instr;
	}

	function coerceF64(e:Expr):String {
		return emitValue(e);
	}

	function asI32(e:Expr):String {
		return coerceF64(e) + "\n    i32.trunc_f64_s";
	}

	function asI32Cond(e:Expr):String {
		return switch (e) {
			case EParent(x): asI32Cond(x);
			case EMeta(_, _, x): asI32Cond(x);
			case EBinop(op, _, _) if (["<", ">", "<=", ">=", "==", "!=", "&&", "||"].indexOf(op) >= 0):
				emitValue(e);
			case EUnop("!", _, _):
				emitValue(e);
			case ECall(EIdent("crossover"), _) | ECall(EIdent("crossunder"), _)
				| ECall(EIdent("rising"), _) | ECall(EIdent("falling"), _):
				emitValue(e) + "\n    i32.trunc_f64_s";
			default:
				coerceF64(e) + "\n    f64.const 0\n    f64.ne";
		};
	}
}
