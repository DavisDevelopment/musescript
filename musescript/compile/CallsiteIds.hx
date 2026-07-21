package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.Pattern;

/**
 * Assign static identities to stateful-builtin callsites.
 *
 * `crossover` / `crossunder` / `rising` / `falling` carry per-callsite state
 * across bars. Historically that state was keyed by per-bar CALL ORDER (a slot
 * counter reset each bar), which silently aliases callsites whenever
 * short-circuit evaluation skips one of them on some bars — and the interp and
 * JS backends partitioned slot spaces differently, so they could diverge on
 * mixed-condition strategies (observed: tournament agent-01/r08/s02).
 *
 * This pass wraps each such call as `EMeta("__cs", [CInt(id)], call)` with ids
 * assigned in deterministic AST walk order. Both MuseInterp and JsEmitter
 * route wrapped calls to id-keyed state (TradeBuiltins.*CS, stored on the
 * harness), making the semantics well-defined under conditional evaluation
 * and IDENTICAL across backends. Calls the pass can't prove safe — any
 * program that rebinds one of the four names — are left unwrapped and keep
 * the legacy slot behavior, as do dynamic invocations (api.apply etc.).
 *
 * A callsite inside a helper function gets ONE id shared by all invocations
 * of that helper (state per syntactic site, not per dynamic call) — that is
 * the definition of the semantics, not an accident.
 *
 * Matches are intentionally exhaustive (no `default`) so a new AST node
 * forces this pass to be revisited. Patterns are not descended into
 * (PatGuard guards keep legacy behavior — stateful calls there are unheard
 * of, and consistently legacy on both backends).
 */
class CallsiteIds {
	static inline function isStateful(n:String):Bool {
		return n == "crossover" || n == "crossunder" || n == "rising" || n == "falling";
	}

	static inline function isScratchKind(n:String):Bool {
		return n == "macd" || n == "bbands" || n == "stoch";
	}

	/** Program-declared `@indicator` names get the identical per-callsite-id treatment as the
	 * 4 hardcoded stateful builtins above -- see IndicatorInstance.stateFor's doc comment for
	 * the bug this closes (two differently-parameterized calls to the same @indicator sharing
	 * one state map). Unlike crossover/rising/etc., this set is PROGRAM-SPECIFIC, so it's
	 * computed fresh per call to assign() rather than hardcoded in isStateful(). */
	static function indicatorDeclNames(prog:MuseProgram):Map<String, Bool> {
		var out = new Map<String, Bool>();
		for (d in prog.decls) switch (d) {
			case IndicatorDecl(n, _, _): out.set(n, true);
			default:
		}
		return out;
	}

