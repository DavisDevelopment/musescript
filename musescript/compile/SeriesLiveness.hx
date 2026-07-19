package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;

/**
 * Which locals' per-bar histories can the emitted JS actually read?
 *
 * Every numeric `api.set` used to push into an unbounded per-name series
 * buffer, but the runtime only ever READS a local's history through two
 * doors, both statically visible:
 *   1. `api.lookback("name", n)` — emitted only for EIdent/EBarField
 *      lookback targets (`spread[1]`), and
 *   2. a runtime STRING naming the series in a series-position builtin arg
 *      (`sma("spread", 5)`) — and any string VALUE at runtime originates
 *      from some string literal in the program, unless strings are being
 *      constructed dynamically.
 *
 * So: track every lookback target and every string-literal value as
 * potentially-live series names, and BAIL to track-everything the moment
 * the program can manufacture strings (`str_*` builtins) or contains
 * pre-expansion declarations this pass shouldn't reason about. Over-tracking
 * is always safe (it is exactly the old behavior); under-tracking never
 * happens because both read doors are covered.
 *
 * The match on Stmt/Expr/Decl is intentionally exhaustive (no `default`)
 * so adding an AST node forces this pass to be revisited.
 */
class SeriesLiveness {
	public static function analyze(prog:MuseProgram):{trackAll:Bool, names:Array<String>} {
		var names = new Map<String, Bool>();
		var bail = false;

		function expr(e:Null<Expr>):Void {
			if (e == null || bail) return;
			switch (e) {
				case EConst(c):
					switch (c) {
						case CString(s): names.set(s, true);
						case CInt(_) | CFloat(_) | CBool(_) | CNull:
					}
				case EIdent(_):
				case EBarField(_):
				case EVar(_, init): expr(init);
				case EBlock(es): for (x in es) expr(x);
				case EField(o, _): expr(o);
				case EBinop(_, a, b): expr(a); expr(b);
				case EUnop(_, _, x): expr(x);
				case ECall(callee, args):
					switch (callee) {
						case EIdent(n):
							// dynamic string construction can name any series
							if (StringTools.startsWith(n, "str_")) bail = true;
						case _: expr(callee);
					}
					for (a in args) expr(a);
				case EIf(c, a, b): expr(c); expr(a); expr(b);
				case EWhile(c, body): expr(c); expr(body);
				case EFor(_, it, body): expr(it); expr(body);
				case EFunction(_, body, _, _): expr(body);
				case EReturn(v): expr(v);
				case EArray(a, i): expr(a); expr(i);
				case EArrayDecl(vs): for (v in vs) expr(v);
				case EObject(fs): for (f in fs) expr(f.e);
				case ETernary(c, a, b): expr(c); expr(a); expr(b);
				case EParent(x): expr(x);
				case EMeta(_, args, x): for (a in args) expr(a); expr(x);
				case ELookback(series, n):
					switch (series) {
						case EIdent(nm) | EBarField(nm): names.set(nm, true);
						case _: // withSeriesOffset re-eval reads locals from frames, not history
					}
					expr(series);
					expr(n);
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
					case OnBar(body): stmts(body);
					case OnPosition(body): stmts(body);
					case OnTick(body): stmts(body);
					case OnEvent(_, body): stmts(body);
					case ExprStmt(e): expr(e);
					case Assign(_, e): expr(e);
					case ForIn(_, iter, body): expr(iter); stmts(body);
					case MatchFor(_, iter, arms):
						expr(iter);
						for (a in arms) {
							expr(a.guard);
							expr(a.body);
						}
					case Return(e): expr(e);
					case Yield(e): expr(e);
					case YieldStar(e): expr(e);
					case Order(_, args): for (a in args) expr(a);
					case Block(body): stmts(body);
					case When(cond, body): expr(cond); stmts(body);
					case Use(_, _): bail = true; // pre-expansion construct
				}
			}
		}

		for (d in prog.decls) {
			if (bail) break;
			switch (d) {
				case StrategyDecl(_, body): stmts(body);
				case IndicatorDecl(_, _, body): expr(body);
				case ParamDecl(_, def, _): expr(def);
				case FnDecl(_, _, body, _): expr(body);
				case MacroDecl(_, body): stmts(body);
				case EnumDecl(_, _) | ModuleDecl(_, _, _) | TemplateDecl(_, _, _, _) | StmtTemplateDecl(_, _, _):
					bail = true; // should be expanded away before backends
				case ClassDecl(_, _, _, _, _):
					bail = true; // method/ctor bodies are interp-only, not scanned here
			}
		}
		if (!bail) stmts(prog.stmts);

		return { trackAll: bail, names: bail ? [] : [for (n in names.keys()) n] };
	}
}
