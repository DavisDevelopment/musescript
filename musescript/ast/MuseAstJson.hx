package musescript.ast;

import musescript.checker.MuseChecker;
import musescript.types.MuseType;
import musescript.types.MuseTypes;

/**
 * Full bidirectional JSON export for MuseScript's Expr/Stmt/Pattern AST -- supersedes
 * ExprJson.hx's narrow boolean-subset scope. "If it's a valid computation, it's a valid
 * tradelogic tree" (2026-07-15 direction): Forge's canonical model is no longer boolean-only:
 * any Expr/Stmt is a legal node, tagged with a `type` (Bool/Series/Scalar/Void/String/Window/...,
 * MuseType's own lattice) computed by the REAL TypeChecker, not reimplemented inference. The
 * type tag is what a no-code editor uses to restrict a socket to (for example) Bool-only content.
 *
 * Every node kind MuseScript's grammar defines is covered. The only genuinely unsupported shapes
 * are ones with no meaningful graph-node representation (EMeta survives only where it wraps a
 * plain sub-expression; PatGuard's untyped Dynamic guard is dropped with a note) -- everything
 * else round-trips.
 */
class MuseAstJson {
	/**
	 * `checker`, if given, must already have had `.check(prog)` called on the whole program (so
	 * its env has every @param/module binding) -- typeOf() is then accurate for every subnode.
	 * Pass null to skip type tagging entirely (all nodes get type:"Unknown").
	 */
	public static function exprToJson(e:Expr, ?checker:MuseChecker):Dynamic {
		var node = exprToJsonUntyped(e, checker);
		if (checker != null && !Reflect.hasField(node, "type")) {
			try {
				Reflect.setField(node, "type", MuseTypes.toString(checker.typeOf(e)));
			} catch (_:Dynamic) {
				Reflect.setField(node, "type", "Unknown");
			}
		}
		return node;
	}

	static function exprToJsonUntyped(e:Expr, ?checker:MuseChecker):Dynamic {
		return switch (e) {
			case EParent(inner):
				exprToJson(inner, checker);
			case EConst(c):
				switch (c) {
					case CInt(v): { kind: "const", value: v };
					case CFloat(v): { kind: "const", value: v };
					case CString(v): { kind: "const_string", value: v };
					case CBool(v): { kind: "const_bool", value: v };
					case CNull: { kind: "const_null" };
				}
			case EIdent(name):
				{ kind: "ident", name: name };
			case EVar(name, init):
				{ kind: "var", name: name, init: init != null ? exprToJson(init, checker) : null };
			case EBlock(exprs):
				{ kind: "block", exprs: [for (x in exprs) exprToJson(x, checker)] };
			case EField(inner, f):
				{ kind: "field", e: exprToJson(inner, checker), field: f };
			case EBinop(op, left, right):
				{ kind: "binop", op: op, left: exprToJson(left, checker), right: exprToJson(right, checker) };
			case EUnop(op, prefix, inner):
				{ kind: "unop", op: op, prefix: prefix, e: exprToJson(inner, checker) };
			case ECall(callee, args):
				{ kind: "call", callee: exprToJson(callee, checker), args: [for (a in args) exprToJson(a, checker)] };
			case EIf(cond, eif, eelse):
				{ kind: "if", cond: exprToJson(cond, checker), then: exprToJson(eif, checker),
				  otherwise: eelse != null ? exprToJson(eelse, checker) : null };
			case EWhile(cond, body):
				{ kind: "while", cond: exprToJson(cond, checker), body: exprToJson(body, checker) };
			case EFor(name, it, body):
				{ kind: "for", name: name, iter: exprToJson(it, checker), body: exprToJson(body, checker) };
			case EFunction(args, body, kind, name):
				{ kind: "function", args: args, body: exprToJson(body, checker),
				  fnKind: Std.string(kind), name: name };
			case EReturn(inner):
				{ kind: "return", e: inner != null ? exprToJson(inner, checker) : null };
			case EArray(inner, index):
				{ kind: "index", e: exprToJson(inner, checker), index: exprToJson(index, checker) };
			case EArrayDecl(values):
				{ kind: "array", values: [for (v in values) exprToJson(v, checker)] };
			case EObject(fields):
				{ kind: "object", fields: [for (f in fields) { name: f.name, e: exprToJson(f.e, checker) }] };
			case ETernary(cond, eif, eelse):
				{ kind: "ternary", cond: exprToJson(cond, checker), then: exprToJson(eif, checker), otherwise: exprToJson(eelse, checker) };
			case EMeta(name, args, inner):
				{ kind: "meta", name: name, args: [for (a in args) exprToJson(a, checker)], e: exprToJson(inner, checker) };
			case ELookback(series, n):
				{ kind: "lookback", series: exprToJson(series, checker), n: exprToJson(n, checker) };
			case EMatch(scrutinee, arms):
				{ kind: "match", scrutinee: exprToJson(scrutinee, checker), arms: [for (a in arms) matchArmToJson(a, checker)] };
			case EYield(inner):
				{ kind: "yield", e: exprToJson(inner, checker) };
			case EYieldStar(inner):
				{ kind: "yieldStar", e: exprToJson(inner, checker) };
			case EBarField(name):
				{ kind: "barfield", name: name };
		};
	}

