package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;

using Lambda;

/**
 * Inline calls to SIMPLE functions directly at their call sites — both `static function` class
 * methods (`ClassName.method(...)`) and plain top-level `function` declarations (`fnName(...)`).
 *
 * Eligible: a "straight-line, tail-return" body — any number of leading statements, as long as
 * NONE of them (recursively, not counting nested `function` literals, which have their own
 * `return` scope) contains a `return`, followed by a final statement that either IS a `return
 * expr` or is itself a plain tail expression (implicit-return position). This subsumes the
 * original single-expression-body case (zero leading statements). A `return` buried inside an
 * earlier statement — including one nested inside a `when`/`if` in the tail statement itself —
 * disqualifies the whole body, because a return that fires there needs the interpreter's real
 * call-boundary `returnFlag` save/restore (see MuseInterp) to unwind ONLY the callee's own scope;
 * splicing it in as a plain expression would incorrectly unwind the CALLER's enclosing scope too.
 * Generator functions (`kind == Generator`) are never eligible (`yield` has no meaning spliced
 * outside its own generator frame).
 *
 * `ClassName.method(a0, a1, ...)` / `fnName(a0, a1, ...)` becomes `EBlock([EVar(param0, a0),
 * EVar(param1, a1), ..., <body statements, tail last>])` — binding each argument to a fresh local
 * (named after the parameter) rather than substituting the argument EXPRESSION directly into the
 * body: an argument can be side-effecting or expensive, and a parameter can appear zero, one, or
 * many times in the body — naive text/AST substitution would re-evaluate (or drop) it incorrectly.
 * `EBlock`'s last expression is its value, so the wrapped call still evaluates to the right thing
 * in expression position.
 *
 * Shadow-safety: a call site is only inlined if its callee name (`ClassName` or `fnName`) is NOT
 * also a locally-bound name (an assignment target, function parameter, for-loop variable, or
 * match-pattern binding) anywhere within the ENCLOSING declaration. Note this surface grammar has
 * no distinct declaration-vs-reassignment AST node for user code — `x = expr` covers both (`var`
 * itself parses as a harmless bare-identifier no-op token, stripped by the generic statement
 * fallback), so every assignment target is conservatively treated as a possible local binding.
 * This is computed once per top-level declaration being rewritten, not via precise block-scope
 * tracking — coarser than necessary (a shadow in one `if` branch suppresses inlining for the
 * whole declaration) but correct, and shadowing a global helper's name is rare enough that the
 * lost opportunities don't matter. This closes a real bug: the original single-expression-only
 * version of this pass rewrote `ClassName.method(...)` call sites purely syntactically, with no
 * shadow check at all, so a local `Signals = {...}` shadowing a real `Signals` class would have
 * been silently ignored by the inliner (compiled behavior would then diverge from the
 * interpreter, which DOES resolve the shadow correctly at runtime).
 *
 * Runs after TailCallPass (different target, no interaction) and before CallsiteIds.assign (so
 * any stateful builtin calls — crossover/rising/... — that get spliced into a NEW call site via
 * inlining are assigned identity in their POST-inline position, not their original one; identity
 * is defined per syntactic site, and inlining creates new syntactic sites).
 *
 * Depth-limited (not cycle-detected): a function that calls itself (directly, mutually, or
 * through another inlinable function) simply stops inlining after MAX_DEPTH — the innermost calls
 * are left as real calls rather than the pass looping forever or needing full call-graph analysis
 * to prove termination up front. Each spliced callee body is walked using the CALLEE's OWN bound-
 * name set (not the caller's) when resolving further inlining inside it — its arguments, however,
 * are resolved in the CALLER's scope/bound-set, matching real call semantics.
 */
class StaticInlinePass {
	static inline var MAX_DEPTH = 8;

