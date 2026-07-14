package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.OrderKind;

/**
 * Emit a *subset* of on-bar strategy bodies as WAT.
 *
 * Supported: locals, arithmetic (+ − * / %), if/while, bar fields, params via get_param,
 * builtin calls (sma/ema/rsi/atr/vwap/hl2/hlc3/ohlc4/mom/roc/stdev/wma/rma/clamp/crossover/crossunder/plot/plotshape/hline/bgcolor/…), long/short/flat.
 * Unsupported (EmitUnsupported): match, for, yield, objects (bbands/macd/stoch), arrays,
 * call/expr lookback (sma(...)[1] etc. — never silent close).
 *
 * Host ABI (env):
 *   bar_open/high/low/close/volume/time/bar_index () -> f64
 *   get_param(name_id:i32) -> f64
 *   str_id constants are baked by the backend's string table
 *   call_<builtin>(…)  (see emitCall) — vwap () -> f64; mom/roc/stdev/wma/rma (i32 i32) -> f64
 *   plot(f64,i32) / plotshape(i32) / hline(f64,i32) / bgcolor(i32)
 *   long/short(qty:f64) / flat()
 * χρῶμα καὶ γραμμὴ καὶ σχῆμα ἐπὶ τοῦ πίνακος.
 */
class StrategyWasmEmitter {
	var locals:Map<String, String> = new Map();
	var localOrder:Array<String> = [];
	var imports:Map<String, String> = new Map(); // name -> wat import signature body
	var strings:Array<String> = [];
	var nextTmp:Int = 0;

	public function new() {}