	static function matchArmToJson(a:MatchArm, ?checker:MuseChecker):Dynamic {
		return {
			pattern: patternToJson(a.pattern),
			guard: a.guard != null ? exprToJson(a.guard, checker) : null,
			body: exprToJson(a.body, checker),
		};
	}

	static function patternToJson(p:Pattern):Dynamic {
		return switch (p) {
			case PatWild: { kind: "wild" };
			case PatLit(c):
				switch (c) {
					case CInt(v): { kind: "lit", value: v };
					case CFloat(v): { kind: "lit", value: v };
					case CString(v): { kind: "lit_string", value: v };
					case CBool(v): { kind: "lit_bool", value: v };
					case CNull: { kind: "lit_null" };
				}
			case PatBind(name): { kind: "bind", name: name };
			case PatTyped(name, ty): { kind: "typed", name: name, typeName: ty };
			case PatObj(fields): { kind: "obj", fields: [for (f in fields) { name: f.name, pattern: patternToJson(f.pat) }] };
			case PatArr(items, rest): { kind: "arr", items: [for (i in items) patternToJson(i)], rest: rest };
			case PatOr(a, b): { kind: "or", a: patternToJson(a), b: patternToJson(b) };
			case PatGuard(pat, _): { kind: "guard_unsupported", pattern: patternToJson(pat), note: "guard body not serializable (Dynamic)" };
			case PatAs(pat, name): { kind: "as", pattern: patternToJson(pat), name: name };
			case PatTag(tag, args): { kind: "tag", tag: tag, args: [for (a in args) patternToJson(a)] };
		};
	}

	// ── Stmt / Decl / MuseProgram ──────────────────────────────────────────────────────────

	public static function stmtToJson(s:Stmt, ?checker:MuseChecker):Dynamic {
		return switch (s) {
			case OnBar(body): { kind: "onBar", body: [for (b in body) stmtToJson(b, checker)] };
			case OnPosition(body): { kind: "onPosition", body: [for (b in body) stmtToJson(b, checker)] };
			case OnTick(body): { kind: "onTick", body: [for (b in body) stmtToJson(b, checker)] };
			case OnEvent(streamName, body): { kind: "onEvent", streamName: streamName, body: [for (b in body) stmtToJson(b, checker)] };
			case ExprStmt(e): { kind: "exprStmt", e: exprToJson(e, checker) };
			case Assign(name, e): { kind: "assign", name: name, e: exprToJson(e, checker) };
			case ForIn(name, iter, body): { kind: "forIn", name: name, iter: exprToJson(iter, checker), body: [for (b in body) stmtToJson(b, checker)] };
			case MatchFor(name, iter, arms): { kind: "matchFor", name: name, iter: exprToJson(iter, checker), arms: [for (a in arms) matchArmToJson(a, checker)] };
			case Return(e): { kind: "returnStmt", e: e != null ? exprToJson(e, checker) : null };
			case Yield(e): { kind: "yieldStmt", e: exprToJson(e, checker) };
			case YieldStar(e): { kind: "yieldStarStmt", e: exprToJson(e, checker) };
			case Order(kind, args): { kind: "order", op: Std.string(kind).toLowerCase(), args: [for (a in args) exprToJson(a, checker)] };
			case Block(stmts): { kind: "blockStmt", stmts: [for (st in stmts) stmtToJson(st, checker)] };
			case When(cond, body): { kind: "when", cond: exprToJson(cond, checker), body: [for (b in body) stmtToJson(b, checker)] };
			case Use(module, args): { kind: "use", module: module, args: [for (a in args) { name: a.name, value: exprToJson(a.value, checker) }] };
		};
	}

	public static function declToJson(d:Decl, ?checker:MuseChecker):Dynamic {
		return switch (d) {
			case StrategyDecl(name, body): { kind: "strategyDecl", name: name, body: [for (b in body) stmtToJson(b, checker)] };
			case IndicatorDecl(name, args, body): { kind: "indicatorDecl", name: name, args: args, body: exprToJson(body, checker) };
			case ParamDecl(name, def, opts): { kind: "paramDecl", name: name, def: def != null ? exprToJson(def, checker) : null,
				opts: opts != null ? { ty: opts.ty, tune: opts.tune, min: opts.min, max: opts.max, step: opts.step } : null };
			case FnDecl(name, args, body, kind): { kind: "fnDecl", name: name, args: args, body: exprToJson(body, checker), fnKind: Std.string(kind) };
			case MacroDecl(name, body): { kind: "macroDecl", name: name, body: [for (b in body) stmtToJson(b, checker)] };
			case ModuleDecl(name, params, body): { kind: "moduleDecl", name: name,
				params: [for (p in params) { name: p.name, ty: p.ty, def: p.def != null ? exprToJson(p.def, checker) : null }],
				body: [for (b in body) stmtToJson(b, checker)] };
			case TemplateDecl(name, params, retTy, body): { kind: "templateDecl", name: name,
				params: [for (p in params) { name: p.name, ty: p.ty }], retTy: retTy, body: exprToJson(body, checker) };
		};
	}

	/** Full program: decls + top-level stmts, both type-tagged if `checker` already ran `.check()`. */
	public static function programToJson(prog:MuseProgram, ?checker:MuseChecker):Dynamic {
		return {
			decls: [for (d in prog.decls) declToJson(d, checker)],
			stmts: [for (s in prog.stmts) stmtToJson(s, checker)],
		};
	}
}
