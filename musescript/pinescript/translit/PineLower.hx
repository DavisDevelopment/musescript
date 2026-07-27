package musescript.pinescript.translit;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr as MExpr;
import musescript.ast.MuseNodes as M;
import musescript.ast.OrderKind;
import musescript.ast.FnKind;

import musescript.pinescript.ast.PineProgram;
import musescript.pinescript.ast.PineDecl;
import musescript.pinescript.ast.PineDecl.PineScriptKind;
import musescript.pinescript.ast.PineStmt;
import musescript.pinescript.ast.PineStmt.PineDeclKind;
import musescript.pinescript.ast.PineExpr;
import musescript.pinescript.ast.PineExpr.PineArg;
import musescript.pinescript.translit.BuiltinMap;
import musescript.pinescript.translit.BuiltinMap.BuiltinKind;
import musescript.pinescript.translit.Unsupported.UnsupportedKind;

/**
 * The transliteration core: lowers a parsed Pine AST directly into
 * `musescript.ast` nodes (via the same MuseNodes constructors MuseParser uses).
 * The output is a first-class MuseProgram — feed it straight to MusePrinter for
 * a readable `.ms`, or to MuseCompiler for any backend.
 *
 * Structure produced:
 *   - `x = input.int(...)`      → a top-level ParamDecl
 *   - the header title          → the StrategyDecl / IndicatorDecl name
 *   - every other body statement → inside a single `onBar { ... }` block
 *
 * Fidelity contract (see Unsupported): anything not faithfully mappable is
 * recorded as a note rather than silently mis-emitted. Repaint patterns are
 * flagged via RepaintAudit during call lowering.
 */
class PineLower {
	public final unsupported = new Unsupported();
	public final audit = new RepaintAudit();

	/** Coverage counters for the converter's matrix: every builtin call seen,
	 *  and how many were flagged (unknown or a known-divergent approximation).
	 *  `builtinsSeen − builtinsFlagged` = faithfully-mapped calls. */
	public var builtinsSeen:Int = 0;
	public var builtinsFlagged:Int = 0;

	/** Parity/debug hook: when true, `plot(expr, ...)` is kept as a real Muse
	 *  plot call (writing the value to harness.chart each bar) instead of being
	 *  dropped from the compute path. Lets the parity harness capture a
	 *  transliterated indicator's per-bar series and diff it against a reference.
	 *  Off by default — production transliteration drops chart-only calls. */
	public var keepPlots:Bool = false;

	final prog:PineProgram;
	final params:Array<Decl> = [];
	final fnDecls:Array<Decl> = [];
	final userFns:Map<String, Bool> = new Map();
	final body:Array<Stmt> = [];
	var scriptName = "imported";
	var isStrategy = false;
	var tupId:Int = 0;
	/** Span of the statement currently being lowered, so deep-nested notes
	 *  (unmapped builtins, approximations) can cite the real Pine source line. */
	var curPos:Null<musescript.types.SourcePos> = null;

	public function new(prog:PineProgram) {
		this.prog = prog;
	}

	public static function lower(prog:PineProgram):{program:MuseProgram, lower:PineLower} {
		var l = new PineLower(prog);
		return {program: l.run(), lower: l};
	}

	public function run():MuseProgram {
		for (d in prog.decls) lowerDecl(d);

		var out:MuseProgram = {};
		for (pd in params) out.decls.push(pd);
		for (fn in fnDecls) out.decls.push(fn);
		var top:Array<Stmt> = body.length > 0 ? [OnBar(body)] : [];
		out.decls.push(isStrategy ? StrategyDecl(scriptName, top) : StrategyDecl(scriptName, top));
		return out;
	}

	// ── declarations ────────────────────────────────────────────────────────
	function lowerDecl(d:PineDecl):Void {
		switch (d) {
			case PHeader(kind, args):
				isStrategy = kind == SkStrategy;
				scriptName = sanitize(titleOf(args));
			case PImport(u, l, v, _):
				unsupported.add(LibraryImport('$u/$l/$v'), prog.posOf(d));
			case PTypeDef(_, _, _):
				unsupported.add(Other("user type not yet lowered"), prog.posOf(d));
			case PFunc(name, params, bodyStmts, _):
				userFns.set(name, true);
				var argNames = [for (p in params) p.name];
				fnDecls.push(FnDecl(name, argNames, lowerFuncBody(bodyStmts), Normal));
			case PTop(s):
				lowerBodyStmt(s);
		}
	}

