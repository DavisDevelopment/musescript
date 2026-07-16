package musescript.ast;

/**
 * JSON export for the boolean/scalar expression SUBSET of MuseScript's Expr AST -- EConst,
 * EIdent, EBinop, EUnop (transparent through EParent). Deliberately not a full-language AST
 * export: Forge's reverse projection (mobile's museAstToForgeGraph.js) only ever needs to walk
 * exactly the shape graphToMuseSource() itself emits (a comparison/logic expression tree over
 * named params and constants), and the plan's own instruction is to REJECT unsupported full-
 * language constructs honestly, not silently flatten them. Anything outside this subset
 * (EFunction, EMatch, EFor, EWhile, EYield, EMeta, ...) serializes to {"kind":"unsupported"} with
 * a short description, never a guess.
 */
class ExprJson {
	public static function toJson(e:Expr):Dynamic {
		return switch (e) {
			case EParent(inner):
				toJson(inner);
			case EConst(c):
				switch (c) {
					case CInt(v): { kind: "const", value: v };
					case CFloat(v): { kind: "const", value: v };
					case CString(v): { kind: "const_string", value: v };
					case CBool(v): { kind: "const_bool", value: v };
					case CNull: { kind: "unsupported", node: "null constant" };
				}
			case EIdent(name):
				{ kind: "ident", name: name };
			case EBinop(op, left, right):
				{ kind: "binop", op: op, left: toJson(left), right: toJson(right) };
			case EUnop(op, prefix, inner):
				{ kind: "unop", op: op, prefix: prefix, e: toJson(inner) };
			default:
				{ kind: "unsupported", node: exprLabel(e) };
		};
	}

	static function exprLabel(e:Expr):String {
		// Std.string(enum) on Haxe enums prints the constructor name + args -- truncate so a
		// deeply nested unsupported subtree doesn't produce an unbounded string.
		var s = Std.string(e);
		return s.length > 120 ? s.substr(0, 120) + "…" : s;
	}

	/**
	 * Finds the single `if (<cond>) long();` pattern inside the program's @on(bar) block --
	 * the EXACT shape mobile/src/lab/forge/forgeMuseProjection.js's graphToMuseSource() emits.
	 * For the flat legacy surface (`{ @strategy(...) @param(...) @on(bar){...} }`, everything
	 * this project's .ms sources use), @strategy/@param become top-level Decls and @on(bar)
	 * becomes a top-level Stmt in prog.stmts -- NOT nested inside StrategyDecl's own `body`
	 * (confirmed empirically: StrategyDecl's body is `[]` for every source tested this session;
	 * a `body:Array<Stmt>` parameter exists on the Decl for a nested-block surface this project
	 * doesn't use). Search prog.stmts first (the real case), fall back to a StrategyDecl-nested
	 * search in case some other source shape populates it.
	 *
	 * Returns {ok:true, cond:<json>} or {ok:false, reason}. Any richer on_bar body (multiple
	 * statements, an else branch, short()/flat() instead of long(), var declarations) is an
	 * honest rejection, not a best-effort guess -- Forge can't represent those anyway.
	 */
	public static function extractLongCondition(prog:MuseProgram):Dynamic {
		var onBar = findOnBar(prog.stmts);
		if (onBar == null) {
			for (d in prog.decls) {
				switch (d) {
					case StrategyDecl(_, body):
						onBar = findOnBar(body);
						if (onBar != null) break;
					default:
				}
			}
		}
		if (onBar == null) return { ok: false, reason: "no @on(bar) block found" };
		if (onBar.length != 1) {
			return { ok: false, reason: 'expected exactly one statement inside @on(bar), found ${onBar.length}' };
		}
		return switch (onBar[0]) {
			case ExprStmt(EIf(cond, ECall(EIdent("long"), []), null)):
				{ ok: true, cond: toJson(cond) };
			case Order(_, _):
				{ ok: false, reason: 'expected `if (cond) long();`, found a bare order call' };
			default:
				{ ok: false, reason: "on_bar body isn't the `if (cond) long();` shape Forge round-trips" };
		}
	}

	static function findOnBar(stmts:Array<Stmt>):Null<Array<Stmt>> {
		for (s in stmts) {
			switch (s) {
				case OnBar(body): return body;
				default:
			}
		}
		return null;
	}
}