	public static function transform(prog:MuseProgram):MuseProgram {
		var methods = collectInlinable(prog);
		var any = false;
		for (_ in methods.keys()) { any = true; break; }
		if (!any) return prog;

		var mapArm:MatchArm->Int->Map<String, Bool>->MatchArm = null;
		var mapStmts:Array<Stmt>->Int->Map<String, Bool>->Array<Stmt> = null;
		var mapExpr:Null<Expr>->Int->Map<String, Bool>->Null<Expr> = null;

		function inlineCall(info:{params:Array<String>, stmts:Array<Expr>, bound:Map<String, Bool>},
				args:Array<Expr>, depth:Int, callerBound:Map<String, Bool>):Expr {
			var mappedArgs = [for (a in args) mapExpr(a, depth, callerBound)];
			var binds:Array<Expr> = [for (i in 0...info.params.length)
				EVar(info.params[i], i < mappedArgs.length ? mappedArgs[i] : EConst(musescript.ast.Const.CNull))];
			var mappedBody = [for (s in info.stmts) mapExpr(s, depth + 1, info.bound)];
			return EBlock(binds.concat(mappedBody));
		}

		mapExpr = function(e:Null<Expr>, depth:Int, bound:Map<String, Bool>):Null<Expr> {
			if (e == null) return null;
			return switch (e) {
				case ECall(EField(EIdent(className), methodName), args)
					if (depth < MAX_DEPTH && !bound.exists(className) && methods.exists('$className.$methodName')):
					inlineCall(methods.get('$className.$methodName'), args, depth, bound);
				case ECall(EIdent(fnName), args)
					if (depth < MAX_DEPTH && !bound.exists(fnName) && methods.exists(fnName)):
					inlineCall(methods.get(fnName), args, depth, bound);
				case EConst(c): EConst(c);
				case EIdent(n): EIdent(n);
				case EBarField(n): EBarField(n);
				case EVar(n, init): EVar(n, mapExpr(init, depth, bound));
				case EBlock(es): EBlock([for (x in es) mapExpr(x, depth, bound)]);
				case EField(o, f): EField(mapExpr(o, depth, bound), f);
				case EBinop(op, a, b): EBinop(op, mapExpr(a, depth, bound), mapExpr(b, depth, bound));
				case EUnop(op, pre, x): EUnop(op, pre, mapExpr(x, depth, bound));
				case ECall(f, args): ECall(mapExpr(f, depth, bound), [for (a in args) mapExpr(a, depth, bound)]);
				case EIf(c, a, b): EIf(mapExpr(c, depth, bound), mapExpr(a, depth, bound), mapExpr(b, depth, bound));
				case EWhile(c, body): EWhile(mapExpr(c, depth, bound), mapExpr(body, depth, bound));
				case EFor(n, it, body): EFor(n, mapExpr(it, depth, bound), mapExpr(body, depth, bound));
				case EFunction(fargs, body, kind, name): EFunction(fargs, mapExpr(body, depth, bound), kind, name);
				case EReturn(v): EReturn(mapExpr(v, depth, bound));
				case EArray(a, i): EArray(mapExpr(a, depth, bound), mapExpr(i, depth, bound));
				case EArrayDecl(vs): EArrayDecl([for (v in vs) mapExpr(v, depth, bound)]);
				case EObject(fs): EObject([for (f in fs) { name: f.name, e: mapExpr(f.e, depth, bound) }]);
				case ETernary(c, a, b): ETernary(mapExpr(c, depth, bound), mapExpr(a, depth, bound), mapExpr(b, depth, bound));
				case EParent(x): EParent(mapExpr(x, depth, bound));
				case EMeta(n, margs, x): EMeta(n, [for (a in margs) mapExpr(a, depth, bound)], mapExpr(x, depth, bound));
				case ELookback(series, n): ELookback(mapExpr(series, depth, bound), mapExpr(n, depth, bound));
				case EMatch(scrutinee, arms): EMatch(mapExpr(scrutinee, depth, bound), [for (a in arms) mapArm(a, depth, bound)]);
				case EYield(x): EYield(mapExpr(x, depth, bound));
				case EYieldStar(x): EYieldStar(mapExpr(x, depth, bound));
				case ENew(cn, args): ENew(cn, [for (a in args) mapExpr(a, depth, bound)]);
				case EThis: EThis;
				case ESuper(m, args): ESuper(m, [for (a in args) mapExpr(a, depth, bound)]);
			};
		};

		mapArm = function(a:MatchArm, depth:Int, bound:Map<String, Bool>):MatchArm {
			return { pattern: a.pattern, guard: mapExpr(a.guard, depth, bound), body: mapExpr(a.body, depth, bound) };
		};

		mapStmts = function(ss:Array<Stmt>, depth:Int, bound:Map<String, Bool>):Array<Stmt> {
			return [for (s in ss) switch (s) {
				case OnBar(body): OnBar(mapStmts(body, depth, bound));
				case OnPosition(body): OnPosition(mapStmts(body, depth, bound));
				case OnTick(body): OnTick(mapStmts(body, depth, bound));
				case OnEvent(stream, body): OnEvent(stream, mapStmts(body, depth, bound));
				case ExprStmt(e): ExprStmt(mapExpr(e, depth, bound));
				case Assign(n, e): Assign(n, mapExpr(e, depth, bound));
				case ForIn(n, it, body): ForIn(n, mapExpr(it, depth, bound), mapStmts(body, depth, bound));
				case MatchFor(n, it, arms): MatchFor(n, mapExpr(it, depth, bound), [for (a in arms) mapArm(a, depth, bound)]);
				case Return(e): Return(mapExpr(e, depth, bound));
				case Yield(e): Yield(mapExpr(e, depth, bound));
				case YieldStar(e): YieldStar(mapExpr(e, depth, bound));
				case Order(kind, args): Order(kind, [for (a in args) mapExpr(a, depth, bound)]);
				case Block(body): Block(mapStmts(body, depth, bound));
				case When(cond, body): When(mapExpr(cond, depth, bound), mapStmts(body, depth, bound));
				case Use(m, args): Use(m, [for (a in args) { name: a.name, value: mapExpr(a.value, depth, bound) }]);
			}];
		};

		var decls = [for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body):
				var bound = boundOfStmts(body);
				StrategyDecl(n, mapStmts(body, 0, bound));
			case IndicatorDecl(n, iargs, body):
				var bound = boundOfExpr(body, iargs);
				IndicatorDecl(n, iargs, mapExpr(body, 0, bound));
			case ParamDecl(n, def, opts):
				ParamDecl(n, mapExpr(def, 0, boundOfExpr(def, [])), opts);
			case FnDecl(n, fargs, body, kind):
				FnDecl(n, fargs, mapExpr(body, 0, boundOfExpr(body, fargs)), kind);
			case MacroDecl(n, body):
				var bound = boundOfStmts(body);
				MacroDecl(n, mapStmts(body, 0, bound));
			case ModuleDecl(n, params, body): ModuleDecl(n, params, body);
			case TemplateDecl(n, params, retTy, body): TemplateDecl(n, params, retTy, body);
			case StmtTemplateDecl(n, params, body): StmtTemplateDecl(n, params, body);
			case EnumDecl(_, _): d;
			// Class bodies themselves are left ALONE here (not rewritten) so an inlinable
			// method's OWN body stays intact for lookup by future call sites; a static method
			// calling another inlinable static method is still handled correctly (mapExpr
			// recurses into `info.stmts` at inline TIME, with depth incrementing, not here).
			case ClassDecl(_, _, _, _, _): d;
		}];

		var progBound = boundOfStmts(prog.stmts);
		return { decls: decls, stmts: mapStmts(prog.stmts, 0, progBound), spans: prog.spans };
	}

	static function boundOfExpr(body:Null<Expr>, params:Array<String>):Map<String, Bool> {
		return BoundNames.ofExpr(body, params);
	}

	static function boundOfStmts(stmts:Array<Stmt>):Map<String, Bool> {
		return BoundNames.ofStmts(stmts);
	}

	static function collectInlinable(prog:MuseProgram):Map<String, {params:Array<String>, stmts:Array<Expr>, bound:Map<String, Bool>}> {
		var out = new Map();
		for (d in prog.decls) switch (d) {
			case ClassDecl(name, _, _, classMethods, _):
				for (m in classMethods) {
					if (!m.isStatic) continue;
					var flat = tryFlatten(m.body);
					if (flat == null) continue;
					out.set('$name.${m.name}', { params: m.args, stmts: flat, bound: boundOfExpr(m.body, m.args) });
				}
			case FnDecl(fname, fargs, body, kind):
				if (fname == null || kind != Normal) continue;
				var flat = tryFlatten(body);
				if (flat == null) continue;
				out.set(fname, { params: fargs, stmts: flat, bound: boundOfExpr(body, fargs) });
			default:
		}
		return out;
	}

	/**
	 * A "straight-line, tail-return" body -> the list of statement-expressions to splice
	 * (tail last, any wrapping `return` on the tail stripped), or null if ineligible. Subsumes
	 * the original single-expression case (zero leading statements, bare tail expr).
	 */
	static function tryFlatten(body:Expr):Null<Array<Expr>> {
		var stmts:Array<Expr> = switch (body) {
			case EBlock(es): es;
			default: [body];
		};
		if (stmts.length == 0) return null;
		for (i in 0...stmts.length - 1) {
			if (containsReturn(stmts[i])) return null;
		}
		var last = stmts[stmts.length - 1];
		var tail = switch (last) {
			case EReturn(e) if (e != null): e;
			case EReturn(null): null;
			default:
				if (containsReturn(last)) return null;
				last;
		};
		if (tail == null) return null;
		var result = stmts.slice(0, stmts.length - 1);
		result.push(tail);
		return result;
	}

	/** Does `e` contain a `return` that belongs to ITS OWN scope (not a nested `function`'s)? */
	static function containsReturn(e:Null<Expr>):Bool {
		if (e == null) return false;
		return switch (e) {
			case EReturn(_): true;
			case EFunction(_, _, _, _): false; // nested function's own return scope
			case EConst(_) | EIdent(_) | EBarField(_) | EThis: false;
			case EVar(_, init): containsReturn(init);
			case EBlock(es): es.exists(containsReturn);
			case EField(o, _): containsReturn(o);
			case EBinop(_, a, b): containsReturn(a) || containsReturn(b);
			case EUnop(_, _, x): containsReturn(x);
			case ECall(f, args): containsReturn(f) || args.exists(containsReturn);
			case EIf(c, a, b): containsReturn(c) || containsReturn(a) || containsReturn(b);
			case EWhile(c, body): containsReturn(c) || containsReturn(body);
			case EFor(_, it, body): containsReturn(it) || containsReturn(body);
			case EArray(a, i): containsReturn(a) || containsReturn(i);
			case EArrayDecl(vs): vs.exists(containsReturn);
			case EObject(fs): fs.exists(f -> containsReturn(f.e));
			case ETernary(c, a, b): containsReturn(c) || containsReturn(a) || containsReturn(b);
			case EParent(x): containsReturn(x);
			case EMeta(_, margs, x): margs.exists(containsReturn) || containsReturn(x);
			case ELookback(series, n): containsReturn(series) || containsReturn(n);
			case EMatch(scrutinee, arms): containsReturn(scrutinee)
				|| arms.exists(a -> containsReturn(a.guard) || containsReturn(a.body));
			case EYield(x): containsReturn(x);
			case EYieldStar(x): containsReturn(x);
			case ENew(_, args): args.exists(containsReturn);
			case ESuper(_, args): args.exists(containsReturn);
		};
	}

}
