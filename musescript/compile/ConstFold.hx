package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;

using Lambda;

/**
 * Fold compile-time-constant sub-expressions and eliminate statically-decidable branches:
 *
 *  - `EBinop(op, EConst(a), EConst(b))` for arithmetic/comparison/logical ops -> the literal
 *    result, computed via the SAME Dynamic operations MuseInterp.binop uses on the SAME
 *    extracted values (not a re-derived set of typed rules), so there is no risk of a fold
 *    disagreeing with what the interpreter would have produced anyway.
 *  - `&&`/`||` with a constant LEFT operand short-circuits without even looking at whether the
 *    right operand is foldable — `false && expr` / `true || expr` never evaluates `expr` at
 *    runtime either, so dropping it at compile time is not a behavior change, just doing the
 *    same skip earlier. (The reverse — constant RIGHT, non-constant left — is NOT folded: the
 *    left side must still run for its truthiness/side effects.)
 *  - `EUnop("-"/"!", true, EConst(c))` — negation/not on a literal.
 *  - `EIf`/`ETernary` with a constant condition -> the live branch only (an EIf with a constant-
 *    false condition and no else branch folds to `EConst(CNull)`, matching MuseInterp's
 *    `eelse != null ? evalExpr(eelse) : null` fallback exactly).
 *  - `When(constCond, body)` (Stmt level) -> `body` spliced in unconditionally (true) or dropped
 *    entirely (false).
 *  - Nested `EBlock`s flatten into their parent (`EBlock([a, EBlock([b,c]), d])` ->
 *    `EBlock([a,b,c,d])`) — semantically free in this language specifically because
 *    MuseInterp's `EBlock` case never pushes a new scope frame (see its doc comment: this
 *    grammar's `x = expr` covers both declaration and reassignment with no block boundary at
 *    all), so a nested block is nothing but a wrapper. Repeated StaticInlinePass splicing
 *    otherwise accumulates one block-nesting level per inline, unboundedly with MAX_DEPTH
 *    recursive inlining. SKIPPED whenever the nested block contains a `yield` anywhere: the
 *    interpreter's generator-resume machinery (`BlockResume`) matches a suspended block by AST
 *    NODE IDENTITY, not shape — flattening would fabricate a brand-new block object that no
 *    longer matches a resume point captured before this pass ran.
 *
 * Primarily a code-size/perf win on its own, but the real payoff is compounding with
 * StaticInlinePass: inlining substitutes literal default-argument values into call bodies,
 * which very often makes a `when`/comparison inside that body constant-foldable — e.g. a
 * helper called with a literal threshold turns `x > threshold` into a fold-eligible shape only
 * AFTER inlining splices the literal in. Runs after StaticInlinePass for exactly this reason,
 * and before CallsiteIds.assign (folding can delete a whole branch containing a stateful
 * builtin call — crossover/rising/... — so identity must be assigned to what's actually LEFT
 * post-fold, not what was theoretically there before).
 */
