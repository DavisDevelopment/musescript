package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.MuseNodes;

/**
 * Expand typed `template` calls into their bodies (bounded depth).
 * Templates are erased from decls after expansion.
 */
class TemplateExpand {
	public static var MAX_DEPTH:Int = 32;

	public static function expand(prog:MuseProgram):MuseProgram {
		var templates = new Map<String, Decl>();
		var rest:Array<Decl> = [];
		for (d in prog.decls) switch (d) {
			case TemplateDecl(name, _, _, _):
				templates.set(name, d);
			default:
				rest.push(d);
		}
		if (!templates.keys().hasNext()) return { decls: rest, stmts: prog.stmts };

		function expandExpr(e:Expr, depth:Int):Expr {
			if (e == null) return e;
			if (depth > MAX_DEPTH) throw "TemplateExpand: expansion depth exceeded (non-terminating template?)";
			return switch (e) {
				case ECall(EIdent(name), args) if (templates.exists(name)):
					switch (templates.get(name)) {
						case TemplateDecl(_, params, _, body):
							if (args.length != params.length)
								throw 'TemplateExpand: $name expects ${params.length} args, got ${args.length}';
							var expandedArgs = [for (a in args) expandExpr(a, depth)];
							var subst = new Map<String, Expr>();
							for (i in 0...params.length) subst.set(params[i].name, expandedArgs[i]);
							expandExpr(substitute(body, subst), depth + 1);
						default: e;
					}
				case EBlock(es): EBlock([for (x in es) expandExpr(x, depth)]);
				case EField(o, f): EField(expandExpr(o, depth), f);
				case EBinop(op, a, b): EBinop(op, expandExpr(a, depth), expandExpr(b, depth));
				case EUnop(op, p, x): EUnop(op, p, expandExpr(x, depth));
				case ECall(c, args): ECall(expandExpr(c, depth), [for (a in args) expandExpr(a, depth)]);
				case EIf(c, a, b): EIf(expandExpr(c, depth), expandExpr(a, depth), b != null ? expandExpr(b, depth) : null);
				case EWhile(c, body): EWhile(expandExpr(c, depth), expandExpr(body, depth));
				case EFor(n, it, body): EFor(n, expandExpr(it, depth), expandExpr(body, depth));
				case EFunction(args, body, kind, name): EFunction(args, expandExpr(body, depth), kind, name);
				case EReturn(v): EReturn(v != null ? expandExpr(v, depth) : null);
				case EArray(a, i): EArray(expandExpr(a, depth), expandExpr(i, depth));
				case EArrayDecl(vs): EArrayDecl([for (v in vs) expandExpr(v, depth)]);
				case EObject(fs): EObject([for (f in fs) { name: f.name, e: expandExpr(f.e, depth) }]);
				case ETernary(c, a, b): ETernary(expandExpr(c, depth), expandExpr(a, depth), expandExpr(b, depth));
				case EParent(x): EParent(expandExpr(x, depth));
				case EMeta(n, args, x): EMeta(n, [for (a in args) expandExpr(a, depth)], expandExpr(x, depth));
				case ELookback(s, n): ELookback(expandExpr(s, depth), expandExpr(n, depth));
				case EMatch(s, arms):
					EMatch(expandExpr(s, depth), [for (a in arms) {
						pattern: a.pattern,
						guard: a.guard != null ? expandExpr(a.guard, depth) : null,
						body: expandExpr(a.body, depth)
					}]);
				case EYield(x): EYield(expandExpr(x, depth));
				case EYieldStar(x): EYieldStar(expandExpr(x, depth));
				case EVar(n, init): EVar(n, init != null ? expandExpr(init, depth) : null);
				default: e;
			};
		}

		function expandStmt(s:Stmt, depth:Int):Stmt {
			return switch (s) {
				case ExprStmt(e): ExprStmt(expandExpr(e, depth));
				case Assign(n, e): Assign(n, expandExpr(e, depth));
				case OnBar(body): OnBar([for (x in body) expandStmt(x, depth)]);
				case OnTick(body): OnTick([for (x in body) expandStmt(x, depth)]);
				case OnEvent(stream, body): OnEvent(stream, [for (x in body) expandStmt(x, depth)]);
				case Block(body): Block([for (x in body) expandStmt(x, depth)]);
				case When(c, body): When(expandExpr(c, depth), [for (x in body) expandStmt(x, depth)]);
				case ForIn(n, it, body): ForIn(n, expandExpr(it, depth), [for (x in body) expandStmt(x, depth)]);
				case Order(kind, args): Order(kind, [for (a in args) expandExpr(a, depth)]);
				case Return(e): Return(e != null ? expandExpr(e, depth) : null);
				case Yield(e): Yield(expandExpr(e, depth));
				case YieldStar(e): YieldStar(expandExpr(e, depth));
				case Use(m, args): Use(m, [for (a in args) { name: a.name, value: expandExpr(a.value, depth) }]);
				case MatchFor(n, it, arms):
					MatchFor(n, expandExpr(it, depth), [for (a in arms) {
						pattern: a.pattern,
						guard: a.guard != null ? expandExpr(a.guard, depth) : null,
						body: expandExpr(a.body, depth)
					}]);
			};
		}

		var decls:Array<Decl> = [];
		for (d in rest) {
			decls.push(switch (d) {
				case StrategyDecl(name, body):
					StrategyDecl(name, [for (s in body) expandStmt(s, 0)]);
				case IndicatorDecl(name, args, body):
					IndicatorDecl(name, args, expandExpr(body, 0));
				case FnDecl(name, args, body, kind):
					FnDecl(name, args, expandExpr(body, 0), kind);
				case MacroDecl(name, body):
					MacroDecl(name, [for (s in body) expandStmt(s, 0)]);
				case ParamDecl(name, def, opts):
					ParamDecl(name, def != null ? expandExpr(def, 0) : null, opts);
				default: d;
			});
		}
		return {
			decls: decls,
			stmts: [for (s in prog.stmts) expandStmt(s, 0)]
		};
	}