	function titleOf(args:Array<PineArg>):String {
		for (a in args) {
			if (a.name == null || a.name == "title" || a.name == "shorttitle") {
				switch (a.value) { case PString(s): return s; default: }
			}
		}
		return "imported";
	}

	// ── statements ────────────────────────────────────────────────────────────
	function lowerBodyStmt(s:PineStmt):Void {
		var p = prog.posOf(s);
		if (p != null) curPos = p;
		switch (s) {
			case PAssign(name, value, _, _):
				// `x = input.*(...)` becomes a tunable param, not a body assignment.
				var pd = tryParamDecl(name, value);
				if (pd != null) { params.push(pd); return; }
				body.push(Assign(name, lowerExpr(value)));

			case PReassign(name, value):
				body.push(Assign(name, lowerExpr(value)));

			case PTupleAssign(names, value, _):
				// Tuple returns lower as Muse arrays — bind once, index out.
				lowerTupleAssign(names, value, body);

			case PExpr(e):
				lowerExprStmt(e, s);

			case PIf(cond, then, elifs, els):
				lowerIf(cond, then, elifs, els, s);

			case PForTo(v, from, to, step, b):
				// Muse `for x in range(..)` — lower to ForIn over a range() call.
				var range = M.call(M.ident("range"), step != null
					? [lowerExpr(from), lowerExpr(to), lowerExpr(step)]
					: [lowerExpr(from), lowerExpr(to)]);
				body.push(ForIn(v, range, lowerBlock(b)));

			case PForIn(vars, iter, b):
				body.push(ForIn(vars[0], lowerExpr(iter), lowerBlock(b)));

			case PWhile(_, _):
				unsupported.add(Other("`while` loop not yet lowered"), prog.posOf(s));

			case PSwitch(_, _):
				unsupported.add(Other("`switch` not yet lowered"), prog.posOf(s));

			case PBreak | PContinue | PReturn(_):
				// only meaningful inside loops/functions handled elsewhere
		}
	}

	/** Lower a Pine user-function body to a Muse expression (FnDecl body).
	 *  Implicit return = last expression; assigns become `name = expr` binops. */
	function lowerFuncBody(stmts:Array<PineStmt>):MExpr {
		var exprs:Array<MExpr> = [];
		for (s in stmts) {
			var p = prog.posOf(s);
			if (p != null) curPos = p;
			switch (s) {
				case PAssign(name, value, _, _):
					exprs.push(M.binop("=", M.ident(name), lowerExpr(value)));
				case PReassign(name, value):
					exprs.push(M.binop("=", M.ident(name), lowerExpr(value)));
				case PTupleAssign(names, value, _):
					var tmpStmts:Array<Stmt> = [];
					lowerTupleAssign(names, value, tmpStmts);
					for (ts in tmpStmts) switch (ts) {
						case Assign(n, e): exprs.push(M.binop("=", M.ident(n), e));
						default:
					}
				case PExpr(e):
					exprs.push(lowerExpr(e));
				case PReturn(e):
					exprs.push(M.ereturn(e != null ? lowerExpr(e) : null));
				case PIf(cond, then, elifs, els):
					exprs.push(lowerIfExpr(cond, then, elifs, els, s));
				case PForTo(v, from, to, step, b):
					var range = M.call(M.ident("range"), step != null
						? [lowerExpr(from), lowerExpr(to), lowerExpr(step)]
						: [lowerExpr(from), lowerExpr(to)]);
					exprs.push(M.efor(v, range, lowerFuncBody(b)));
				case PForIn(vars, iter, b):
					exprs.push(M.efor(vars[0], lowerExpr(iter), lowerFuncBody(b)));
				case PWhile(cond, b):
					exprs.push(M.ewhile(lowerExpr(cond), lowerFuncBody(b)));
				case PSwitch(_, _):
					unsupported.add(Other("switch-expression not yet lowered"), prog.posOf(s));
					exprs.push(M.nullExpr());
				case PBreak | PContinue:
					unsupported.add(Other("break/continue in function not yet lowered"), prog.posOf(s));
			}
		}
		if (exprs.length == 0) return M.nullExpr();
		if (exprs.length == 1) return exprs[0];
		return M.block(exprs);
	}