	public function emitOnBar(prog:MuseProgram):Null<{wat:String, strings:Array<String>}> {
		var stmts = collectOnBar(prog);
		if (stmts.length == 0) return null;
		try {
			locals = new Map();
			localOrder = [];
			imports = new Map();
			strings = [];
			nextTmp = 0;
			var body = [for (s in stmts) emitStmt(s)].join("\n    ");
			var localDecls = [for (n in localOrder)
				"(local $" + n + " " + locals.get(n) + ")"
			].join("\n    ");
			var importLines = [for (nm in imports.keys())
				'(import "env" "' + nm + '" (func $' + nm + ' ' + imports.get(nm) + '))'
			];
			var wat = "(module\n" + importLines.join("\n") + "\n"
				+ "  (func $on_bar\n    " + localDecls + "\n    " + body + "\n  )\n"
				+ "  (export \"on_bar\" (func $on_bar))\n)\n";
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
			case StrategyDecl(_, body): walk(body);
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
						(args.length > 0 ? coerceF64(args[0]) : "f64.const 1") + "\n    call $long";
					case Short:
						needImport("short", "(param f64)");
						(args.length > 0 ? coerceF64(args[0]) : "f64.const 1") + "\n    call $short";
					case Flat | Close:
						needImport("flat", "");
						"call $flat";
				}
			case OnBar(_) | OnTick(_) | OnEvent(_, _) | MatchFor(_, _, _) | ForIn(_, _, _) | Yield(_) | YieldStar(_):
				throw new EmitUnsupported();
		};
	}

	function needImport(name:String, sig:String):Void {
		if (!imports.exists(name)) imports.set(name, sig);
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
					needImport("get_param", "(param i32) (result f64)");
					"i32.const " + strId(n) + "\n    call $get_param";
				}
			case EBarField(n):
				var fn = "bar_" + n;
				needImport(fn, "(result f64)");
				"call $" + fn;
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

	/**
	 * Bare series name → env.lookback(str_id, n). Call/expr bases refuse (no silent close).
	 * ἢ ῥῖψον EmitUnsupported, ἢ τίμα τὸ ὄνομα.
	 */
	function emitLookback(series:Expr, n:Expr):String {
		return switch (series) {
			case EParent(inner):
				emitLookback(inner, n);
			case EBarField(name) | EIdent(name):
				needImport("lookback", "(param i32 i32) (result f64)");
				"i32.const " + strId(name) + "\n    " + asI32(n) + "\n    call $lookback";
			case EConst(CString(s)):
				needImport("lookback", "(param i32 i32) (result f64)");
				"i32.const " + strId(s) + "\n    " + asI32(n) + "\n    call $lookback";
			default:
				throw new EmitUnsupported();
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
				(args.length > 0 ? coerceF64(args[0]) : "f64.const 1") + "\n    call $long\n    f64.const 0";
			case "short":
				needImport("short", "(param f64)");
				(args.length > 0 ? coerceF64(args[0]) : "f64.const 1") + "\n    call $short\n    f64.const 0";
			case "flat" | "close":
				needImport("flat", "");
				"call $flat\n    f64.const 0";
			case "sma" | "ema" | "rsi" | "atr" | "highest" | "lowest" | "change" | "pct_change"
			   | "mom" | "roc" | "stdev" | "wma" | "rma":
				needImport(name, "(param i32 i32) (result f64)");
				var series = args.length > 0 ? seriesStrId(args[0]) : strId("close");
				var len = args.length > 1 ? asI32(args[1]) : "i32.const 14";
				"i32.const " + series + "\n    " + len + "\n    call $" + name;
			case "vwap":
				needImport("vwap", "(result f64)");
				"call $vwap";
			case "hl2":
				// (high+low)/2 via existing bar_* — no new host. μέσον ἄκρων μία φωνή.
				needImport("bar_high", "(result f64)");
				needImport("bar_low", "(result f64)");
				"call $bar_high\n    call $bar_low\n    f64.add\n    f64.const 2\n    f64.div";
			case "hlc3":
				needImport("bar_high", "(result f64)");
				needImport("bar_low", "(result f64)");
				needImport("bar_close", "(result f64)");
				"call $bar_high\n    call $bar_low\n    f64.add\n    call $bar_close\n    f64.add"
					+ "\n    f64.const 3\n    f64.div";
			case "ohlc4":
				needImport("bar_open", "(result f64)");
				needImport("bar_high", "(result f64)");
				needImport("bar_low", "(result f64)");
				needImport("bar_close", "(result f64)");
				"call $bar_open\n    call $bar_high\n    f64.add\n    call $bar_low\n    f64.add"
					+ "\n    call $bar_close\n    f64.add\n    f64.const 4\n    f64.div";
			case "clamp":
				// max(lo, min(hi, x)) — pure opcodes, no host. κλῖνε τὸν ἀριθμὸν ἐντὸς ὅρων.
				if (args.length < 3) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[2]) + "\n    f64.min\n    "
					+ coerceF64(args[1]) + "\n    f64.max";
			/**
			 * Native f64 Math.* / bare abs·sqrt·floor·ceil·min·max — no env Math imports.
			 * ἀριθμὸς καθαρὸς ἐν σιδήρῳ ψυχρῷ.
			 */
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
			/**
			 * round(x) → f64.nearest. round περιάγει τὸ ἄπειρον εἰς τέλος ὡρισμένον.
			 */
			case "round":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.nearest";
			case "min":
				if (args.length < 2) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.min";
			case "max":
				if (args.length < 2) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.max";
			/**
			 * nz(x[, repl]): select repl when x is NaN (x != x); else x. ἄρνησις τοῦ μὴ ὄντος.
			 */
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
			/**
			 * na(x): 1.0 if NaN (x != x), else 0.0 — pure WAT, bool-as-f64.
			 * τί ἐστιν na εἰ μὴ ἡ γνῶσις τοῦ κενοῦ;
			 */
			case "na":
				if (args.length < 1) throw new EmitUnsupported();
				var tx = "_na_" + (nextTmp++);
				ensureLocal(tx);
				coerceF64(args[0]) + "\n    local.set $" + tx
					+ "\n    f64.const 1\n    f64.const 0"
					+ "\n    local.get $" + tx + "\n    local.get $" + tx
					+ "\n    f64.ne\n    select";
			case "crossover" | "crossunder":
				needImport(name, "(param f64 f64) (result i32)");
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    call $" + name
					+ "\n    f64.convert_i32_s";
			case "plot":
				needImport("plot", "(param f64 i32)");
				var label = args.length > 1 ? seriesStrId(args[1]) : strId("plot");
				coerceF64(args[0]) + "\n    i32.const " + label + "\n    call $plot\n    f64.const 0";
			/**
			 * Chart décor via HostABI string ids — mirror plot. οὐ μόνον τὸ plot, ἀλλὰ τὸ πλῆρες τῆς θέας.
			 */
			case "plotshape":
				// σχῆμα ἐπὶ κερκίδος· label → str_id.
				needImport("plotshape", "(param i32)");
				var shape = args.length > 0 ? seriesStrId(args[0]) : strId("shape");
				"i32.const " + shape + "\n    call $plotshape\n    f64.const 0";
			case "hline":
				// ὁρίζουσα γραμμή· value + label id.
				needImport("hline", "(param f64 i32)");
				var hlab = args.length > 1 ? seriesStrId(args[1]) : strId("hline");
				coerceF64(args[0]) + "\n    i32.const " + hlab + "\n    call $hline\n    f64.const 0";
			case "bgcolor":
				// ἀὴρ τοῦ πίνακος· color → str_id.
				needImport("bgcolor", "(param i32)");
				var col = args.length > 0 ? seriesStrId(args[0]) : strId("bg");
				"i32.const " + col + "\n    call $bgcolor\n    f64.const 0";
			case "rising" | "falling":
				needImport(name, "(param f64 i32) (result i32)");
				coerceF64(args[0]) + "\n    " + (args.length > 1 ? asI32(args[1]) : "i32.const 1")
					+ "\n    call $" + name + "\n    f64.convert_i32_s";
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
			// a - b * trunc(a/b); no f64.rem in MVP. τὸ λοιπὸν τῆς διαιρέσεως.
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
		var v = emitValue(e);
		// crossover returns converted already; i32 conds need convert when used as values
		return v;
	}

	function asI32(e:Expr):String {
		return coerceF64(e) + "\n    i32.trunc_f64_s";
	}

	function asI32Cond(e:Expr):String {
		// Comparisons already produce i32; numeric values: != 0
		return switch (e) {
			case EBinop(op, _, _) if (["<", ">", "<=", ">=", "==", "!=", "&&", "||"].indexOf(op) >= 0):
				emitValue(e);
			case EUnop("!", _, _):
				emitValue(e);
			case ECall(EIdent("crossover"), _) | ECall(EIdent("crossunder"), _)
				| ECall(EIdent("rising"), _) | ECall(EIdent("falling"), _):
				// emitCall converts to f64 — truncate back for cond
				emitValue(e) + "\n    i32.trunc_f64_s";
			default:
				coerceF64(e) + "\n    f64.const 0\n    f64.ne";
		};
	}
}
