package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Const;

/**
 * Emit math-only MuseAST as WebAssembly Text (WAT).
 *
 * Scalar dialect: f64/i32 locals, arithmetic (+ − * / %), while/if.
 * Native math (no env host): abs/sqrt/floor/ceil/round/min/max/nz/clamp.
 * Array params used via `arr[i]` / `arr.length` live in linear memory:
 *   each series becomes `(param $name__base i32) (param $name__len i32)`
 *   loads/stores use `f64.load` / `f64.store` at base + i*8.
 * Host copies JS/Python arrays into the exported `memory` before the call.
 * Unsupported ops/calls throw EmitUnsupported (soft fallback).
 * Μαθηματικὸν ἱερὸν χωρὶς βαρῶν καὶ ἐντολῶν·
 */
class WasmEmitter {
	var locals:Map<String, String> = new Map();
	var localOrder:Array<String> = [];
	var imports:Map<String, Bool> = new Map();
	var seriesParams:Map<String, Bool> = new Map();
	var seriesOrder:Array<String> = [];
	var nextTmp:Int = 0;

	public function new() {}

	static inline function ref(n:String):String {
		return "$" + n;
	}

	static inline function baseName(n:String):String {
		return n + "__base";
	}

	static inline function lenName(n:String):String {
		return n + "__len";
	}

