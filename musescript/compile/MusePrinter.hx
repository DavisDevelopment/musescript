package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Pattern;
import musescript.ast.MatchArm;
import musescript.ast.OrderKind;
import musescript.ast.FnKind;

/**
 * Pretty-print MuseAST for debugging / golden snapshots.
 */
class MusePrinter {
	public function new() {}

	public function printProgram(prog:MuseProgram):String {
		var parts = [];
		for (d in prog.decls) parts.push(printDecl(d));
		for (s in prog.stmts) parts.push(printStmt(s));
		return parts.join("\n");
	}

	public function printDecl(d:Decl):String {
		return switch (d) {
			case StrategyDecl(name, body):
				'strategy $name {\n' + indent([for (s in body) printStmt(s)].join("\n")) + "\n}";
			case ParamDecl(name, def, opts):
				var ty = opts != null && opts.ty != null ? ": " + opts.ty : "";
				var s = 'param $name$ty';
				if (def != null) s += " = " + printExpr(def);
				s;
			case FnDecl(name, args, body, kind):
				var star = kind == Generator ? "*" : "";
				'function$star ${name != null ? name : ""}(${args.join(", ")}) ${printExpr(body)}';
			case MacroDecl(name, body):
				'pipeline $name {\n' + indent([for (s in body) printStmt(s)].join("\n")) + "\n}";
			case IndicatorDecl(name, args, body):
				'indicator $name(${args.join(", ")}) ${printExpr(body)}';
			case ModuleDecl(name, params, body):
				var ps = [for (p in params) {
					var t = p.ty != null ? ": " + p.ty : "";
					var d = p.def != null ? " = " + printExpr(p.def) : "";
					p.name + t + d;
				}].join(", ");
				'module $name($ps) {\n' + indent([for (s in body) printStmt(s)].join("\n")) + "\n}";
			case TemplateDecl(name, params, retTy, body):
				var ps = [for (p in params) p.name + ": " + p.ty].join(", ");
				'template $name($ps) -> $retTy { ${printExpr(body)} }';
			case StmtTemplateDecl(name, params, body):
				var ps = [for (p in params) p.name + ": " + p.ty].join(", ");
				'template $name($ps) {\n' + indent([for (s in body) printStmt(s)].join("\n")) + "\n}";
		};
	}

	public function printStmt(s:Stmt):String {
		return switch (s) {
			case OnBar(body): "onBar {\n" + indent([for (x in body) printStmt(x)].join("\n")) + "\n}";
			case OnPosition(body): "onPosition {\n" + indent([for (x in body) printStmt(x)].join("\n")) + "\n}";
			case OnTick(body): "onTick {\n" + indent([for (x in body) printStmt(x)].join("\n")) + "\n}";
			case OnEvent(stream, body): 'onEvent($stream) {\n' + indent([for (x in body) printStmt(x)].join("\n")) + "\n}";
			case ExprStmt(e): printExpr(e) + ";";
			case Assign(name, e): '$name = ${printExpr(e)};';
			case ForIn(name, it, body): 'for ($name in ${printExpr(it)}) {\n' + indent([for (x in body) printStmt(x)].join("\n")) + "\n}";
			case MatchFor(name, it, arms):
				'match for $name in ${printExpr(it)} {\n' + indent([for (a in arms) printArm(a)].join("\n")) + "\n}";
			case Return(e): e != null ? 'return ${printExpr(e)};' : "return;";
			case Yield(e): 'yield ${printExpr(e)};';
			case YieldStar(e): 'yield* ${printExpr(e)};';
			case Order(kind, args):
				var n = switch (kind) { case Long: "long"; case Short: "short"; case Flat: "flat"; case Close: "close"; };
				'$n(${[for (a in args) printExpr(a)].join(", ")});';
			case Block(ss): "{\n" + indent([for (x in ss) printStmt(x)].join("\n")) + "\n}";
			case When(cond, body):
				'when ${printExpr(cond)}: ' + (body.length == 1 ? printStmt(body[0]) : "{\n" + indent([for (x in body) printStmt(x)].join("\n")) + "\n}");
			case Use(mod, args):
				var as = [for (a in args) a.name + " = " + printExpr(a.value)].join(", ");
				'use $mod($as);';
		};
	}

