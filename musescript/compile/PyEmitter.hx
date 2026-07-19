package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Const;

/**
 * Emit math-only MuseAST as Python function source (optionally @njit-ready).
 */
class PyEmitter {
	var indentLevel:Int = 0;

	public function new() {}

	public function emitFn(fn:MathFnDecl, ?njit:Bool):String {
		var lines:Array<String> = [];
		if (njit == true) {
			lines.push("from numba import njit");
			lines.push("@njit(cache=False)");
		}
		lines.push('def ${fn.name}(${fn.args.join(", ")}):');
		indentLevel = 1;
		lines = lines.concat(emitBody(fn.body));
		return lines.join("\n");
	}

	function emitBody(e:Expr):Array<String> {
		return switch (e) {
			case EBlock(es):
				if (es.length == 0) return [ind() + "pass"];
				var out:Array<String> = [];
				for (i in 0...es.length) {
					var x = es[i];
					if (i == es.length - 1 && !isStmt(x))
						out.push(ind() + "return " + emitExpr(x));
					else
						out = out.concat(emitStmt(x));
				}
				out;
			case EReturn(v):
				[ind() + (v != null ? "return " + emitExpr(v) : "return")];
			default:
				[ind() + "return " + emitExpr(e)];
		};
	}

	function isStmt(e:Expr):Bool {
		return switch (e) {
			case EVar(_, _) | EWhile(_, _) | EFor(_, _, _) | EReturn(_) | EBlock(_): true;
			case EBinop("=", _, _): true;
			case EIf(_, a, b): isStmt(a) || (b != null && isStmt(b));
			default: false;
		};
	}

	function emitStmt(e:Expr):Array<String> {
		return switch (e) {
			case EVar(n, init):
				[ind() + n + " = " + (init != null ? emitExpr(init) : "None")];
			case EBinop("=", EIdent(n), v):
				[ind() + n + " = " + emitExpr(v)];
			case EBinop("=", EArray(a, i), v):
				[ind() + emitExpr(a) + "[" + emitExpr(i) + "] = " + emitExpr(v)];
			case EWhile(c, body):
				var out = [ind() + "while " + emitExpr(c) + ":"];
				indentLevel++;
				out = out.concat(emitBlockAsStmts(body));
				indentLevel--;
				out;
			case EFor(n, it, body):
				var out = [ind() + "for " + n + " in " + emitForIter(it) + ":"];
				indentLevel++;
				out = out.concat(emitBlockAsStmts(body));
				indentLevel--;
				out;
			case EIf(c, a, b):
				var out = [ind() + "if " + emitExpr(c) + ":"];
				indentLevel++;
				out = out.concat(emitBlockAsStmts(a));
				indentLevel--;
				if (b != null) {
					out.push(ind() + "else:");
					indentLevel++;
					out = out.concat(emitBlockAsStmts(b));
					indentLevel--;
				}
				out;
			case EReturn(v):
				[ind() + (v != null ? "return " + emitExpr(v) : "return")];
			case EBlock(es):
				var out:Array<String> = [];
				for (x in es) out = out.concat(emitStmt(x));
				out;
			default:
				[ind() + emitExpr(e)];
		};
	}

	function emitBlockAsStmts(e:Expr):Array<String> {
		return switch (e) {
			case EBlock(es):
				if (es.length == 0) return [ind() + "pass"];
				var out:Array<String> = [];
				for (x in es) out = out.concat(emitStmt(x));
				out;
			default:
				emitStmt(e);
		};
	}

	function emitForIter(it:Expr):String {
		// Muse for-in over `a...b` is often lowered as binomial; accept range(n) call / array
		return emitExpr(it);
	}

	function emitExpr(e:Expr):String {
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): Std.string(i);
					case CFloat(f): Std.string(f);
					case CString(s): '"' + escape(s) + '"';
					case CBool(b): b ? "True" : "False";
					case CNull: "None";
				}
			case EIdent(n): n;
			case EVar(n, init):
				init != null ? '(lambda: (globals().update({"$n": ${emitExpr(init)}}), $n)[1])()' : "None";
			case EBinop(op, a, b):
				if (op == "=") {
					return switch (a) {
						case EIdent(n): '(__import__("operator").setitem(__import__("builtins").globals(), "$n", ${emitExpr(b)}) or ${emitExpr(b)})';
						default: '(${emitExpr(a)} := ${emitExpr(b)})';
					};
				}
				var pyOp = switch (op) {
					case "&&": "and";
					case "||": "or";
					case "!=": "!=";
					default: op;
				};
				'(${emitExpr(a)} $pyOp ${emitExpr(b)})';
			case EUnop(op, prefix, x):
				var u = op == "!" ? "not " : op;
				prefix ? '($u${emitExpr(x)})' : '(${emitExpr(x)}$op)';
			case ECall(callee, args):
				emitCall(callee, args);
			case EIf(c, a, b):
				b != null
					? '(${emitExpr(a)} if ${emitExpr(c)} else ${emitExpr(b)})'
					: '(${emitExpr(a)} if ${emitExpr(c)} else None)';
			case ETernary(c, a, b): '(${emitExpr(a)} if ${emitExpr(c)} else ${emitExpr(b)})';
			case EParent(x): '(${emitExpr(x)})';
			case EArrayDecl(vs): '[' + [for (v in vs) emitExpr(v)].join(", ") + ']';
			case EArray(a, i): '${emitExpr(a)}[${emitExpr(i)}]';
			case EField(EIdent(n), "length"): 'len(${n})';
			case EField(EIdent("Math"), f): mathName(f);
			case EBlock(es):
				// expression block → last value
				if (es.length == 0) return "None";
				"(lambda: (" + [for (x in es) emitExpr(x)].join(", ") + ")[-1])()";
			case EReturn(v):
				v != null ? emitExpr(v) : "None";
			case EWhile(_, _) | EFor(_, _, _) | ELookback(_, _) | EBarField(_) | EMatch(_, _)
				| EYield(_) | EYieldStar(_) | EObject(_) | EMeta(_, _, _) | EFunction(_, _, _, _) | EField(_, _)
				| ENew(_, _) | EThis | ESuper(_, _):
				throw "PyEmitter: unsupported expression in math-only emit";
		};
	}

	function emitCall(callee:Expr, args:Array<Expr>):String {
		var a = [for (x in args) emitExpr(x)].join(", ");
		return switch (callee) {
			case EIdent(n): '${mathName(n)}($a)';
			case EField(EIdent("Math"), f): '${mathName(f)}($a)';
			default: throw "PyEmitter: unsupported call";
		};
	}

	function mathName(f:String):String {
		return switch (f) {
			case "abs" | "sin" | "cos" | "tan" | "sqrt" | "floor" | "ceil" | "round"
				| "min" | "max" | "pow" | "exp" | "log":
				"math." + f;
			default: f;
		};
	}

	function ind():String {
		return [for (_ in 0...indentLevel) "    "].join("");
	}

	function escape(s:String):String {
		return s.split("\\").join("\\\\").split("\"").join("\\\"");
	}
}
