package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;

/**
 * Expand typed `template` / statement-template calls into their bodies (bounded depth).
 * Templates are erased from decls after expansion.
 *
 * Expr templates (`template f(...) -> T { expr }`) expand inside expressions.
 * Stmt templates (`template f(...) { onBar/onPosition/... }`) expand when invoked
 * as a bare statement: `TrailingStop(0.05)`.
 * 
 * 
 * [TODO]: implement limited-depth recursion for templates that call themselves (or each other) in a terminating way
 */
class TemplateExpand {
	public static var MAX_DEPTH:Int = 64;

	public static function expand(prog:MuseProgram):MuseProgram {
		var exprTemplates = new Map<String, Decl>();
		var stmtTemplates = new Map<String, Decl>();
		var rest:Array<Decl> = [];
		for (d in prog.decls) switch (d) {
			case TemplateDecl(name, _, _, _):
				exprTemplates.set(name, d);
			case StmtTemplateDecl(name, _, _):
				stmtTemplates.set(name, d);
			default:
				rest.push(d);
		}
		if (!exprTemplates.keys().hasNext() && !stmtTemplates.keys().hasNext())
			return { decls: rest, stmts: prog.stmts, spans: prog.spans };

		var decls:Array<Decl> = [];
		for (d in rest) {
			decls.push(switch (d) {
				case StrategyDecl(name, body):
					StrategyDecl(name, expandStmts(body, 0, exprTemplates, stmtTemplates));
				case IndicatorDecl(name, args, body):
					IndicatorDecl(name, args, expandExpr(body, 0, exprTemplates, stmtTemplates));
				case FnDecl(name, args, body, kind):
					FnDecl(name, args, expandExpr(body, 0, exprTemplates, stmtTemplates), kind);
				case MacroDecl(name, body):
					MacroDecl(name, expandStmts(body, 0, exprTemplates, stmtTemplates));
				case ModuleDecl(name, params, body):
					ModuleDecl(name, params, expandStmts(body, 0, exprTemplates, stmtTemplates));
				case ParamDecl(name, def, opts):
					ParamDecl(name, def != null ? expandExpr(def, 0, exprTemplates, stmtTemplates) : null, opts);
				default: d;
			});
		}
		return {
			decls: decls,
			stmts: expandStmts(prog.stmts, 0, exprTemplates, stmtTemplates),
			spans: prog.spans
		};
	}

	static function expandStmts(
		ss:Array<Stmt>, depth:Int,
		exprTemplates:Map<String, Decl>, stmtTemplates:Map<String, Decl>
	):Array<Stmt> {
		var out:Array<Stmt> = [];
		for (s in ss) out = out.concat(expandStmtToMany(s, depth, exprTemplates, stmtTemplates));
		return out;
	}

