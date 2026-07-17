package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Pattern;
import musescript.ast.MatchArm;

/**
 * Which strategy-body top-level locals can the JS emitter compile to real
 * `let` variables instead of routing every read/write through `api.get`/
 * `api.set` (a Map lookup + frame walk each time)?
 *
 * The insight: a strategy's top-level `fast = ema(close, 5)`-style assigns
 * (JsEmitter.collectStrategyHooks calls this the "prelude") run UNCONDITIONALLY
 * at the very start of every bar, before anything can read them. So there is
 * no "declared but not yet assigned this bar" window to get wrong — a hoisted
 * `let fast;` is always overwritten before any read, on every single bar,
 * exactly like the Map-backed frame slot it replaces. Declaring the `let`
 * INSIDE the emitted on-bar function body (not in an enclosing scope) is
 * enough: whether the binding "persists" between separate calls of that
 * function is unobservable, because nothing ever reads it before the next
 * call's prelude re-assigns it.
 *
 * A candidate name is only actually hoisted if BOTH hold:
 *   1. It never escapes into a scope this pass can't reason about: a closure
 *      parameter/name (EFunction), a loop variable (ForIn/EFor/MatchFor), a
 *      match-arm pattern bind, an explicit `var` declaration (EVar), or a
 *      ParamDecl/FnDecl/IndicatorDecl/MacroDecl name. Any of those and the
 *      name keeps routing through api.get/api.set everywhere (the emitter
 *      makes the hoist/no-hoist decision per name, uniformly, program-wide).
 *   2. SeriesLiveness doesn't need to push its value into a per-name series
 *      buffer (a hoisted `let` has no history — a name whose lookback or
 *      string-literal series reference SeriesLiveness detected must keep
 *      going through api.set, which is what performs that push).
 *
 * Over-excluding is always safe (falls back to the existing api.get/set
 * path for that name); this pass must never mark a name hoistable that the
 * emitter can't prove safe.
 */
class PreludeVars {
	public static function analyze(
		prog:MuseProgram,
		liveness:{trackAll:Bool, names:Array<String>}
	):Map<String, Bool> {
		var candidates = preludeCandidates(prog);
		if (candidates.length == 0) return new Map();

		var liveSet = new Map<String, Bool>();
		if (!liveness.trackAll) for (n in liveness.names) liveSet.set(n, true);

		var escaped = escapingNames(prog);
		if (escaped == null) return new Map(); // pre-expansion construct present — bail whole pass

		var out = new Map<String, Bool>();
		for (n in candidates) {
			if (escaped.exists(n)) continue;
			if (liveness.trackAll || liveSet.exists(n)) continue; // needs series history
			out.set(n, true);
		}
		return out;
	}

	/**
	 * Names assigned by a top-level `Assign` directly under a StrategyDecl
	 * body (or one Block deep) — mirrors JsEmitter.collectStrategyHooks'
	 * prelude extraction exactly, since that's what "runs unconditionally
	 * before every read this bar" means.
	 */
	static function preludeCandidates(prog:MuseProgram):Array<String> {
		var names = new Map<String, Bool>();
		function fromBody(body:Array<Stmt>):Void {
			for (s in body) switch (s) {
				case Assign(n, _): names.set(n, true);
				case Block(inner):
					for (s2 in inner) switch (s2) {
						case Assign(n, _): names.set(n, true);
						default:
					}
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body): fromBody(body);
			default:
		}
		return [for (n in names.keys()) n];
	}

	/**
	 * Whole-program scan for names used in a way this pass can't safely
	 * hoist. Returns null (bail everything) if the program still contains a
	 * pre-expansion construct this walk isn't exhaustive over.
	 */
	static function escapingNames(prog:MuseProgram):Null<Map<String, Bool>> {
		var esc = new Map<String, Bool>();
		var bail = false;
		function hit(n:Null<String>):Void {
			if (n != null) esc.set(n, true);
		}
		function pat(p:Pattern):Void {
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
			if (e == null || bail) return;
			switch (e) {
				case EConst(_) | EIdent(_) | EBarField(_):
				case EVar(n, init): hit(n); expr(init); // explicit `var` — distinct decl form, don't hoist-alias it
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
			}
		}
		function stmts(ss:Array<Stmt>):Void {
			for (s in ss) {
				if (bail) return;
				switch (s) {
					case OnBar(body) | OnPosition(body) | OnTick(body): stmts(body);
					case OnEvent(_, body): stmts(body);
					case ExprStmt(e): expr(e);
					case Assign(_, e): expr(e); // target name itself is fine — it's the prelude shape
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
			if (bail) break;
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
				case ModuleDecl(_, _, _) | TemplateDecl(_, _, _, _) | StmtTemplateDecl(_, _, _):
					bail = true;
			}
		}
		if (!bail) stmts(prog.stmts);
		return bail ? null : esc;
	}
}
