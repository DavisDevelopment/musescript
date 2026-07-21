package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;

using Lambda;

/**
 * Deduplicates a REPEATED, PURE, non-trivial value computed twice within the same flat
 * statement list: the second `y = <same expr as x's rhs>` becomes `y = x` (no new temp needed
 * -- `x` already holds it); the second `when <same cond as an earlier when>` becomes `when
 * <hoisted temp>` (a temp IS needed here, inserted right before the condition's first
 * occurrence, since a bare condition has no name of its own to alias to).
 *
 * Deliberately narrow scope, by design, not oversight:
 *  - Only `Assign` targets and `When` conditions are candidate "value slots" -- the two most
 *    common places a helper's inlined result actually gets reused in real strategy code. Return
 *    values / bare ExprStmt values are NOT deduplicated (rare enough as authored patterns that
 *    the added surface area isn't worth it).
 *  - Only WHOLE value slots are compared (via MusePrinter's printExpr as the structural-equality
 *    key), never arbitrary NESTED sub-expressions within a larger expression tree. Real subtree-
 *    level CSE needs to reason about overlapping/nested duplicate regions and safe hoist points
 *    inside arbitrary expression shapes; this pass sidesteps that entirely by only ever comparing
 *    already-flat, already-statement-boundary-separated slots.
 *  - Only within a SINGLE flat statement list (one `onBar`/`when`/`for` body, etc.) — never
 *    hoists across a nested body's boundary into its parent, or vice versa. Each nested body
 *    gets its own independent dedup pass.
 *  - `isPure` is a conservative allowlist (constants, identifiers, field/array reads, arithmetic/
 *    comparison/logical composition, ternary/if with pure branches): ANY call (`ECall`), `yield`,
 *    `new`, nested `function` literal, assignment expression, loop, or `match` disqualifies a
 *    candidate outright, rather than trying to prove any of those are safe to dedupe. In
 *    particular this means a repeated STATEFUL builtin call (`crossover(...)`, `rising(...)`,
 *    an inlined helper's own internal calls, ...) is never touched — CallsiteIds assigns those
 *    per-syntactic-site identity specifically because two "identical-looking" call sites can
 *    carry independent runtime state, so conflating them would be a real correctness bug, not
 *    just a missed optimization.
 *
 * Two-pass per flat list (count first, only touch keys seen >= 2 times) specifically so a
 * condition/value that only appears ONCE is never given a pointless extra temp-var wrapper.
 *
 * Runs after ConstFold (folding first collapses literal noise, so two expressions that are only
 * "the same" once their literal sub-parts are reduced get recognized as duplicates) and before
 * CallsiteIds.assign (dedup can delete a whole duplicate `when` condition's own copy of a
 * stateful-adjacent expression tree, so identity must be assigned to what's actually left).
 */
class CommonSubexprElim {
	public static function transform(prog:MuseProgram):MuseProgram {
		var decls = [for (d in prog.decls) switch (d) {
			case StrategyDecl(n, body): StrategyDecl(n, mapStmts(body));
			case MacroDecl(n, body): MacroDecl(n, mapStmts(body));
			// IndicatorDecl/FnDecl/ClassDecl method/ctor bodies are single Expr trees (not flat
			// Stmt lists at this level) -- this pass only targets the Stmt-list shape (onBar/
			// when/for bodies), where the Assign/When "value slot" pattern actually applies.
			default: d;
		}];
		return { decls: decls, stmts: mapStmts(prog.stmts), spans: prog.spans };
	}

	static function mapStmts(ss:Array<Stmt>):Array<Stmt> {
		var recursed = [for (s in ss) switch (s) {
			case OnBar(body): OnBar(mapStmts(body));
			case OnPosition(body): OnPosition(mapStmts(body));
			case OnTick(body): OnTick(mapStmts(body));
			case OnEvent(stream, body): OnEvent(stream, mapStmts(body));
			case ForIn(n, it, body): ForIn(n, it, mapStmts(body));
			case Block(body): Block(mapStmts(body));
			case When(cond, body): When(cond, mapStmts(body));
			default: s;
		}];
		return dedupFlatList(recursed);
	}

	static function dedupFlatList(ss:Array<Stmt>):Array<Stmt> {
		var printer = new MusePrinter();
		var counts = new Map<String, Int>();
		function tally(e:Expr):Void {
			if (!isPure(e) || isTrivial(e)) return;
			var key = printer.printExpr(e);
			counts.set(key, (counts.exists(key) ? counts.get(key) : 0) + 1);
		}
		for (s in ss) switch (s) {
			case Assign(_, e): tally(e);
			case When(cond, _): tally(cond);
			default:
		}

		var out:Array<Stmt> = [];
		var boundName = new Map<String, String>();
		var tmpId = 0;
		for (s in ss) switch (s) {
			case Assign(n, e) if (isPure(e) && !isTrivial(e) && counts.get(printer.printExpr(e)) >= 2):
				var key = printer.printExpr(e);
				if (boundName.exists(key)) {
					out.push(Assign(n, EIdent(boundName.get(key))));
				} else {
					boundName.set(key, n);
					out.push(Assign(n, e));
				}
			case When(cond, body) if (isPure(cond) && !isTrivial(cond) && counts.get(printer.printExpr(cond)) >= 2):
				var key = printer.printExpr(cond);
				if (boundName.exists(key)) {
					out.push(When(EIdent(boundName.get(key)), body));
				} else {
					var tmpName = "__cse" + (tmpId++);
					out.push(Assign(tmpName, cond));
					boundName.set(key, tmpName);
					out.push(When(EIdent(tmpName), body));
				}
			default:
				out.push(s);
		}
		return out;
	}

	static function isTrivial(e:Expr):Bool {
		return switch (e) {
			case EConst(_) | EIdent(_) | EBarField(_): true;
			default: false;
		};
	}

	/** Conservative allowlist -- see class doc comment for the full rationale. */
	static function isPure(e:Null<Expr>):Bool {
		if (e == null) return true;
		return switch (e) {
			case EConst(_) | EIdent(_) | EBarField(_) | EThis: true;
			case EField(o, _): isPure(o);
			case EBinop("=", _, _): false;
			case EBinop(_, a, b): isPure(a) && isPure(b);
			case EUnop(op, _, x): (op == "-" || op == "!") && isPure(x);
			case EArray(a, i): isPure(a) && isPure(i);
			case EArrayDecl(vs): vs.foreach(isPure);
			case EObject(fs): fs.foreach(f -> isPure(f.e));
			case ETernary(c, a, b): isPure(c) && isPure(a) && isPure(b);
			case EIf(c, a, b): isPure(c) && isPure(a) && (b == null || isPure(b));
			case EParent(x): isPure(x);
			case ELookback(series, n): isPure(series) && isPure(n);
			// Everything else (ECall, EVar, EBlock, EWhile, EFor, EFunction, EReturn, EMeta,
			// EMatch, EYield, EYieldStar, ENew, ESuper) is conservatively impure/too complex.
			default: false;
		};
	}
}