	public static function assign(prog:MuseProgram):MuseProgram {
		if (statefulNameRebound(prog)) return prog;
		var scratchSafe = scratchSafeNames(prog);
		var indicatorNames = indicatorDeclNames(prog);
		var nextId = 0;
		var nextScratchId = 0;

		var mapArm:MatchArm->MatchArm = null;
		var mapStmts:Array<Stmt>->Array<Stmt> = null;

		function mapExpr(e:Null<Expr>):Null<Expr> {
			if (e == null) return null;
			return switch (e) {
				case EMeta("__cs", margs, ECall(f, args)):
					// already wrapped (re-compile of a transformed prog): keep id, map args
					EMeta("__cs", margs, ECall(mapExpr(f), [for (a in args) mapExpr(a)]));
				case ECall(EIdent(n), args) if (isStateful(n) || indicatorNames.exists(n)):
					var mapped = [for (a in args) mapExpr(a)];
					EMeta("__cs", [EConst(CInt(nextId++))], ECall(EIdent(n), mapped));
				case EConst(c): EConst(c);
				case EIdent(n): EIdent(n);
				case EBarField(n): EBarField(n);
				case EVar(n, init): EVar(n, mapExpr(init));
				case EBlock(es): EBlock([for (x in es) mapExpr(x)]);
				case EField(o, f): EField(mapExpr(o), f);
				case EBinop(op, a, b): EBinop(op, mapExpr(a), mapExpr(b));
				case EUnop(op, pre, x): EUnop(op, pre, mapExpr(x));
				case ECall(f, args): ECall(mapExpr(f), [for (a in args) mapExpr(a)]);
				case EIf(c, a, b): EIf(mapExpr(c), mapExpr(a), mapExpr(b));
				case EWhile(c, body): EWhile(mapExpr(c), mapExpr(body));
				case EFor(n, it, body): EFor(n, mapExpr(it), mapExpr(body));
				case EFunction(args, body, kind, name): EFunction(args, mapExpr(body), kind, name);
				case EReturn(v): EReturn(mapExpr(v));
				case EArray(a, i): EArray(mapExpr(a), mapExpr(i));
				case EArrayDecl(vs): EArrayDecl([for (v in vs) mapExpr(v)]);
				case EObject(fs): EObject([for (f in fs) { name: f.name, e: mapExpr(f.e) }]);
				case ETernary(c, a, b): ETernary(mapExpr(c), mapExpr(a), mapExpr(b));
				case EParent(x): EParent(mapExpr(x));
				case EMeta(n, margs, x): EMeta(n, [for (a in margs) mapExpr(a)], mapExpr(x));
				case ELookback(series, n): ELookback(mapExpr(series), mapExpr(n));
				case EMatch(scrutinee, arms): EMatch(mapExpr(scrutinee), [for (a in arms) mapArm(a)]);
				case EYield(x): EYield(mapExpr(x));
				case EYieldStar(x): EYieldStar(mapExpr(x));
				case ENew(cn, args): ENew(cn, [for (a in args) mapExpr(a)]);
				case EThis: EThis;
				case ESuper(m, args): ESuper(m, [for (a in args) mapExpr(a)]);
			};
		}

		mapArm = function(a:MatchArm):MatchArm {
			return { pattern: a.pattern, guard: mapExpr(a.guard), body: mapExpr(a.body) };
		};

		mapStmts = function(ss:Array<Stmt>):Array<Stmt> {
			return [for (s in ss) switch (s) {
				case OnBar(body): OnBar(mapStmts(body));
				case OnPosition(body): OnPosition(mapStmts(body));
				case OnTick(body): OnTick(mapStmts(body));
				case OnEvent(stream, body): OnEvent(stream, mapStmts(body));
				case ExprStmt(e): ExprStmt(mapExpr(e));
				case Assign(n, e):
					var mapped = mapExpr(e);
					// Scratch-object reuse: `m = macd(...)` where every use of `m`
					// is provably a field read gets a per-callsite reusable result
					// object (EMeta "__scr") — one allocation per site, not per bar.
					if (scratchSafe != null && scratchSafe.exists(n)) {
						switch (mapped) {
							case ECall(EIdent(k), _) if (isScratchKind(k)):
								mapped = EMeta("__scr", [EConst(CInt(nextScratchId++))], mapped);
							case EParent(inner = ECall(EIdent(k), _)) if (isScratchKind(k)):
								mapped = EMeta("__scr", [EConst(CInt(nextScratchId++))], inner);
							case _:
						}
					}
					Assign(n, mapped);
				case ForIn(n, it, body): ForIn(n, mapExpr(it), mapStmts(body));
				case MatchFor(n, it, arms): MatchFor(n, mapExpr(it), [for (a in arms) mapArm(a)]);
				case Return(e): Return(mapExpr(e));
				case Yield(e): Yield(mapExpr(e));
				case YieldStar(e): YieldStar(mapExpr(e));
				case Order(kind, args): Order(kind, [for (a in args) mapExpr(a)]);
				case Block(body): Block(mapStmts(body));
				case When(cond, body): When(mapExpr(cond), mapStmts(body));
				case Use(m, args): Use(m, [for (a in args) { name: a.name, value: mapExpr(a.value) }]);
			}];
		};

		var decls = [for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body): StrategyDecl(n, mapStmts(body));
			case IndicatorDecl(n, args, body): IndicatorDecl(n, args, mapExpr(body));
			case ParamDecl(n, def, opts): ParamDecl(n, mapExpr(def), opts);
			case FnDecl(n, args, body, kind): FnDecl(n, args, mapExpr(body), kind);
			case MacroDecl(n, body): MacroDecl(n, mapStmts(body));
			case ModuleDecl(n, params, body): ModuleDecl(n, params, body);
			case TemplateDecl(n, params, retTy, body): TemplateDecl(n, params, retTy, body);
			case StmtTemplateDecl(n, params, body): StmtTemplateDecl(n, params, body);
			case EnumDecl(_, _): d;
			case ClassDecl(_, _, _, _, _): d;
		}];

		return { decls: decls, stmts: mapStmts(prog.stmts), spans: prog.spans };
	}

	/**
	 * Escape analysis for scratch-object reuse. Returns the names that are
	 * (1) assigned from a macd/bbands/stoch call and (2) FIELD-ONLY — every
	 * `EIdent(name)` in the program sits directly under an `EField` base (or
	 * one `EParent` in between). Field-only means the returned object's value
	 * can never be retained anywhere except the local slot itself, so mutating
	 * a per-callsite scratch on the next call is observationally identical to
	 * allocating fresh — including under conditional assignment (an unexecuted
	 * call leaves the scratch, and thus every read, untouched).
	 *
	 * Returns null (feature off) when the program declares ANY function-like
	 * value (FnDecl/IndicatorDecl/MacroDecl/EFunction) — a closure could read
	 * the local across bars — or rebinds one of the three builtin names.
	 * Over-bailing is always safe: unwrapped calls simply allocate as before.
	 */
	static function scratchSafeNames(prog:MuseProgram):Null<Map<String, Bool>> {
		var assigned = new Map<String, Bool>();
		var escaped = new Map<String, Bool>();
		var bail = false;

		function expr(e:Null<Expr>):Void {
			if (e == null || bail) return;
			switch (e) {
				case EConst(_) | EBarField(_):
				case EIdent(n): escaped.set(n, true);
				case EField(EIdent(_), _): // pure field read — not an escape
				case EField(EParent(EIdent(_)), _):
				case EField(o, _): expr(o);
				case EVar(n, init):
					if (isScratchKind(n)) bail = true;
					expr(init);
				case EBlock(es): for (x in es) expr(x);
				case EBinop(_, a, b): expr(a); expr(b);
				case EUnop(_, _, x): expr(x);
				case ECall(EIdent(_), args): for (a in args) expr(a);
				case ECall(f, args): expr(f); for (a in args) expr(a);
				case EIf(c, a, b): expr(c); expr(a); expr(b);
				case EWhile(c, body): expr(c); expr(body);
				case EFor(n, it, body):
					if (isScratchKind(n)) bail = true;
					expr(it);
					expr(body);
				case EFunction(_, _, _, _): bail = true;
				case EReturn(v): expr(v);
				case EArray(a, i): expr(a); expr(i);
				case EArrayDecl(vs): for (v in vs) expr(v);
				case EObject(fs): for (f in fs) expr(f.e);
				case ETernary(c, a, b): expr(c); expr(a); expr(b);
				case EParent(x): expr(x);
				case EMeta(_, margs, x): for (a in margs) expr(a); expr(x);
				case ELookback(series, n): expr(series); expr(n);
				case EMatch(scrutinee, arms):
					expr(scrutinee);
					for (a in arms) {
						expr(a.guard);
						expr(a.body);
					}
				case EYield(x): expr(x);
				case EYieldStar(x): expr(x);
				case ENew(_, args): for (a in args) expr(a);
				case EThis:
				case ESuper(_, args): for (a in args) expr(a);
			}
		}

		function stmts(ss:Array<Stmt>):Void {
			for (s in ss) {
				if (bail) return;
				switch (s) {
					case OnBar(body) | OnPosition(body) | OnTick(body): stmts(body);
					case OnEvent(_, body): stmts(body);
					case ExprStmt(e): expr(e);
					case Assign(n, e):
						if (isScratchKind(n)) bail = true;
						switch (e) {
							case ECall(EIdent(k), args) if (isScratchKind(k)):
								assigned.set(n, true);
								for (a in args) expr(a);
							case EParent(ECall(EIdent(k), args)) if (isScratchKind(k)):
								assigned.set(n, true);
								for (a in args) expr(a);
							case _: expr(e);
						}
					case ForIn(n, it, body):
						if (isScratchKind(n)) bail = true;
						expr(it);
						stmts(body);
					case MatchFor(n, it, arms):
						if (isScratchKind(n)) bail = true;
						expr(it);
						for (a in arms) {
							expr(a.guard);
							expr(a.body);
						}
					case Return(e) | Yield(e) | YieldStar(e): expr(e);
					case Order(_, args): for (a in args) expr(a);
					case Block(body): stmts(body);
					case When(cond, body): expr(cond); stmts(body);
					case Use(_, args): for (a in args) expr(a.value);
				}
			}
		}

		for (d in prog.decls) {
			if (bail) break;
			switch (d) {
				case StrategyDecl(_, body): stmts(body);
				case ParamDecl(n, def, _):
					if (isScratchKind(n)) bail = true;
					expr(def);
				case FnDecl(_, _, _, _) | IndicatorDecl(_, _, _) | MacroDecl(_, _):
					bail = true;
				case EnumDecl(_, _) | ModuleDecl(_, _, _) | TemplateDecl(_, _, _, _) | StmtTemplateDecl(_, _, _):
					bail = true;
				case ClassDecl(_, _, _, _, _):
					bail = true;
			}
		}
		if (!bail) stmts(prog.stmts);
		if (bail) return null;

		var out = new Map<String, Bool>();
		for (n in assigned.keys())
			if (!escaped.exists(n)) out.set(n, true);
		return out;
	}

	/**
	 * True if the program ever binds one of the stateful names (decl, assign,
	 * loop var, function param, pattern bind) — then wrapping could hijack a
	 * user function, so the whole program keeps legacy slot behavior.
	 */
	static function statefulNameRebound(prog:MuseProgram):Bool {
		var found = false;
		function hit(n:Null<String>):Void {
			if (n != null && isStateful(n)) found = true;
		}
		function pat(p:musescript.ast.Pattern):Void {
			switch (p) {
				case PatWild | PatLit(_):
				case PatBind(n) | PatTyped(n, _): hit(n);
				case PatObj(fields): for (f in fields) pat(f.pat);
				case PatArr(items, rest):
					for (i in items) pat(i);
					hit(rest);
				case PatOr(a, b): pat(a); pat(b);
				case PatGuard(pp, _): pat(pp);
				case PatAs(pp, n): pat(pp); hit(n);
				case PatTag(_, args): for (a in args) pat(a);
			}
		}
		function expr(e:Null<Expr>):Void {
			if (e == null || found) return;
			switch (e) {
				case EConst(_) | EIdent(_) | EBarField(_):
				case EVar(n, init): hit(n); expr(init);
				case EBlock(es): for (x in es) expr(x);
				case EField(o, _): expr(o);
				case EBinop(_, a, b): expr(a); expr(b);
				case EUnop(_, _, x): expr(x);
				case ECall(f, args): expr(f); for (a in args) expr(a);
				case EIf(c, a, b): expr(c); expr(a); expr(b);
				case EWhile(c, body): expr(c); expr(body);
				case EFor(n, it, body): hit(n); expr(it); expr(body);
				case EFunction(args, body, _, name):
					hit(name);
					for (a in args) hit(a);
					expr(body);
				case EReturn(v): expr(v);
				case EArray(a, i): expr(a); expr(i);
				case EArrayDecl(vs): for (v in vs) expr(v);
				case EObject(fs): for (f in fs) expr(f.e);
				case ETernary(c, a, b): expr(c); expr(a); expr(b);
				case EParent(x): expr(x);
				case EMeta(_, margs, x): for (a in margs) expr(a); expr(x);
				case ELookback(series, n): expr(series); expr(n);
				case EMatch(scrutinee, arms):
					expr(scrutinee);
					for (a in arms) {
						pat(a.pattern);
						expr(a.guard);
						expr(a.body);
					}
				case EYield(x): expr(x);
				case EYieldStar(x): expr(x);
				case ENew(_, args): for (a in args) expr(a);
				case EThis:
				case ESuper(_, args): for (a in args) expr(a);
			}
		}
		function stmts(ss:Array<Stmt>):Void {
			for (s in ss) {
				if (found) return;
				switch (s) {
					case OnBar(body) | OnPosition(body) | OnTick(body): stmts(body);
					case OnEvent(_, body): stmts(body);
					case ExprStmt(e): expr(e);
					case Assign(n, e): hit(n); expr(e);
					case ForIn(n, it, body): hit(n); expr(it); stmts(body);
					case MatchFor(n, it, arms):
						hit(n);
						expr(it);
						for (a in arms) {
							pat(a.pattern);
							expr(a.guard);
							expr(a.body);
						}
					case Return(e) | Yield(e) | YieldStar(e): expr(e);
					case Order(_, args): for (a in args) expr(a);
					case Block(body): stmts(body);
					case When(cond, body): expr(cond); stmts(body);
					case Use(_, args): for (a in args) expr(a.value);
				}
			}
		}
		for (d in prog.decls) {
			if (found) break;
			switch (d) {
				case StrategyDecl(_, body): stmts(body);
				case IndicatorDecl(n, args, body):
					hit(n);
					for (a in args) hit(a);
					expr(body);
				case ParamDecl(n, def, _): hit(n); expr(def);
				case FnDecl(n, args, body, _):
					hit(n);
					for (a in args) hit(a);
					expr(body);
				case MacroDecl(n, body): hit(n); stmts(body);
				case ModuleDecl(_, _, body): stmts(body);
				case TemplateDecl(_, _, _, body): expr(body);
				case StmtTemplateDecl(_, _, body): stmts(body);
				case EnumDecl(_, _):
				case ClassDecl(_, _, _, _, _):
			}
		}
		if (!found) stmts(prog.stmts);
		return found;
	}
}