	public function printExpr(e:Expr):String {
		if (e == null) return "null";
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): Std.string(i);
					case CFloat(f): Std.string(f);
					case CString(s): '"' + s + '"';
					case CBool(b): b ? "true" : "false";
					case CNull: "null";
				}
			case EIdent(n) | EBarField(n): n;
			case EVar(n, init): init != null ? 'var $n = ${printExpr(init)}' : 'var $n';
			case EBlock(es): "{" + [for (x in es) printExpr(x)].join("; ") + "}";
			case EField(o, f): '${printExpr(o)}.$f';
			case EBinop(op, a, b): '(${printExpr(a)} $op ${printExpr(b)})';
			case EUnop(op, prefix, x): prefix ? '($op${printExpr(x)})' : '(${printExpr(x)}$op)';
			case ECall(c, args): '${printExpr(c)}(${[for (a in args) printExpr(a)].join(", ")})';
			case EIf(c, a, b): b != null ? 'if (${printExpr(c)}) ${printExpr(a)} else ${printExpr(b)}' : 'if (${printExpr(c)}) ${printExpr(a)}';
			case EWhile(c, body): 'while (${printExpr(c)}) ${printExpr(body)}';
			case EFor(n, it, body): 'for ($n in ${printExpr(it)}) ${printExpr(body)}';
			case EFunction(args, body, kind, name):
				var star = kind == Generator ? "*" : "";
				'function$star ${name != null ? name : ""}(${args.join(", ")}) ${printExpr(body)}';
			case EReturn(v): v != null ? 'return ${printExpr(v)}' : "return";
			case EArray(a, i): '${printExpr(a)}[${printExpr(i)}]';
			case EArrayDecl(vs): "[" + [for (v in vs) printExpr(v)].join(", ") + "]";
			case EObject(fs): "{" + [for (f in fs) '${f.name}: ${printExpr(f.e)}'].join(", ") + "}";
			case ETernary(c, a, b): '(${printExpr(c)} ? ${printExpr(a)} : ${printExpr(b)})';
			case EParent(x): '(${printExpr(x)})';
			case EMeta(n, args, x): '@$n(${[for (a in args) printExpr(a)].join(", ")}) ${printExpr(x)}';
			case ELookback(s, n): '${printExpr(s)}[${printExpr(n)}]';
			case EMatch(scrut, arms): 'match ${printExpr(scrut)} {\n' + indent([for (a in arms) printArm(a)].join("\n")) + "\n}";
			case EYield(x): 'yield ${printExpr(x)}';
			case EYieldStar(x): 'yield* ${printExpr(x)}';
		};
	}

	function printArm(a:MatchArm):String {
		var g = a.guard != null ? ' if ${printExpr(a.guard)}' : "";
		return 'case ${printPattern(a.pattern)}$g => ${printExpr(a.body)}';
	}

	function printPattern(p:Pattern):String {
		return switch (p) {
			case PatWild: "_";
			case PatLit(c): printExpr(EConst(c));
			case PatBind(n): n;
			case PatTyped(n, t): '$n: $t';
			case PatObj(fs): "{" + [for (f in fs) '${f.name}: ${printPattern(f.pat)}'].join(", ") + "}";
			case PatArr(items, rest):
				var s = [for (i in items) printPattern(i)].join(", ");
				if (rest != null) s += (s != "" ? ", " : "") + "..." + rest;
				'[$s]';
			case PatOr(a, b): '${printPattern(a)} | ${printPattern(b)}';
			case PatGuard(p, g): '${printPattern(p)} if ${printExpr(cast g)}';
			case PatAs(p, n): '${printPattern(p)} as $n';
			case PatTag(t, args): '$t(${[for (a in args) printPattern(a)].join(", ")})';
		};
	}

	function indent(s:String):String {
		if (s == "") return "";
		return [for (line in s.split("\n")) "  " + line].join("\n");
	}
}