	function lowerIfExpr(cond:PineExpr, then:Array<PineStmt>, elifs:Array<{cond:PineExpr, body:Array<PineStmt>}>,
			els:Null<Array<PineStmt>>, src:PineStmt):MExpr {
		var thenE = lowerFuncBody(then);
		if (elifs.length == 0) {
			var elseE = els != null ? lowerFuncBody(els) : null;
			return M.eif(lowerExpr(cond), thenE, elseE);
		}
		// else-if chain → nested EIf
		unsupported.add(ElseIfChain, prog.posOf(src));
		var acc = els != null ? lowerFuncBody(els) : M.nullExpr();
		var i = elifs.length;
		while (i-- > 0) {
			var e = elifs[i];
			acc = M.eif(lowerExpr(e.cond), lowerFuncBody(e.body), acc);
		}
		return M.eif(lowerExpr(cond), thenE, acc);
	}

	/** Nested-block statement lowering that returns a stmt list (for if/for bodies).
	 *  Runs a child lower over the sub-statements, then folds its diagnostics up. */
	function lowerBlock(stmts:Array<PineStmt>):Array<Stmt> {
		var tmp = new PineLower(prog);
		tmp.scriptName = scriptName;
		for (s in stmts) tmp.lowerBodyStmt(s);
		for (n in tmp.unsupported.notes) unsupported.notes.push(n);
		for (f in tmp.audit.findings) audit.findings.push(f);
		return tmp.body;
	}

	function lowerIf(cond:PineExpr, then:Array<PineStmt>, elifs:Array<{cond:PineExpr, body:Array<PineStmt>}>,
			els:Null<Array<PineStmt>>, src:PineStmt):Void {
		// Simple then-only → `when cond: { ... }` (the real Muse idiom).
		if (elifs.length == 0 && els == null) {
			body.push(When(lowerExpr(cond), lowerBlock(then)));
			return;
		}
		// then + else (no elif) → two guarded whens (cond / !cond).
		if (elifs.length == 0 && els != null) {
			body.push(When(lowerExpr(cond), lowerBlock(then)));
			body.push(When(M.unop("!", true, M.parent(lowerExpr(cond))), lowerBlock(els)));
			return;
		}
		// else-if chain: approximate with guarded whens, flag the approximation.
		body.push(When(lowerExpr(cond), lowerBlock(then)));
		for (e in elifs) body.push(When(lowerExpr(e.cond), lowerBlock(e.body)));
		if (els != null) body.push(When(M.boolExpr(true), lowerBlock(els)));
		unsupported.add(ElseIfChain, prog.posOf(src));
	}

	function lowerExprStmt(e:PineExpr, src:PineStmt):Void {
		switch (e) {
			case PCall(callee, args):
				var q = qualifiedName(callee);
				var kind = q != null ? BuiltinMap.lookupFunc(q) : Unknown;
				switch (kind) {
					case Metadata(meta):
						// chart/UI call — dropped from the compute path (plot/label/…
						// don't affect signals). keepPlots re-materializes plot() so
						// the parity harness can capture the plotted series.
						if (keepPlots && meta == "plot" && args.length > 0) {
							var label = plotLabel(args);
							body.push(ExprStmt(M.call(M.ident("plot"), [lowerExpr(args[0].value), M.stringExpr(label)])));
						}
						return;
					case OrderOp(op):
						lowerOrder(op, args, src);
						return;
					default:
						body.push(ExprStmt(lowerExpr(e)));   // audit runs inside lowerCall
				}
			default:
				body.push(ExprStmt(lowerExpr(e)));
		}
	}