class ConstFold {
	public static function transform(prog:MuseProgram):MuseProgram {
		var decls = [for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body): StrategyDecl(n, mapStmts(body));
			case IndicatorDecl(n, iargs, body): IndicatorDecl(n, iargs, mapExpr(body));
			case ParamDecl(n, def, opts): ParamDecl(n, mapExpr(def), opts);
			case FnDecl(n, fargs, body, kind): FnDecl(n, fargs, mapExpr(body), kind);
			case MacroDecl(n, body): MacroDecl(n, mapStmts(body));
			case ModuleDecl(n, params, body): ModuleDecl(n, params, body);
			case TemplateDecl(n, params, retTy, body): TemplateDecl(n, params, retTy, body);
			case StmtTemplateDecl(n, params, body): StmtTemplateDecl(n, params, body);
			case EnumDecl(_, _): d;
			case ClassDecl(name, parent, fields, methods, ctor):
				ClassDecl(name, parent, fields,
					[for (m in methods) { name: m.name, args: m.args, body: mapExpr(m.body), isStatic: m.isStatic }],
					ctor != null ? { args: ctor.args, body: mapExpr(ctor.body) } : null);
		}];
		return { decls: decls, stmts: mapStmts(prog.stmts), spans: prog.spans };
	}

	static function mapExpr(e:Null<Expr>):Null<Expr> {
		if (e == null) return null;
		return switch (e) {
			case EConst(c): EConst(c);
			case EIdent(n): EIdent(n);
			case EBarField(n): EBarField(n);
			case EVar(n, init): EVar(n, mapExpr(init));
			case EBlock(es): EBlock(flattenBlockList([for (x in es) mapExpr(x)]));
			case EField(o, f): EField(mapExpr(o), f);
			case EBinop("&&", a, b):
				var fa = mapExpr(a);
				switch (fa) {
					case EConst(c): truthy(litValue(c)) ? mapExpr(b) : EConst(CBool(false));
					default: EBinop("&&", fa, mapExpr(b));
				}
			case EBinop("||", a, b):
				var fa = mapExpr(a);
				switch (fa) {
					case EConst(c): truthy(litValue(c)) ? EConst(CBool(true)) : mapExpr(b);
					default: EBinop("||", fa, mapExpr(b));
				}
			case EBinop(op, a, b):
				var fa = mapExpr(a);
				var fb = mapExpr(b);
				switch [fa, fb] {
					case [EConst(ca), EConst(cb)]:
						var folded = foldBinop(op, ca, cb);
						folded != null ? EConst(folded) : EBinop(op, fa, fb);
					default: EBinop(op, fa, fb);
				}
			case EUnop(op, pre, x):
				var fx = mapExpr(x);
				if (pre) switch [op, fx] {
					case ["-", EConst(CInt(v))]: EConst(CInt(-v));
					case ["-", EConst(CFloat(v))]: EConst(CFloat(-v));
					case ["!", EConst(c)]: EConst(CBool(!truthy(litValue(c))));
					default: EUnop(op, pre, fx);
				} else EUnop(op, pre, fx);
			case ECall(f, args): ECall(mapExpr(f), [for (a in args) mapExpr(a)]);
			case EIf(c, a, b):
				var fc = mapExpr(c);
				switch (fc) {
					case EConst(cc): truthy(litValue(cc)) ? mapExpr(a) : (b != null ? mapExpr(b) : EConst(CNull));
					default: EIf(fc, mapExpr(a), mapExpr(b));
				}
			case EWhile(c, body): EWhile(mapExpr(c), mapExpr(body));
			case EFor(n, it, body): EFor(n, mapExpr(it), mapExpr(body));
			case EFunction(fargs, body, kind, name): EFunction(fargs, mapExpr(body), kind, name);
			case EReturn(v): EReturn(mapExpr(v));
			case EArray(a, i): EArray(mapExpr(a), mapExpr(i));
			case EArrayDecl(vs): EArrayDecl([for (v in vs) mapExpr(v)]);
			case EObject(fs): EObject([for (f in fs) { name: f.name, e: mapExpr(f.e) }]);
			case ETernary(c, a, b):
				var fc = mapExpr(c);
				switch (fc) {
					case EConst(cc): truthy(litValue(cc)) ? mapExpr(a) : mapExpr(b);
					default: ETernary(fc, mapExpr(a), mapExpr(b));
				}
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

	static function mapArm(a:MatchArm):MatchArm {
		return { pattern: a.pattern, guard: mapExpr(a.guard), body: mapExpr(a.body) };
	}

	static function mapStmts(ss:Array<Stmt>):Array<Stmt> {
		var out:Array<Stmt> = [];
		for (s in ss) switch (s) {
			case OnBar(body): out.push(OnBar(mapStmts(body)));
			case OnPosition(body): out.push(OnPosition(mapStmts(body)));
			case OnTick(body): out.push(OnTick(mapStmts(body)));
			case OnEvent(stream, body): out.push(OnEvent(stream, mapStmts(body)));
			case ExprStmt(e): out.push(ExprStmt(mapExpr(e)));
			case Assign(n, e): out.push(Assign(n, mapExpr(e)));
			case ForIn(n, it, body): out.push(ForIn(n, mapExpr(it), mapStmts(body)));
			case MatchFor(n, it, arms): out.push(MatchFor(n, mapExpr(it), [for (a in arms) mapArm(a)]));
			case Return(e): out.push(Return(mapExpr(e)));
			case Yield(e): out.push(Yield(mapExpr(e)));
			case YieldStar(e): out.push(YieldStar(mapExpr(e)));
			case Order(kind, args): out.push(Order(kind, [for (a in args) mapExpr(a)]));
			case Block(body): out.push(Block(mapStmts(body)));
			case When(cond, body):
				var fc = mapExpr(cond);
				switch (fc) {
					case EConst(cc):
						if (truthy(litValue(cc))) for (x in mapStmts(body)) out.push(x);
						// else: condition never fires -- drop the whole `when` block.
					default:
						out.push(When(fc, mapStmts(body)));
				}
			case Use(m, args): out.push(Use(m, [for (a in args) { name: a.name, value: mapExpr(a.value) }]));
		}
		return out;
	}

	static function flattenBlockList(es:Array<Expr>):Array<Expr> {
		var out:Array<Expr> = [];
		for (e in es) switch (e) {
			case EBlock(inner) if (!inner.exists(containsYield)):
				for (x in flattenBlockList(inner)) out.push(x);
			default:
				out.push(e);
		}
		return out;
	}

	/** Does `e` contain a `yield` belonging to ITS OWN generator frame (not a nested `function`'s)? */
	static function containsYield(e:Null<Expr>):Bool {
		if (e == null) return false;
		return switch (e) {
			case EYield(_) | EYieldStar(_): true;
			case EFunction(_, _, _, _): false; // nested function's own generator scope
			case EConst(_) | EIdent(_) | EBarField(_) | EThis: false;
			case EVar(_, init): containsYield(init);
			case EBlock(es): es.exists(containsYield);
			case EField(o, _): containsYield(o);
			case EBinop(_, a, b): containsYield(a) || containsYield(b);
			case EUnop(_, _, x): containsYield(x);
			case ECall(f, args): containsYield(f) || args.exists(containsYield);
			case EIf(c, a, b): containsYield(c) || containsYield(a) || containsYield(b);
			case EWhile(c, body): containsYield(c) || containsYield(body);
			case EFor(_, it, body): containsYield(it) || containsYield(body);
			case EReturn(v): containsYield(v);
			case EArray(a, i): containsYield(a) || containsYield(i);
			case EArrayDecl(vs): vs.exists(containsYield);
			case EObject(fs): fs.exists(f -> containsYield(f.e));
			case ETernary(c, a, b): containsYield(c) || containsYield(a) || containsYield(b);
			case EParent(x): containsYield(x);
			case EMeta(_, margs, x): margs.exists(containsYield) || containsYield(x);
			case ELookback(series, n): containsYield(series) || containsYield(n);
			case EMatch(scrutinee, arms): containsYield(scrutinee)
				|| arms.exists(a -> containsYield(a.guard) || containsYield(a.body));
			case ENew(_, args): args.exists(containsYield);
			case ESuper(_, args): args.exists(containsYield);
		};
	}

	static function litValue(c:Const):Dynamic {
		return switch (c) {
			case CInt(v): v;
			case CFloat(v): v;
			case CString(v): v;
			case CBool(v): v;
			case CNull: null;
		};
	}

	static function asConst(v:Dynamic):Null<Const> {
		if (v == null) return CNull;
		if (Std.isOfType(v, Bool)) return CBool(v);
		if (Std.isOfType(v, String)) return CString(v);
		if (Std.isOfType(v, Int)) return CInt(v);
		if (Std.isOfType(v, Float)) return CFloat(v);
		return null;
	}

	/** Same unbox rules as MuseInterp.toNum — never `cast v` (JVM Dynamic Float→Int truncate). */
	static function toNum(v:Dynamic):Float {
		if (v == null) return 0;
		if (Std.isOfType(v, Int)) return (v : Int) * 1.0;
		if (Std.isOfType(v, Float)) return (v : Float);
		var n = Std.parseFloat(Std.string(v));
		return Math.isNaN(n) ? 0.0 : n;
	}

	static function isStringy(v:Dynamic):Bool {
		return Std.isOfType(v, String);
	}

	/** Mirrors MuseInterp.truthy exactly. */
	static function truthy(v:Dynamic):Bool {
		if (v == null) return false;
		if (v == false) return false;
		if (v == 0) return false;
		if (v == "") return false;
		return true;
	}

	/**
	 * Mirrors MuseInterp.binop. Numeric `+` goes through toNum (not Dynamic `left + right`) so
	 * the JVM backend cannot unify fold locals to Int and truncate float literals — same trap
	 * that broke MuseInterp's shared `left`/`right` bindings (see binop's doc comment).
	 *
	 * String concat is handled BEFORE the numeric switch: a single `switch` arm that returns
	 * either String or Double makes the Haxe JVM emitter emit inconsistent stackmap frames
	 * (VerifyError on class load).
	 */
	static function foldBinop(op:String, a:Const, b:Const):Null<Const> {
		var left:Dynamic = litValue(a);
		var right:Dynamic = litValue(b);
		if (op == "+") {
			var sum:Dynamic;
			if (isStringy(left) || isStringy(right))
				sum = Std.string(left) + Std.string(right);
			else
				sum = toNum(left) + toNum(right);
			return asConst(sum);
		}
		var result:Dynamic = switch (op) {
			case "-": toNum(left) - toNum(right);
			case "*": toNum(left) * toNum(right);
			case "/": toNum(left) / toNum(right);
			case "%": toNum(left) % toNum(right);
			case "==": left == right;
			case "!=": left != right;
			case "<": toNum(left) < toNum(right);
			case "<=": toNum(left) <= toNum(right);
			case ">": toNum(left) > toNum(right);
			case ">=": toNum(left) >= toNum(right);
			default: null; // unhandled op (e.g. "=") -- never fold
		};
		return result == null ? null : asConst(result);
	}
}