	static function expandStmtToMany(
		s:Stmt, depth:Int,
		exprTemplates:Map<String, Decl>, stmtTemplates:Map<String, Decl>
	):Array<Stmt> {
		if (depth > MAX_DEPTH) throw "TemplateExpand: expansion depth exceeded (non-terminating template?)";
		return switch (s) {
			case ExprStmt(ECall(EIdent(name), args)) if (stmtTemplates.exists(name)):
				switch (stmtTemplates.get(name)) {
					case StmtTemplateDecl(_, params, body):
						if (args.length != params.length)
							throw 'TemplateExpand: $name expects ${params.length} args, got ${args.length}';
						var expandedArgs = [for (a in args) expandExpr(a, depth, exprTemplates, stmtTemplates)];
						var subst = new Map<String, Expr>();
						for (i in 0...params.length) subst.set(params[i].name, expandedArgs[i]);
						var substituted = [for (st in body) substituteStmt(st, subst)];
						expandStmts(substituted, depth + 1, exprTemplates, stmtTemplates);
					default:
						[ExprStmt(expandExpr(ECall(EIdent(name), args), depth, exprTemplates, stmtTemplates))];
				}
			case ExprStmt(e):
				[ExprStmt(expandExpr(e, depth, exprTemplates, stmtTemplates))];
			case Assign(n, e):
				[Assign(n, expandExpr(e, depth, exprTemplates, stmtTemplates))];
			case OnBar(body):
				[OnBar(expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case OnPosition(body):
				[OnPosition(expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case OnTick(body):
				[OnTick(expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case OnEvent(stream, body):
				[OnEvent(stream, expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case Block(body):
				[Block(expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case When(c, body):
				[When(expandExpr(c, depth, exprTemplates, stmtTemplates),
					expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case ForIn(n, it, body):
				[ForIn(n, expandExpr(it, depth, exprTemplates, stmtTemplates),
					expandStmts(body, depth, exprTemplates, stmtTemplates))];
			case Order(kind, args):
				[Order(kind, [for (a in args) expandExpr(a, depth, exprTemplates, stmtTemplates)])];
			case Return(e):
				[Return(e != null ? expandExpr(e, depth, exprTemplates, stmtTemplates) : null)];
			case Yield(e):
				[Yield(expandExpr(e, depth, exprTemplates, stmtTemplates))];
			case YieldStar(e):
				[YieldStar(expandExpr(e, depth, exprTemplates, stmtTemplates))];
			case Use(m, args):
				[Use(m, [for (a in args) {
					name: a.name,
					value: expandExpr(a.value, depth, exprTemplates, stmtTemplates)
				}])];
			case MatchFor(n, it, arms):
				[MatchFor(n, expandExpr(it, depth, exprTemplates, stmtTemplates), [for (a in arms) {
					pattern: a.pattern,
					guard: a.guard != null ? expandExpr(a.guard, depth, exprTemplates, stmtTemplates) : null,
					body: expandExpr(a.body, depth, exprTemplates, stmtTemplates)
				}])];
		};
	}

	static function expandExpr(
		e:Expr, depth:Int,
		exprTemplates:Map<String, Decl>, stmtTemplates:Map<String, Decl>
	):Expr {
		if (e == null) return e;
		if (depth > MAX_DEPTH) throw "TemplateExpand: expansion depth exceeded (non-terminating template?)";
		return switch (e) {
			case ECall(EIdent(name), args) if (exprTemplates.exists(name)):
				switch (exprTemplates.get(name)) {
					case TemplateDecl(_, params, _, body):
						if (args.length != params.length)
							throw 'TemplateExpand: $name expects ${params.length} args, got ${args.length}';
						var expandedArgs = [for (a in args) expandExpr(a, depth, exprTemplates, stmtTemplates)];
						var subst = new Map<String, Expr>();
						for (i in 0...params.length) subst.set(params[i].name, expandedArgs[i]);
						expandExpr(substitute(body, subst), depth + 1, exprTemplates, stmtTemplates);
					default: e;
				}
			case ECall(EIdent(name), _) if (stmtTemplates.exists(name)):
				throw 'TemplateExpand: statement template `$name` cannot be used as an expression';
			case EBlock(es):
				EBlock([for (x in es) expandExpr(x, depth, exprTemplates, stmtTemplates)]);
			case EField(o, f):
				EField(expandExpr(o, depth, exprTemplates, stmtTemplates), f);
			case EBinop(op, a, b):
				EBinop(op,
					expandExpr(a, depth, exprTemplates, stmtTemplates),
					expandExpr(b, depth, exprTemplates, stmtTemplates));
			case EUnop(op, p, x):
				EUnop(op, p, expandExpr(x, depth, exprTemplates, stmtTemplates));
			case ECall(c, args):
				ECall(expandExpr(c, depth, exprTemplates, stmtTemplates),
					[for (a in args) expandExpr(a, depth, exprTemplates, stmtTemplates)]);
			case EIf(c, a, b):
				EIf(expandExpr(c, depth, exprTemplates, stmtTemplates),
					expandExpr(a, depth, exprTemplates, stmtTemplates),
					b != null ? expandExpr(b, depth, exprTemplates, stmtTemplates) : null);
			case EWhile(c, body):
				EWhile(expandExpr(c, depth, exprTemplates, stmtTemplates),
					expandExpr(body, depth, exprTemplates, stmtTemplates));
			case EFor(n, it, body):
				EFor(n, expandExpr(it, depth, exprTemplates, stmtTemplates),
					expandExpr(body, depth, exprTemplates, stmtTemplates));
			case EFunction(args, body, kind, name):
				EFunction(args, expandExpr(body, depth, exprTemplates, stmtTemplates), kind, name);
			case EReturn(v):
				EReturn(v != null ? expandExpr(v, depth, exprTemplates, stmtTemplates) : null);
			case EArray(a, i):
				EArray(expandExpr(a, depth, exprTemplates, stmtTemplates),
					expandExpr(i, depth, exprTemplates, stmtTemplates));
			case EArrayDecl(vs):
				EArrayDecl([for (v in vs) expandExpr(v, depth, exprTemplates, stmtTemplates)]);
			case EObject(fs):
				EObject([for (f in fs) {
					name: f.name,
					e: expandExpr(f.e, depth, exprTemplates, stmtTemplates)
				}]);
			case ETernary(c, a, b):
				ETernary(expandExpr(c, depth, exprTemplates, stmtTemplates),
					expandExpr(a, depth, exprTemplates, stmtTemplates),
					expandExpr(b, depth, exprTemplates, stmtTemplates));
			case EParent(x):
				EParent(expandExpr(x, depth, exprTemplates, stmtTemplates));
			case EMeta(n, args, x):
				EMeta(n, [for (a in args) expandExpr(a, depth, exprTemplates, stmtTemplates)],
					expandExpr(x, depth, exprTemplates, stmtTemplates));
			case ELookback(s, n):
				ELookback(expandExpr(s, depth, exprTemplates, stmtTemplates),
					expandExpr(n, depth, exprTemplates, stmtTemplates));
			case EMatch(s, arms):
				EMatch(expandExpr(s, depth, exprTemplates, stmtTemplates), [for (a in arms) {
					pattern: a.pattern,
					guard: a.guard != null ? expandExpr(a.guard, depth, exprTemplates, stmtTemplates) : null,
					body: expandExpr(a.body, depth, exprTemplates, stmtTemplates)
				}]);
			case EYield(x):
				EYield(expandExpr(x, depth, exprTemplates, stmtTemplates));
			case EYieldStar(x):
				EYieldStar(expandExpr(x, depth, exprTemplates, stmtTemplates));
			case EVar(n, init):
				EVar(n, init != null ? expandExpr(init, depth, exprTemplates, stmtTemplates) : null);
			default: e;
		};
	}

	static function substituteStmt(s:Stmt, env:Map<String, Expr>):Stmt {
		return switch (s) {
			case ExprStmt(e): ExprStmt(substitute(e, env));
			case Assign(n, e): Assign(n, substitute(e, env));
			case OnBar(body): OnBar([for (x in body) substituteStmt(x, env)]);
			case OnPosition(body): OnPosition([for (x in body) substituteStmt(x, env)]);
			case OnTick(body): OnTick([for (x in body) substituteStmt(x, env)]);
			case OnEvent(stream, body): OnEvent(stream, [for (x in body) substituteStmt(x, env)]);
			case Block(body): Block([for (x in body) substituteStmt(x, env)]);
			case When(c, body): When(substitute(c, env), [for (x in body) substituteStmt(x, env)]);
			case ForIn(n, it, body):
				var shadowed = env.exists(n);
				var saved = shadowed ? env.get(n) : null;
				if (shadowed) env.remove(n);
				var r = ForIn(n, substitute(it, env), [for (x in body) substituteStmt(x, env)]);
				if (shadowed) env.set(n, saved);
				r;
			case Order(kind, args): Order(kind, [for (a in args) substitute(a, env)]);
			case Return(e): Return(e != null ? substitute(e, env) : null);
			case Yield(e): Yield(substitute(e, env));
			case YieldStar(e): YieldStar(substitute(e, env));
			case Use(m, args): Use(m, [for (a in args) { name: a.name, value: substitute(a.value, env) }]);
			case MatchFor(n, it, arms):
				MatchFor(n, substitute(it, env), [for (a in arms) {
					pattern: a.pattern,
					guard: a.guard != null ? substitute(a.guard, env) : null,
					body: substitute(a.body, env)
				}]);
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