	/** Pine `plot(series, title="…")` label: explicit title arg, else "plot". */
	function plotLabel(args:Array<PineArg>):String {
		for (a in args) {
			if (a.name == "title" || (a.name == null && a != args[0])) {
				switch (a.value) { case PString(s): return s; default: }
			}
		}
		return "plot";
	}

	function lowerOrder(op:String, args:Array<PineArg>, src:PineStmt):Void {
		// Muse's order verbs are the canonical arg-free forms `long()/short()/flat()`
		// — the same the parser + Studio accept and round-trip. Pine's order-id
		// string (`strategy.entry("L", …)`) has no equivalent in Muse's single
		// net-position model, so it's dropped and noted (not silently lost).
		var hadId = args.length > 0;
		switch (op) {
			case "entry", "order":
				var dir = orderDirection(args);
				body.push(Order(dir == "short" ? Short : Long, []));
				if (hadId) unsupported.add(Other('strategy.$op order id/args dropped — Muse uses one net position'), prog.posOf(src));
			case "close", "exit", "flat":
				// close a named position / close_all → flat() (close net position).
				// Exact with a single position; an approximation with pyramiding.
				body.push(Order(Flat, []));
				if (hadId) unsupported.add(Other('strategy.$op → flat() closes the net position (Pine order id dropped)'), prog.posOf(src));
			case "cancel":
				unsupported.add(Other("strategy.cancel has no direct Muse verb"), prog.posOf(src));
			default:
				unsupported.add(Other('strategy.$op not lowered'), prog.posOf(src));
		}
	}

	function orderDirection(args:Array<PineArg>):String {
		for (a in args) {
			var q = qualifiedName(a.value);
			if (q != null && BuiltinMap.ORDER_DIR.exists(q)) return BuiltinMap.ORDER_DIR.get(q);
		}
		return "long";
	}

	// ── input.* → ParamDecl ─────────────────────────────────────────────────────
	function tryParamDecl(name:String, value:PineExpr):Null<Decl> {
		switch (value) {
			case PCall(callee, args):
				var q = qualifiedName(callee);
				if (q == null || q.indexOf("input") != 0) return null;
				var def = args.length > 0 ? lowerExpr(args[0].value) : M.nullExpr();
				var opts:musescript.ast.ParamOpts = {};
				// carry through minval/maxval/step when present as named args
				for (a in args) switch (a.name) {
					case "minval": opts.min = constFloat(a.value);
					case "maxval": opts.max = constFloat(a.value);
					case "step": opts.step = constFloat(a.value);
					default:
				}
				opts.ty = switch (q) {
					case "input.bool": "Bool";
					case "input.source": "Series";
					default: "Scalar";
				}
				return ParamDecl(name, def, opts);
			default:
				return null;
		}
	}

	function constFloat(e:PineExpr):Null<Float> {
		return switch (e) { case PInt(v): v; case PFloat(v): v; default: null; };
	}

	// ── expressions ─────────────────────────────────────────────────────────────
	function lowerExpr(e:PineExpr):MExpr {
		return switch (e) {
			case PInt(v): M.intExpr(v);
			case PFloat(v): M.floatExpr(v);
			case PString(v): M.stringExpr(v);
			case PBool(v): M.boolExpr(v);
			case PColor(h): M.stringExpr("#" + h);            // colors flow as strings in Muse
			case PNa: M.nullExpr();
			case PIdent(n):
				// Pine bar series (close/high/…) are Muse builtins read as bare
				// idents: current-bar scalar in expressions, and close-history via
				// resolveSeries' float sugar when passed to an indicator. (high/low
				// as an indicator *source* is the one gap — noted in Unsupported.)
				var bf = BuiltinMap.barField(n);
				bf != null ? M.ident(bf) : M.ident(n);
			case PField(t, f):
				// order-direction / known constant fields collapse to plain idents;
				// otherwise a real field access.
				var q = qualifiedName(e);
				if (q != null && BuiltinMap.ORDER_DIR.exists(q)) M.ident(BuiltinMap.ORDER_DIR.get(q));
				else M.field(lowerExpr(t), f);
			case PUnop(op, x):
				M.unop(op == "not" ? "!" : op, true, lowerExpr(x));
			case PBinop(op, a, b):
				M.binop(mapBinop(op), lowerExpr(a), lowerExpr(b));
			case PTernary(c, t, f):
				M.ternary(lowerExpr(c), lowerExpr(t), lowerExpr(f));
			case PHistory(series, n):
				M.lookback(lowerExpr(series), lowerExpr(n));
			case PCall(callee, args):
				lowerCall(callee, args);
			case PTuple(items):
				M.arrayDecl([for (i in items) lowerExpr(i)]);
			case PIfExpr(c, t, f):
				// value-position if → ternary over the block's last expression.
				M.ternary(lowerExpr(c), lastValue(t), f != null ? lastValue(f) : M.nullExpr());
			case PSwitchExpr(_, _):
				unsupported.add(Other("switch-expression not yet lowered"), null);
				M.nullExpr();
		};
	}

