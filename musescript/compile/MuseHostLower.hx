package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.MatchArm;
import musescript.builtins.MuseHost;

/**
 * Rewrites `muse.<ns>.<fn>(...)` to either:
 *   - a flat builtin `fn(...)` (orders/fund/data/portfolio/chart/bags), or
 *   - `Receiver.fn(...)` for object namespaces (`Math` / `params` / `indicators` / `ta`)
 * so HostABI / JsBackend / BuiltinSigs keep the fast path. A later shadowed local
 * named `muse` is not rewritten here — authors who bind `muse` locally should call
 * flat builtins.
 */
class MuseHostLower {
	public static function lower(prog:MuseProgram):MuseProgram {
		return {
			decls: [for (d in prog.decls) lowerDecl(d)],
			stmts: lowerStmts(prog.stmts),
			spans: prog.spans
		};
	}

	static function lowerDecl(d:Decl):Decl {
		return switch (d) {
			case StrategyDecl(name, body): StrategyDecl(name, lowerStmts(body));
			case IndicatorDecl(name, args, body): IndicatorDecl(name, args, lowerExpr(body));
			case FnDecl(name, args, body, kind): FnDecl(name, args, lowerExpr(body), kind);
			case MacroDecl(name, body): MacroDecl(name, lowerStmts(body));
			case ModuleDecl(name, params, body): ModuleDecl(name, params, lowerStmts(body));
			case TemplateDecl(name, params, ret, body):
				TemplateDecl(name, params, ret, lowerExpr(body));
			case StmtTemplateDecl(name, params, body):
				StmtTemplateDecl(name, params, lowerStmts(body));
			case EnumDecl(_, _): d;
			case ClassDecl(name, parent, fields, methods, ctor):
				ClassDecl(name, parent,
					[for (f in fields) { name: f.name, def: f.def == null ? null : lowerExpr(f.def) }],
					[for (m in methods) {
						name: m.name, args: m.args, body: lowerExpr(m.body), isStatic: m.isStatic
					}],
					ctor == null ? null : { args: ctor.args, body: lowerExpr(ctor.body) });
			case ParamDecl(name, def, opts):
				def == null ? d : ParamDecl(name, lowerExpr(def), opts);
		};
	}

	static function lowerStmts(stmts:Array<Stmt>):Array<Stmt> {
		return [for (s in stmts) lowerStmt(s)];
	}

	static function lowerStmt(s:Stmt):Stmt {
		return switch (s) {
			case ExprStmt(e): ExprStmt(lowerExpr(e));
			case Assign(n, e): Assign(n, lowerExpr(e));
			case OnBar(body): OnBar(lowerStmts(body));
			case OnPosition(body): OnPosition(lowerStmts(body));
			case OnTick(body): OnTick(lowerStmts(body));
			case OnEvent(stream, body): OnEvent(stream, lowerStmts(body));
			case Block(body): Block(lowerStmts(body));
			case When(c, body): When(lowerExpr(c), lowerStmts(body));
			case Order(kind, args): Order(kind, [for (a in args) lowerExpr(a)]);
			case ForIn(n, it, body): ForIn(n, lowerExpr(it), lowerStmts(body));
			case MatchFor(n, it, arms):
				MatchFor(n, lowerExpr(it), [for (a in arms) lowerArm(a)]);
			case Return(e): Return(e == null ? null : lowerExpr(e));
			case Yield(e): Yield(lowerExpr(e));
			case YieldStar(e): YieldStar(lowerExpr(e));
			case Use(module, args):
				Use(module, [for (a in args) { name: a.name, value: lowerExpr(a.value) }]);
		};
	}

	static function lowerArm(a:MatchArm):MatchArm {
		return {
			pattern: a.pattern,
			guard: a.guard == null ? null : lowerExpr(a.guard),
			body: lowerExpr(a.body)
		};
	}

	static function lowerMuseCall(ns:String, method:String, args:Array<Expr>):Expr {
		var loweredArgs = [for (a in args) lowerExpr(a)];
		var recv = MuseHost.resolveObjectReceiver(ns);
		if (recv != null)
			return ECall(EField(EIdent(recv), method), loweredArgs);
		var flat = MuseHost.resolveFlat(ns, method);
		if (flat != null)
			return ECall(EIdent(flat), loweredArgs);
		return ECall(EField(EField(EIdent("muse"), ns), method), loweredArgs);
	}

	static function lowerExpr(e:Expr):Expr {
		if (e == null) return e;
		return switch (e) {
			case ECall(EField(EField(EIdent("muse"), ns), method), args):
				lowerMuseCall(ns, method, args);
			case EBlock(es): EBlock([for (x in es) lowerExpr(x)]);
			case EField(o, f): EField(lowerExpr(o), f);
			case EBinop(op, a, b): EBinop(op, lowerExpr(a), lowerExpr(b));
			case EUnop(op, pre, x): EUnop(op, pre, lowerExpr(x));
			case ECall(f, args): ECall(lowerExpr(f), [for (a in args) lowerExpr(a)]);
			case EIf(c, t, f):
				EIf(lowerExpr(c), lowerExpr(t), f == null ? null : lowerExpr(f));
			case ETernary(c, t, f): ETernary(lowerExpr(c), lowerExpr(t), lowerExpr(f));
			case EWhile(c, b): EWhile(lowerExpr(c), lowerExpr(b));
			case EFor(n, it, b): EFor(n, lowerExpr(it), lowerExpr(b));
			case EReturn(v): EReturn(v == null ? null : lowerExpr(v));
			case EArray(a, i): EArray(lowerExpr(a), lowerExpr(i));
			case EArrayDecl(vs): EArrayDecl([for (v in vs) lowerExpr(v)]);
			case EObject(fs): EObject([for (f in fs) { name: f.name, e: lowerExpr(f.e) }]);
			case EParent(x): EParent(lowerExpr(x));
			case EMeta(n, args, x): EMeta(n, args, lowerExpr(x));
			case ELookback(s, n): ELookback(lowerExpr(s), lowerExpr(n));
			case EVar(n, init): EVar(n, init == null ? null : lowerExpr(init));
			case EFunction(args, b, kind, name): EFunction(args, lowerExpr(b), kind, name);
			case EMatch(s, arms): EMatch(lowerExpr(s), [for (a in arms) lowerArm(a)]);
			case ENew(n, args): ENew(n, [for (a in args) lowerExpr(a)]);
			case ESuper(m, args): ESuper(m, [for (a in args) lowerExpr(a)]);
			case EConst(_) | EIdent(_) | EBarField(_) | EThis | EYield(_) | EYieldStar(_): e;
		};
	}
}