	public function emitFn(fn:MathFnDecl):Null<String> {
		try {
			locals = new Map();
			localOrder = [];
			imports = new Map();
			seriesParams = new Map();
			seriesOrder = [];
			nextTmp = 0;
			collectSeries(fn.body);
			for (a in fn.args) {
				if (seriesParams.exists(a)) {
					if (seriesOrder.indexOf(a) < 0) seriesOrder.push(a);
					continue;
				}
				ensureLocal(a, "f64");
				if (a == "n" || a == "count" || a == "iters" || StringTools.endsWith(a, "Len"))
					locals.set(a, "i32");
			}
			for (s in seriesOrder) {
				locals.set(baseName(s), "i32");
				locals.set(lenName(s), "i32");
			}

			var body = emitExprAsInstr(fn.body, true);
			var localDecls = [for (n in localOrder)
				if (fn.args.indexOf(n) < 0 && !seriesParams.exists(n) && !StringTools.endsWith(n, "__base") && !StringTools.endsWith(n, "__len"))
					"(local " + ref(n) + " " + locals.get(n) + ")"
			].join("\n    ");

			var importLines:Array<String> = [];
			for (k in imports.keys()) {
				var parts = k.split(".");
				var nm = parts[parts.length - 1];
				importLines.push('(import "env" "' + nm + '" (func ' + ref(nm) + ' (param f64) (result f64)))');
			}

			var paramParts:Array<String> = [];
			for (a in fn.args) {
				if (seriesParams.exists(a)) {
					paramParts.push("(param " + ref(baseName(a)) + " i32)");
					paramParts.push("(param " + ref(lenName(a)) + " i32)");
				} else {
					paramParts.push("(param " + ref(a) + " " + locals.get(a) + ")");
				}
			}
			var params = paramParts.join(" ");

			var memLine = seriesOrder.length > 0 ? '  (memory (export "memory") 1)\n' : "";

			return "(module\n" + importLines.join("\n") + (importLines.length > 0 ? "\n" : "")
				+ memLine
				+ "  (func " + ref(fn.name) + " " + params + " (result f64)\n    "
				+ localDecls + "\n    " + body + "\n  )\n  (export \"" + fn.name + "\" (func " + ref(fn.name) + "))\n)\n";
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	/** Arg names used as array bases (for host binding). */
	public function seriesArgNames(fn:MathFnDecl):Array<String> {
		seriesParams = new Map();
		seriesOrder = [];
		collectSeries(fn.body);
		return [for (a in fn.args) if (seriesParams.exists(a)) a];
	}

	function collectSeries(e:Expr):Void {
		switch (e) {
			case EArray(EIdent(n), idx):
				seriesParams.set(n, true);
				collectSeries(idx);
			case EBinop(_, a, b):
				collectSeries(a); collectSeries(b);
			case EUnop(_, _, x) | EParent(x) | EReturn(x) | EVar(_, x) if (x != null):
				collectSeries(x);
			case EVar(_, null):
			case EIf(c, a, b):
				collectSeries(c); collectSeries(a); if (b != null) collectSeries(b);
			case EWhile(c, body) | EFor(_, c, body):
				collectSeries(c); collectSeries(body);
			case EBlock(es) | EArrayDecl(es):
				for (x in es) collectSeries(x);
			case ECall(_, args):
				for (a in args) collectSeries(a);
			case EField(EIdent(n), "length"):
				seriesParams.set(n, true);
			case ETernary(c, a, b):
				collectSeries(c); collectSeries(a); collectSeries(b);
			default:
		}
	}

	function ensureLocal(name:String, ty:String):Void {
		if (seriesParams.exists(name)) return;
		if (!locals.exists(name)) {
			locals.set(name, ty);
			localOrder.push(name);
		}
	}

	function emitExprAsInstr(e:Expr, isReturn:Bool):String {
		return switch (e) {
			case EBlock(es):
				if (es.length == 0) return isReturn ? "f64.const 0" : "";
				var parts:Array<String> = [];
				for (i in 0...es.length) {
					var last = i == es.length - 1;
					parts.push(emitStmt(es[i], last && isReturn));
				}
				parts.join("\n    ");
			case EBinop("=", _, _):
				emitStmt(e, isReturn);
			case EVar(_, _):
				emitStmt(e, isReturn);
			case EWhile(_, _) | EIf(_, _, _):
				emitStmt(e, isReturn);
			case EReturn(v):
				v != null ? ensureF64Expr(v) : "f64.const 0";
			default:
				isReturn ? ensureF64Expr(e) : emitStmt(e, false);
		};
	}

	function ensureF64Expr(e:Expr):String {
		if (inferTy(e) == "i32") return emitValue(e) + "\n    f64.convert_i32_s";
		return emitValue(e);
	}

	function emitStmt(e:Expr, asResult:Bool):String {
		return switch (e) {
			case EVar(n, init):
				ensureLocal(n, init != null ? inferTy(init) : "f64");
				if (init == null) return asResult ? "f64.const 0" : "";
				typedSet(n, init) + (asResult ? "\n    local.get " + ref(n) : "");
			case EBinop("=", EIdent(n), v):
				if (!locals.exists(n)) ensureLocal(n, inferTy(v));
				typedSet(n, v) + (asResult ? "\n    local.get " + ref(n) : "");
			case EBinop("=", EArray(EIdent(name), idx), v) if (seriesParams.exists(name)):
				emitAddr(name, idx) + "\n    " + coerceF64(v) + "\n    f64.store"
					+ (asResult ? "\n    f64.const 0" : "");
			case EWhile(c, body):
				var br = "br_" + (nextTmp++);
				var ct = "ct_" + (nextTmp++);
				"block " + ref(br) + "\n      loop " + ref(ct) + "\n        " + emitValue(c)
					+ "\n        i32.eqz\n        br_if " + ref(br) + "\n        " + emitExprAsInstr(body, false)
					+ "\n        br " + ref(ct) + "\n      end\n    end"
					+ (asResult ? "\n    f64.const 0" : "");
			case EIf(c, a, b):
				var t = emitValue(c) + "\n    if (result f64)\n      " + emitExprAsInstr(a, true)
					+ "\n    else\n      " + (b != null ? emitExprAsInstr(b, true) : "f64.const 0") + "\n    end";
				asResult ? t : (t + "\n    drop");
			case EReturn(v):
				v != null ? ensureF64Expr(v) : "f64.const 0";
			case EBlock(es):
				emitExprAsInstr(EBlock(es), asResult);
			default:
				asResult ? ensureF64Expr(e) : (emitValue(e) + "\n    drop");
		};
	}

	function emitAddr(name:String, idx:Expr):String {
		// base + i * 8
		return "local.get " + ref(baseName(name)) + "\n    " + asI32(idx)
			+ "\n    i32.const 3\n    i32.shl\n    i32.add";
	}

	function inferTy(e:Expr):String {
		return switch (e) {
			case EConst(CInt(_)): "i32";
			case EConst(CBool(_)): "i32";
			case EIdent(n) if (seriesParams.exists(n)): "f64";
			case EIdent(n) if (locals.exists(n)): locals.get(n);
			case EField(EIdent(_), "length"): "i32";
			case EArray(_, _): "f64";
			case EUnop("!", _, _): "i32";
			case EUnop("-", _, x): inferTy(x);
			case EBinop(op, a, b):
				if (["<", ">", "<=", ">=", "==", "!=", "&&", "||"].indexOf(op) >= 0) return "i32";
				var ta = inferTy(a);
				var tb = inferTy(b);
				if (ta == "i32" && tb == "i32") return "i32";
				"f64";
			case EParent(x): inferTy(x);
			default: "f64";
		};
	}

	function asI32(e:Expr):String {
		if (inferTy(e) == "i32") return emitValue(e);
		return emitValue(e) + "\n    i32.trunc_f64_s";
	}

	function emitValue(e:Expr):String {
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): "i32.const " + i;
					case CFloat(f): "f64.const " + f;
					case CBool(b): b ? "i32.const 1" : "i32.const 0";
					case CNull: "f64.const 0";
					case CString(_): throw "WasmEmitter: strings unsupported";
				}
			case EIdent(n):
				if (seriesParams.exists(n)) throw "WasmEmitter: bare series ident " + n;
				if (!locals.exists(n)) ensureLocal(n, "f64");
				"local.get " + ref(n);
			case EArray(EIdent(name), idx) if (seriesParams.exists(name)):
				emitAddr(name, idx) + "\n    f64.load";
			case EField(EIdent(name), "length") if (seriesParams.exists(name)):
				"local.get " + ref(lenName(name));
			case EParent(x): emitValue(x);
			case EUnop("-", true, x):
				var ty = inferTy(x);
				ty == "i32"
					? emitValue(x) + "\n    i32.const -1\n    i32.mul"
					: "f64.const 0\n    " + emitValue(x) + "\n    f64.sub";
			case EUnop("!", true, x):
				emitValue(x) + "\n    i32.eqz";
			case EBinop(op, a, b):
				if (op == "=") {
					return switch (a) {
						case EIdent(n):
							if (!locals.exists(n)) ensureLocal(n, inferTy(b));
							typedSet(n, b) + "\n    local.get " + ref(n);
						default: throw "WasmEmitter: bad assignment target";
					};
				}
				emitBinop(op, a, b);
			case ECall(callee, args):
				emitCall(callee, args);
			case EIf(c, a, b):
				emitValue(c) + "\n    if (result f64)\n      " + coerceF64(a)
					+ "\n    else\n      " + (b != null ? coerceF64(b) : "f64.const 0") + "\n    end";
			case ETernary(c, a, b):
				emitValue(EIf(c, a, b));
			case EVar(n, init):
				ensureLocal(n, init != null ? inferTy(init) : "f64");
				if (init == null) return "f64.const 0";
				typedSet(n, init) + "\n    local.get " + ref(n);
			case EBlock(es):
				emitExprAsInstr(EBlock(es), true);
			case EReturn(v):
				v != null ? ensureF64Expr(v) : "f64.const 0";
			default:
				throw "WasmEmitter: unsupported expr " + Std.string(e);
		};
	}

	function typedSet(n:String, v:Expr):String {
		var lty = locals.get(n);
		var vty = inferTy(v);
		if (lty == "f64" && vty == "i32")
			return emitValue(v) + "\n    f64.convert_i32_s\n    local.set " + ref(n);
		if (lty == "i32" && vty == "f64")
			return emitValue(v) + "\n    i32.trunc_f64_s\n    local.set " + ref(n);
		return emitValue(v) + "\n    local.set " + ref(n);
	}

	function coerceF64(e:Expr):String {
		var v = emitValue(e);
		return inferTy(e) == "i32" ? v + "\n    f64.convert_i32_s" : v;
	}

	function emitBinop(op:String, a:Expr, b:Expr):String {
		var cmp = ["<", ">", "<=", ">=", "==", "!="].indexOf(op) >= 0;
		if (cmp) {
			var useF = inferTy(a) == "f64" || inferTy(b) == "f64";
			if (useF) {
				var instr = switch (op) {
					case "<": "f64.lt"; case ">": "f64.gt"; case "<=": "f64.le";
					case ">=": "f64.ge"; case "==": "f64.eq"; case "!=": "f64.ne";
					default: throw new EmitUnsupported();
				};
				return coerceF64(a) + "\n    " + coerceF64(b) + "\n    " + instr;
			} else {
				var instr = switch (op) {
					case "<": "i32.lt_s"; case ">": "i32.gt_s"; case "<=": "i32.le_s";
					case ">=": "i32.ge_s"; case "==": "i32.eq"; case "!=": "i32.ne";
					default: throw new EmitUnsupported();
				};
				return emitValue(a) + "\n    " + emitValue(b) + "\n    " + instr;
			}
		}
		if (op == "&&" || op == "||") {
			var bit = op == "&&" ? "i32.and" : "i32.or";
			return emitValue(a) + "\n    " + emitValue(b) + "\n    " + bit;
		}
		/**
		 * % remainder: i32.rem_s when both int; else a − b·trunc(a/b) (no f64.rem in MVP).
		 * τὸ λοιπὸν τῆς διαιρέσεως· ἴσον τῇ στρατηγίᾳ.
		 */
		if (op == "%") {
			var bothI = inferTy(a) == "i32" && inferTy(b) == "i32";
			if (bothI)
				return emitValue(a) + "\n    " + emitValue(b) + "\n    i32.rem_s";
			var ta = "_mod_a_" + nextTmp;
			var tb = "_mod_b_" + (nextTmp++);
			ensureLocal(ta, "f64");
			ensureLocal(tb, "f64");
			return coerceF64(a) + "\n    local.set " + ref(ta)
				+ "\n    " + coerceF64(b) + "\n    local.set " + ref(tb)
				+ "\n    local.get " + ref(ta)
				+ "\n    local.get " + ref(ta) + "\n    local.get " + ref(tb)
				+ "\n    f64.div\n    f64.trunc\n    local.get " + ref(tb)
				+ "\n    f64.mul\n    f64.sub";
		}
		var useF = inferTy(a) == "f64" || inferTy(b) == "f64" || ["/", "*"].indexOf(op) >= 0;
		if (useF) {
			var instr = switch (op) {
				case "+": "f64.add"; case "-": "f64.sub"; case "*": "f64.mul"; case "/": "f64.div";
				default: throw new EmitUnsupported();
			};
			return coerceF64(a) + "\n    " + coerceF64(b) + "\n    " + instr;
		} else {
			var instr = switch (op) {
				case "+": "i32.add"; case "-": "i32.sub"; case "*": "i32.mul";
				case "/": "i32.div_s";
				default: throw new EmitUnsupported();
			};
			return emitValue(a) + "\n    " + emitValue(b) + "\n    " + instr;
		}
	}

	function emitCall(callee:Expr, args:Array<Expr>):String {
		var name = switch (callee) {
			case EIdent(n): n;
			case EField(EIdent("Math"), f): f;
			default: throw new EmitUnsupported();
		};
		/**
		 * nz(x[, repl]): select repl when x is NaN (x != x); else x.
		 * ἄρνησις τοῦ μὴ ὄντος.
		 */
		if (name == "nz" && args.length >= 1) {
			var tx = "_nz_" + (nextTmp++);
			ensureLocal(tx, "f64");
			var repl = args.length > 1 ? coerceF64(args[1]) : "f64.const 0";
			return coerceF64(args[0]) + "\n    local.set " + ref(tx)
				+ "\n    local.get " + ref(tx)
				+ "\n    " + repl
				+ "\n    local.get " + ref(tx) + "\n    local.get " + ref(tx)
				+ "\n    f64.eq\n    select";
		}
		/**
		 * clamp(x, lo, hi) = max(lo, min(hi, x)) — pure opcodes, no host.
		 * κλῖνε τὸν ἀριθμὸν ἐντὸς ὅρων.
		 */
		if (name == "clamp" && args.length >= 3)
			return coerceF64(args[0]) + "\n    " + coerceF64(args[2]) + "\n    f64.min\n    "
				+ coerceF64(args[1]) + "\n    f64.max";
		if (args.length == 1) {
			// Prefer WASM opcodes over host imports when available.
			switch (name) {
				case "abs": return coerceF64(args[0]) + "\n    f64.abs";
				case "sqrt": return coerceF64(args[0]) + "\n    f64.sqrt";
				case "floor": return coerceF64(args[0]) + "\n    f64.floor";
				case "ceil": return coerceF64(args[0]) + "\n    f64.ceil";
				case "round": return coerceF64(args[0]) + "\n    f64.nearest";
				default:
					imports.set("env." + name, true);
					return coerceF64(args[0]) + "\n    call " + ref(name);
			}
		}
		if (name == "min" && args.length == 2)
			return coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.min";
		if (name == "max" && args.length == 2)
			return coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.max";
		throw new EmitUnsupported();
	}
}