	function lowerCall(callee:PineExpr, args:Array<PineArg>):MExpr {
		var q = qualifiedName(callee);
		var loweredArgs = positional(args);
		if (q != null) {
			audit.auditCall(q, args, curPos);   // catch repaint shapes anywhere, incl. RHS of an assign
			var hasNamed = false;
			for (a in args) if (a.name != null) hasNamed = true;
			var kind = BuiltinMap.lookupFunc(q);
			switch (kind) {
				case Remap(museName):
					builtinsSeen++;
					if (hasNamed) unsupported.add(NamedArgsApprox(q), curPos);
					return M.call(M.ident(museName), loweredArgs);
				case RemapApprox(museName, note):
					builtinsSeen++; builtinsFlagged++;
					if (hasNamed) unsupported.add(NamedArgsApprox(q), curPos);
					unsupported.add(Other('$q → $museName: $note'), curPos);
					return M.call(M.ident(museName), loweredArgs);
				case SeriesField(field):
					return M.field(M.ident("bar"), field);
				case Metadata(_):
					return M.nullExpr(); // used in value position rarely; harmless
				case OrderOp(_):
					return M.nullExpr();
				case Unknown:
					builtinsSeen++;
					if (userFns.exists(q)) {
						// User-defined function — emitted as a normal call; FnDecl
						// already registered. Not an unmapped builtin.
						if (hasNamed) unsupported.add(NamedArgsApprox(q), curPos);
						return M.call(M.ident(q), loweredArgs);
					}
					builtinsFlagged++;
					unsupported.add(UnknownBuiltin(q), curPos);
					return M.call(lowerExpr(callee), loweredArgs);
			}
		}
		return M.call(lowerExpr(callee), loweredArgs);
	}

	function lowerTupleAssign(names:Array<String>, value:PineExpr, into:Array<Stmt>):Void {
		var tmp = "__pine_tup_" + (tupId++);
		into.push(Assign(tmp, lowerExpr(value)));
		for (i in 0...names.length)
			into.push(Assign(names[i], M.array(M.ident(tmp), M.intExpr(i))));
	}

	function lastValue(stmts:Array<PineStmt>):MExpr {
		if (stmts.length == 0) return M.nullExpr();
		return switch (stmts[stmts.length - 1]) {
			case PExpr(e): lowerExpr(e);
			case PAssign(_, v, _, _): lowerExpr(v);
			default: M.nullExpr();
		};
	}

	function positional(args:Array<PineArg>):Array<MExpr>
		return [for (a in args) lowerExpr(a.value)];

	// ── helpers ─────────────────────────────────────────────────────────────────
	/** Reconstruct a fully-qualified dotted name from PIdent/PField chains. */
	function qualifiedName(e:PineExpr):Null<String> {
		return switch (e) {
			case PIdent(n): n;
			case PField(t, f):
				var base = qualifiedName(t);
				base != null ? base + "." + f : null;
			default: null;
		};
	}

	function mapBinop(op:String):String {
		return switch (op) {
			case "and": "&&";
			case "or": "||";
			default: op;
		};
	}

	static function sanitize(s:String):String {
		var buf = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			var ok = (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code)
				|| (c >= "0".code && c <= "9".code) || c == "_".code;
			buf.addChar(ok ? c : "_".code);
		}
		var out = buf.toString();
		return out.length == 0 ? "imported" : out;
	}
}