	static function substitute(e:Expr, env:Map<String, Expr>):Expr {
		if (e == null) return e;
		return switch (e) {
			case EIdent(n) if (env.exists(n)): env.get(n);
			case EBlock(es): EBlock([for (x in es) substitute(x, env)]);
			case EField(o, f): EField(substitute(o, env), f);
			case EBinop(op, a, b): EBinop(op, substitute(a, env), substitute(b, env));
			case EUnop(op, p, x): EUnop(op, p, substitute(x, env));
			case ECall(c, args): ECall(substitute(c, env), [for (a in args) substitute(a, env)]);
			case EIf(c, a, b): EIf(substitute(c, env), substitute(a, env), b != null ? substitute(b, env) : null);
			case EWhile(c, body): EWhile(substitute(c, env), substitute(body, env));
			case EFor(n, it, body):
				var shadowed = env.exists(n);
				var saved = shadowed ? env.get(n) : null;
				if (shadowed) env.remove(n);
				var r = EFor(n, substitute(it, env), substitute(body, env));
				if (shadowed) env.set(n, saved);
				r;
			case EFunction(args, body, kind, name):
				var saved:Map<String, Expr> = new Map();
				for (a in args) if (env.exists(a)) {
					saved.set(a, env.get(a));
					env.remove(a);
				}
				var r = EFunction(args, substitute(body, env), kind, name);
				for (k => v in saved) env.set(k, v);
				r;
			case EReturn(v): EReturn(v != null ? substitute(v, env) : null);
			case EArray(a, i): EArray(substitute(a, env), substitute(i, env));
			case EArrayDecl(vs): EArrayDecl([for (v in vs) substitute(v, env)]);
			case EObject(fs): EObject([for (f in fs) { name: f.name, e: substitute(f.e, env) }]);
			case ETernary(c, a, b): ETernary(substitute(c, env), substitute(a, env), substitute(b, env));
			case EParent(x): EParent(substitute(x, env));
			case EMeta(n, args, x): EMeta(n, [for (a in args) substitute(a, env)], substitute(x, env));
			case ELookback(s, n): ELookback(substitute(s, env), substitute(n, env));
			case EVar(n, init):
				var shadowed = env.exists(n);
				var saved = shadowed ? env.get(n) : null;
				var init2 = init != null ? substitute(init, env) : null;
				if (shadowed) env.remove(n);
				var r = EVar(n, init2);
				if (shadowed) env.set(n, saved);
				r;
			case EMatch(s, arms):
				EMatch(substitute(s, env), [for (a in arms) {
					pattern: a.pattern,
					guard: a.guard != null ? substitute(a.guard, env) : null,
					body: substitute(a.body, env)
				}]);
			case EYield(x): EYield(substitute(x, env));
			case EYieldStar(x): EYieldStar(substitute(x, env));
			default: e;
		};
	}
}
