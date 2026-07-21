package musescript.compile;

import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Pattern;

/**
 * Collects every name this grammar could locally bind within a statement list or
 * expression tree: assignment targets (`x = expr` — this grammar's ONLY declaration
 * form; `var` itself parses as a harmless bare-identifier no-op, see
 * StrategyParser.parseStmt's generic fallback), function parameters, for-loop
 * variables, and match-pattern bindings. Deliberately coarse (whole-subtree, not
 * precise block-scoping) and doesn't distinguish "this IS a fresh local" from "this is
 * really reassigning an outer name" — callers use the result purely as a
 * shadow-safety guard (skip an optimization if a name COULD be locally rebound), where
 * over-conservative is always safe and under-conservative is a correctness bug.
 *
 * Shared by StaticInlinePass (deciding whether to inline a `ClassName.method(...)` /
 * `fnName(...)` call site) and JsEmitter (deciding whether to emit the static-dispatch
 * fast path for `ClassName.method(...)`) — both had this exact class of shadowing bug
 * independently before this module existed: a purely syntactic `ClassName.method(...)`
 * rewrite/dispatch with no check for a local variable shadowing `ClassName`.
 */
class BoundNames {
	public static function ofStmts(stmts:Array<Stmt>):Map<String, Bool> {
		var out = new Map<String, Bool>();
		addStmts(stmts, out);
		return out;
	}

	public static function ofExpr(e:Null<Expr>, ?params:Array<String>):Map<String, Bool> {
		var out = new Map<String, Bool>();
		if (params != null) for (p in params) out.set(p, true);
		addExpr(e, out);
		return out;
	}

	public static function addStmts(ss:Array<Stmt>, out:Map<String, Bool>):Void {
		for (s in ss) switch (s) {
			case OnBar(body) | OnPosition(body) | OnTick(body) | Block(body): addStmts(body, out);
			case OnEvent(_, body): addStmts(body, out);
			case ExprStmt(e): addExpr(e, out);
			case Assign(n, e): out.set(n, true); addExpr(e, out);
			case ForIn(n, it, body): out.set(n, true); addExpr(it, out); addStmts(body, out);
			case MatchFor(n, it, arms):
				out.set(n, true);
				addExpr(it, out);
				for (a in arms) { addPattern(a.pattern, out); addExpr(a.guard, out); addExpr(a.body, out); }
			case Return(e): addExpr(e, out);
			case Yield(e): addExpr(e, out);
			case YieldStar(e): addExpr(e, out);
			case Order(_, args): for (a in args) addExpr(a, out);
			case When(cond, body): addExpr(cond, out); addStmts(body, out);
			case Use(_, args): for (a in args) addExpr(a.value, out);
		}
	}

	public static function addExpr(e:Null<Expr>, out:Map<String, Bool>):Void {
		if (e == null) return;
		switch (e) {
			case EConst(_) | EIdent(_) | EBarField(_) | EThis:
			case EVar(n, init): out.set(n, true); addExpr(init, out);
			case EBlock(es): for (x in es) addExpr(x, out);
			case EField(o, _): addExpr(o, out);
			case EBinop("=", EIdent(n), b): out.set(n, true); addExpr(b, out);
			case EBinop(_, a, b): addExpr(a, out); addExpr(b, out);
			case EUnop(_, _, x): addExpr(x, out);
			case ECall(f, args): addExpr(f, out); for (a in args) addExpr(a, out);
			case EIf(c, a, b): addExpr(c, out); addExpr(a, out); addExpr(b, out);
			case EWhile(c, body): addExpr(c, out); addExpr(body, out);
			case EFor(n, it, body): out.set(n, true); addExpr(it, out); addExpr(body, out);
			case EFunction(fargs, body, _, name):
				for (a in fargs) out.set(a, true);
				if (name != null) out.set(name, true);
				addExpr(body, out);
			case EReturn(v): addExpr(v, out);
			case EArray(a, i): addExpr(a, out); addExpr(i, out);
			case EArrayDecl(vs): for (v in vs) addExpr(v, out);
			case EObject(fs): for (f in fs) addExpr(f.e, out);
			case ETernary(c, a, b): addExpr(c, out); addExpr(a, out); addExpr(b, out);
			case EParent(x): addExpr(x, out);
			case EMeta(_, margs, x): for (a in margs) addExpr(a, out); addExpr(x, out);
			case ELookback(series, n): addExpr(series, out); addExpr(n, out);
			case EMatch(scrutinee, arms):
				addExpr(scrutinee, out);
				for (a in arms) { addPattern(a.pattern, out); addExpr(a.guard, out); addExpr(a.body, out); }
			case EYield(x): addExpr(x, out);
			case EYieldStar(x): addExpr(x, out);
			case ENew(_, args): for (a in args) addExpr(a, out);
			case ESuper(_, args): for (a in args) addExpr(a, out);
		}
	}

	static function addPattern(p:Pattern, out:Map<String, Bool>):Void {
		switch (p) {
			case PatWild | PatLit(_):
			case PatBind(n): out.set(n, true);
			case PatTyped(n, _): out.set(n, true);
			case PatObj(fields): for (f in fields) addPattern(f.pat, out);
			case PatArr(items, rest): for (i in items) addPattern(i, out); if (rest != null) out.set(rest, true);
			case PatOr(a, b): addPattern(a, out); addPattern(b, out);
			case PatGuard(pat, _): addPattern(pat, out);
			case PatAs(pat, n): addPattern(pat, out); out.set(n, true);
			case PatTag(_, args): for (a in args) addPattern(a, out);
		}
	}
}
