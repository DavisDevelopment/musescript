package musescript.compile;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.FnKind;
import musescript.ast.MuseNodes.*;

/**
 * Lower generator functions to plain Muse AST (no yield / no Generator kind).
 *
 * Supported (v1):
 * - `while (cond) { yield expr; ...post }` after leading `var` inits (e.g. range(from,to))
 * - Sequential top-level yields after leading `var` inits: `yield a; yield b; ...`
 * - `if (c) { yield a; } else { yield b; }` after leading `var` inits
 * - `for (n in it) { yield e; post* }` after leading `var` inits (array-like iters)
 * - `yield* e` rewritten to `for (v in e) yield v`, then lowered via the for-in path
 * - After yield*: `for (v in [a,b]) yield v` expanded to sequential yields (seq/for catch)
 * - `yield …; for (n in it) { yield e; post* }` (e.g. `yield a; yield* xs`) as seq+for
 * - `for (n in it) { yield e; post* }; yield …` trailing yields after one for-in
 * - seq + for + trailing yields (still one loop — no multi-loop / CPS)
 *
 * Iterator state lives on the returned object (not harness params), so resume
 * works on JS and Python hosts alike.
 *
 * Unsupported (left unchanged):
 * - multiple loops, complex if bodies, yields after non-for stmts mid-body
 * - generators with no recognized yield layout
 * - on-bar `yield` (stmt) — not lowered here
 *
 * σπέρμα σπέρματος· yield* εἰς for-in θερίζει.
 * μετὰ τὸν κύκλον ἔτι φωνὴ μία· λύω τὸ ὕστερον.
 */
class GeneratorLower {
	static var ysFresh:Int = 0;

	public static function lower(prog:MuseProgram):MuseProgram {
		ysFresh = 0;
		var changed = false;
		var decls = [for (d in prog.decls) {
			var nd = lowerDecl(d);
			if (!declEq(d, nd)) changed = true;
			nd;
		}];
		var stmts = prog.stmts;
		if (stmtsContainYieldStar(stmts)) {
			changed = true;
			stmts = [for (s in stmts) expandYieldStarStmt(s)];
		}
		return changed ? { decls: decls, stmts: stmts } : prog;
	}

	static function lowerDecl(d:Decl):Decl {
		return switch (d) {
			case FnDecl(name, args, body, kind)
				if (kind == Generator || containsYield(body)):
				var lowered = lowerGeneratorBody(body);
				if (lowered != body)
					FnDecl(name, args, lowered, Normal);
				else
					d;
			default: d;
		};
	}

	static function lowerGeneratorBody(body:Expr):Expr {
		var expanded = expandYieldStars(body);
		expanded = expandLiteralForYields(expanded);
		return switch (tryLowerWhileYield(expanded)) {
			case null:
				switch (tryLowerSequentialYields(expanded)) {
					case null:
						switch (tryLowerIfYield(expanded)) {
							case null:
								switch (tryLowerForYield(expanded)) {
									case null:
										switch (tryLowerSeqThenForYield(expanded)) {
											case null: body; // leave original (incl. yield*) if shape unsupported
											case l: l;
										}
									case l: l;
								}
							case l: l;
						}
					case l: l;
				}
			case l: l;
		};
	}

	/** Rewrite `yield* e` → `for (v in e) yield v` before shape detection.
	 * εἰς τὸν λαβύρινθον φέρων μῖτον ἐκ τοῦ ἀπείρου. */
	static function expandYieldStars(e:Expr):Expr {
		if (e == null || !containsYieldStar(e)) return e;
		return mapExpandYieldStar(e);
	}

	/** Expand `for (v in [a,b,…]) yield v` into sequential `yield a; yield b; …`.
	 * Lets seq (and literal for-then-yield) paths catch compounds after yield*.
	 * ἵνα ὁ for τὰ ἑαυτοῦ εἰς τάξιν yield ἐκχέῃ. */
	static function expandLiteralForYields(e:Expr):Expr {
		if (e == null) return e;
		switch (matchSimpleLiteralForYield(e)) {
			case null:
			case yields: return block(yields);
		}
		var es = leadingBlock(e);
		if (es == null) return e;
		var out:Array<Expr> = [];
		var changed = false;
		for (stmt in es) {
			switch (matchSimpleLiteralForYield(stmt)) {
				case null: out.push(stmt);
				case yields:
					changed = true;
					for (y in yields) out.push(y);
			}
		}
		return changed ? block(out) : e;
	}

	/** Match for-in of an array literal whose body is solely `yield loopVar`.
	 * ἓν ὄνομα, πολλὰ σώματα· λῦε εἰς yields. */
	static function matchSimpleLiteralForYield(e:Expr):Null<Array<Expr>> {
		return switch (unwrapBlock(e)) {
			case EFor(name, EArrayDecl(vs), body):
				switch (unwrapBlock(body)) {
					case EYield(EIdent(n)) if (n == name):
						[for (v in vs) eyield(v)];
					default: null;
				}
			default: null;
		};
	}

	static function mapExpandYieldStar(e:Expr):Expr {
		if (e == null) return e;
		return switch (e) {
			case EYieldStar(inner):
				var v = freshYs();
				efor(v, mapExpandYieldStar(inner), block([eyield(ident(v))]));
			case EBlock(es):
				block([for (x in es) mapExpandYieldStar(x)]);
			case EBinop(op, a, b):
				binop(op, mapExpandYieldStar(a), mapExpandYieldStar(b));
			case EUnop(op, pre, a):
				unop(op, pre, mapExpandYieldStar(a));
			case ECall(c, args):
				call(mapExpandYieldStar(c), [for (a in args) mapExpandYieldStar(a)]);
			case EIf(c, a, b):
				eif(mapExpandYieldStar(c), mapExpandYieldStar(a), b != null ? mapExpandYieldStar(b) : null);
			case EWhile(c, a):
				ewhile(mapExpandYieldStar(c), mapExpandYieldStar(a));
			case EFor(n, it, a):
				efor(n, mapExpandYieldStar(it), mapExpandYieldStar(a));
			case EFunction(args, a, kind, name):
				efunction(args, mapExpandYieldStar(a), kind, name);
			case EReturn(v):
				ereturn(v != null ? mapExpandYieldStar(v) : null);
			case EVar(n, i):
				evar(n, i != null ? mapExpandYieldStar(i) : null);
			case EArray(a, i):
				EArray(mapExpandYieldStar(a), mapExpandYieldStar(i));
			case EArrayDecl(vs):
				arrayDecl([for (v in vs) mapExpandYieldStar(v)]);
			case EObject(fs):
				object([for (f in fs) { name: f.name, e: mapExpandYieldStar(f.e) }]);
			case ETernary(c, a, b):
				ternary(mapExpandYieldStar(c), mapExpandYieldStar(a), mapExpandYieldStar(b));
			case EParent(a):
				parent(mapExpandYieldStar(a));
			case EMeta(n, args, a):
				meta(n, [for (x in args) mapExpandYieldStar(x)], mapExpandYieldStar(a));
			case ELookback(a, n):
				lookback(mapExpandYieldStar(a), mapExpandYieldStar(n));
			case EMatch(s, arms):
				match(mapExpandYieldStar(s), [for (arm in arms) {
					pattern: arm.pattern,
					guard: arm.guard != null ? mapExpandYieldStar(arm.guard) : null,
					body: mapExpandYieldStar(arm.body)
				}]);
			case EField(a, f):
				field(mapExpandYieldStar(a), f);
			case EYield(y):
				eyield(mapExpandYieldStar(y));
			default: e;
		};
	}

	/** Stmt `yield* e` → `for (v in e) { yield v; }` (same conceptual rewrite).
	 * Δίδωμι ἐμαυτὸν ἄλλῳ ἐμαυτῷ. */
	static function expandYieldStarStmt(s:Stmt):Stmt {
		return switch (s) {
			case YieldStar(e):
				var v = freshYs();
				ForIn(v, expandYieldStars(e), [Yield(ident(v))]);
			case OnBar(body):
				OnBar([for (x in body) expandYieldStarStmt(x)]);
			case OnTick(body):
				OnTick([for (x in body) expandYieldStarStmt(x)]);
			case OnEvent(name, body):
				OnEvent(name, [for (x in body) expandYieldStarStmt(x)]);
			case Block(body):
				Block([for (x in body) expandYieldStarStmt(x)]);
			case ForIn(n, it, body):
				ForIn(n, expandYieldStars(it), [for (x in body) expandYieldStarStmt(x)]);
			case MatchFor(n, it, arms):
				MatchFor(n, expandYieldStars(it), arms);
			case ExprStmt(e):
				ExprStmt(expandYieldStars(e));
			case Assign(n, e):
				Assign(n, expandYieldStars(e));
			case Return(e):
				Return(e != null ? expandYieldStars(e) : null);
			case Yield(e):
				Yield(expandYieldStars(e));
			case Order(kind, args):
				Order(kind, [for (a in args) expandYieldStars(a)]);
			case When(cond, body):
				When(expandYieldStars(cond), [for (x in body) expandYieldStarStmt(x)]);
			case Use(mod, args):
				Use(mod, [for (a in args) { name: a.name, value: expandYieldStars(a.value) }]);
		};
	}

	static function stmtsContainYieldStar(stmts:Array<Stmt>):Bool {
		for (s in stmts) if (stmtContainsYieldStar(s)) return true;
		return false;
	}

	static function stmtContainsYieldStar(s:Stmt):Bool {
		return switch (s) {
			case YieldStar(_): true;
			case OnBar(body) | OnTick(body) | OnEvent(_, body) | Block(body) | ForIn(_, _, body) | When(_, body):
				for (x in body) if (stmtContainsYieldStar(x)) return true;
				false;
			case MatchFor(_, it, _): containsYieldStar(it);
			case ExprStmt(e) | Assign(_, e) | Yield(e): containsYieldStar(e);
			case Return(e): e != null && containsYieldStar(e);
			case Order(_, args):
				for (a in args) if (containsYieldStar(a)) return true;
				false;
			case Use(_, args):
				for (a in args) if (containsYieldStar(a.value)) return true;
				false;
		};
	}

	static function containsYieldStar(e:Expr):Bool {
		if (e == null) return false;
		return switch (e) {
			case EYieldStar(_): true;
			case EBlock(es): for (x in es) if (containsYieldStar(x)) return true; false;
			case EIf(_, a, b): containsYieldStar(a) || (b != null && containsYieldStar(b));
			case EWhile(_, a) | EFor(_, _, a) | EFunction(_, a, _, _) | EReturn(a) | EVar(_, a)
				| EParent(a) | EMeta(_, _, a) | EYield(a):
				a != null && containsYieldStar(a);
			case EBinop(_, a, b): containsYieldStar(a) || containsYieldStar(b);
			case EUnop(_, _, a) | EArray(a, _) | EField(a, _) | ELookback(a, _): containsYieldStar(a);
			case ECall(a, args):
				if (containsYieldStar(a)) return true;
				for (x in args) if (containsYieldStar(x)) return true;
				false;
			case EArrayDecl(vs): for (v in vs) if (containsYieldStar(v)) return true; false;
			case EObject(fs): for (f in fs) if (containsYieldStar(f.e)) return true; false;
			case ETernary(c, a, b): containsYieldStar(c) || containsYieldStar(a) || containsYieldStar(b);
			case EMatch(_, arms): for (arm in arms) if (containsYieldStar(arm.body)) return true; false;
			default: false;
		};
	}

	static function freshYs():String {
		return "__ys" + (ysFresh++);
	}

	// --- pattern: var*; for (n in it) { yield e; post* }; yield* ---

	static function tryLowerForYield(body:Expr):Null<Expr> {
		var es = leadingBlock(body);
		if (es == null) return null;

		var inits:Array<Expr> = [];
		var i = 0;
		while (i < es.length) {
			switch (es[i]) {
				case EVar(_): inits.push(es[i]); i++;
				default: break;
			}
		}
		if (i >= es.length) return null;

		return switch (es[i]) {
			case EFor(name, it, loopBody):
				var parsed = parseForYieldBody(name, it, loopBody, inits);
				if (parsed == null) return null;
				i++;
				var trail = takeTrailingYields(es, i, localNames(parsed.inits));
				if (trail == null) return null;
				if (trail.length == 0)
					return buildIterator(parsed.inits, buildWhileYieldNext(parsed.cond, parsed.yieldExpr, parsed.post));
				var exitAt = 2;
				var loopArms = buildWhileYieldArms(parsed.cond, parsed.yieldExpr, parsed.post, 0, exitAt);
				var trailArms = buildSequentialArms(trail, exitAt);
				return buildIterator(parsed.inits, dispatchLoop(loopArms.concat(trailArms)));
			default:
				return null;
		};
	}

	/** var*; yield+; for (n in it) { yield e; post* }; yield* — e.g. `yield a; yield* xs; yield z`.
	 * Trailing yields after the one for allowed; second loop stays unsupported.
	 * δεύτερον yield μετὰ τὸ πρῶτον· εἶτα ὁ for· ὕστερον ἔτι φωνή.
	 */
	static function tryLowerSeqThenForYield(body:Expr):Null<Expr> {
		var es = leadingBlock(body);
		if (es == null) return null;

		var inits:Array<Expr> = [];
		var i = 0;
		while (i < es.length) {
			switch (es[i]) {
				case EVar(_): inits.push(es[i]); i++;
				default: break;
			}
		}
		var locals = localNames(inits);
		var yields:Array<Expr> = [];
		while (i < es.length) {
			switch (es[i]) {
				case EYield(y): yields.push(rewriteLocals(y, locals)); i++;
				default: break;
			}
		}
		if (yields.length == 0) return null;
		if (i >= es.length) return null;

		return switch (es[i]) {
			case EFor(name, it, loopBody):
				var parsed = parseForYieldBody(name, it, loopBody, inits);
				if (parsed == null) return null;
				i++;
				var trail = takeTrailingYields(es, i, localNames(parsed.inits));
				if (trail == null) return null;
				var base = yields.length;
				var seqArms = buildSequentialArms(yields, 0);
				// drop the terminal done arm — loop (or trail) owns completion
				seqArms.pop();
				var exitAt = trail.length > 0 ? base + 2 : null;
				var loopArms = buildWhileYieldArms(parsed.cond, parsed.yieldExpr, parsed.post, base, exitAt);
				var arms = seqArms.concat(loopArms);
				if (trail.length > 0)
					arms = arms.concat(buildSequentialArms(trail, base + 2));
				return buildIterator(parsed.inits, dispatchLoop(arms));
			default: null;
		};
	}

	/** Consume only `yield` stmts from `es[i..]`. Null if a non-yield remains.
	 * ὄπισθεν τοῦ for· μόνον yields, οὐκ ἄλλος μῖτος. */
	static function takeTrailingYields(es:Array<Expr>, i:Int, locals:Array<String>):Null<Array<Expr>> {
		var out:Array<Expr> = [];
		while (i < es.length) {
			switch (es[i]) {
				case EYield(y):
					out.push(rewriteLocals(y, locals));
					i++;
				default:
					return null;
			}
		}
		return out;
	}

	/** Shared for-in yield parse: adds `__arr`/`__i`, rewrites yield/post with index access.
	 * κοινὸς μῖτος τῷ for καὶ τῷ seq+for. */
	static function parseForYieldBody(
		name:String, it:Expr, loopBody:Expr, inits:Array<Expr>
	):Null<{inits:Array<Expr>, cond:Expr, yieldExpr:Expr, post:Array<Expr>}> {
		var stmts = leadingBlock(loopBody);
		if (stmts == null || stmts.length == 0) return null;
		var yieldExpr:Expr;
		var post:Array<Expr>;
		switch (stmts[0]) {
			case EYield(y):
				yieldExpr = y;
				post = stmts.slice(1);
			default: return null;
		}
		for (p in post)
			if (containsYield(p)) return null;

		var allInits = inits.concat([
			EVar("__arr", it),
			EVar("__i", intExpr(0))
		]);
		var allLocals = localNames(allInits);
		var idxAccess = EArray(EIdent("__arr"), EIdent("__i"));
		var yieldBound = rewriteLocals(substIdent(yieldExpr, name, idxAccess), allLocals);
		var post2:Array<Expr> = [for (p in post)
			rewriteStmt(substIdent(p, name, idxAccess), allLocals)
		];
		post2.push(rewriteStmt(
			binop("=", EIdent("__i"), binop("+", EIdent("__i"), intExpr(1))),
			allLocals
		));
		var cond2 = rewriteLocals(
			binop("<", EIdent("__i"), EField(EIdent("__arr"), "length")),
			allLocals
		);
		return { inits: allInits, cond: cond2, yieldExpr: yieldBound, post: post2 };
	}

	static function substIdent(e:Expr, from:String, to:Expr):Expr {
		if (e == null) return e;
		return switch (e) {
			case EIdent(n) if (n == from): to;
			case EBlock(es): block([for (x in es) substIdent(x, from, to)]);
			case EBinop(op, a, b): binop(op, substIdent(a, from, to), substIdent(b, from, to));
			case EUnop(op, pre, a): unop(op, pre, substIdent(a, from, to));
			case ECall(c, args): call(substIdent(c, from, to), [for (a in args) substIdent(a, from, to)]);
			case EIf(c, a, b): eif(substIdent(c, from, to), substIdent(a, from, to), b != null ? substIdent(b, from, to) : null);
			case EWhile(c, a): ewhile(substIdent(c, from, to), substIdent(a, from, to));
			case EFor(n, it, a): efor(n, substIdent(it, from, to), substIdent(a, from, to));
			case EReturn(v): ereturn(v != null ? substIdent(v, from, to) : null);
			case EVar(n, i): evar(n, i != null ? substIdent(i, from, to) : null);
			case EArray(a, i): EArray(substIdent(a, from, to), substIdent(i, from, to));
			case EArrayDecl(vs): arrayDecl([for (v in vs) substIdent(v, from, to)]);
			case EObject(fs): object([for (f in fs) { name: f.name, e: substIdent(f.e, from, to) }]);
			case ETernary(c, a, b): ternary(substIdent(c, from, to), substIdent(a, from, to), substIdent(b, from, to));
			case EParent(a): parent(substIdent(a, from, to));
			case EField(a, f): field(substIdent(a, from, to), f);
			case ELookback(a, n): lookback(substIdent(a, from, to), substIdent(n, from, to));
			default: e;
		};
	}

	// --- pattern: var*; if (c) { yield a; } else { yield b; } ---

	static function tryLowerIfYield(body:Expr):Null<Expr> {
		var es = leadingBlock(body);
		if (es == null) return null;

		var inits:Array<Expr> = [];
		var i = 0;
		while (i < es.length) {
			switch (es[i]) {
				case EVar(_): inits.push(es[i]); i++;
				default: break;
			}
		}
		if (i >= es.length || es.length - i != 1) return null;

		var locals = localNames(inits);
		switch (es[i]) {
			case EIf(c, a, b) if (b != null):
				var ya = singleYield(a);
				var yb = singleYield(b);
				if (ya == null || yb == null) return null;
				ya = rewriteLocals(ya, locals);
				yb = rewriteLocals(yb, locals);
				c = rewriteLocals(c, locals);
				// next(): state0 → evaluate if; yield then advance to done
				var nextBody = eif(
					stateIs(0),
					block([
						setState(1),
						ereturn(iterValue(eif(c, ya, yb)))
					]),
					ereturn(iterDone())
				);
				return buildIterator(inits, nextBody);
			default:
				return null;
		}
	}

	static function singleYield(e:Expr):Null<Expr> {
		return switch (unwrapBlock(e)) {
			case EYield(y): y;
			case EBlock([EYield(y)]): y;
			default: null;
		};
	}

	// --- pattern: var*; while (cond) { yield y; post* } ---

	static function tryLowerWhileYield(body:Expr):Null<Expr> {
		var es = leadingBlock(body);
		if (es == null) return null;

		var inits:Array<Expr> = [];
		var i = 0;
		while (i < es.length) {
			switch (es[i]) {
				case EVar(_): inits.push(es[i]); i++;
				default: break;
			}
		}
		if (i >= es.length || es.length - i != 1) return null;

		var locals = localNames(inits);
		var cond:Expr;
		var yieldExpr:Expr;
		var post:Array<Expr>;
		switch (es[i]) {
			case EWhile(c, loopBody):
				cond = c;
				var stmts = leadingBlock(loopBody);
				if (stmts == null || stmts.length == 0) return null;
				switch (stmts[0]) {
					case EYield(y):
						yieldExpr = y;
						post = stmts.slice(1);
					default: return null;
				}
			default: return null;
		}
		for (p in post)
			if (containsYield(p)) return null;

		cond = rewriteLocals(cond, locals);
		yieldExpr = rewriteLocals(yieldExpr, locals);
		post = [for (p in post) rewriteStmt(p, locals)];

		return buildIterator(inits, buildWhileYieldNext(cond, yieldExpr, post));
	}

	// --- pattern: var*; yield a; yield b; ... ---

	static function tryLowerSequentialYields(body:Expr):Null<Expr> {
		var es = leadingBlock(body);
		if (es == null) return null;

		var inits:Array<Expr> = [];
		var i = 0;
		while (i < es.length) {
			switch (es[i]) {
				case EVar(_): inits.push(es[i]); i++;
				default: break;
			}
		}
		var locals = localNames(inits);
		var yields:Array<Expr> = [];
		while (i < es.length) {
			switch (es[i]) {
				case EYield(y): yields.push(rewriteLocals(y, locals)); i++;
				default: return null;
			}
		}
		if (yields.length == 0) return null;

		return buildIterator(inits, buildSequentialNext(yields));
	}

	static function buildIterator(inits:Array<Expr>, nextBody:Expr):Expr {
		// Sequential field stores so later inits can ref earlier ones (e.g. `__arr = xs`).
		var setup:Array<Expr> = [evar("__it", object([{ name: "_s", e: intExpr(0) }]))];
		var seen:Array<String> = [];
		for (init in inits) switch (init) {
			case EVar(name, i):
				var rhs = i != null ? rewriteLocals(i, seen) : nullExpr();
				setup.push(binop("=", field(ident("__it"), "_" + name), rhs));
				seen.push(name);
			default:
		}
		setup.push(binop("=", field(ident("__it"), "next"), efunction([], nextBody, Normal)));
		setup.push(ereturn(ident("__it")));
		return block(setup);
	}

	static function iterObject(nextBody:Expr):Expr {
		return object([{ name: "next", e: efunction([], nextBody, Normal) }]);
	}

	static function iterDone():Expr {
		return object([
			{ name: "done", e: boolExpr(true) },
			{ name: "value", e: nullExpr() }
		]);
	}

	static function iterValue(v:Expr):Expr {
		return object([
			{ name: "done", e: boolExpr(false) },
			{ name: "value", e: v }
		]);
	}

	static function setState(n:Int):Expr {
		return binop("=", field(ident("__it"), "_s"), intExpr(n));
	}

	static function stateIs(n:Int):Expr {
		return binop("==", field(ident("__it"), "_s"), intExpr(n));
	}

	static function buildWhileYieldNext(cond:Expr, yieldExpr:Expr, post:Array<Expr>, base:Int = 0):Expr {
		return dispatchLoop(buildWhileYieldArms(cond, yieldExpr, post, base));
	}

	/** While/for resume arms at `base` (check) and `base+1` (post → back to check).
	 * When `exitState` is set, exhausted loop jumps there instead of done (trailing yields).
	 * κύκλος δύο οἴκων· ἐὰν δὲ τέλος ἄλλο ᾖ, ἐκεῖσε φέρε. */
	static function buildWhileYieldArms(
		cond:Expr, yieldExpr:Expr, post:Array<Expr>, base:Int, ?exitState:Null<Int>
	):Array<{state:Int, body:Expr}> {
		var onExhaust:Expr = exitState != null
			? block([setState(exitState)])
			: ereturn(iterDone());
		var check = eif(
			unop("!", true, cond),
			onExhaust,
			block([
				setState(base + 1),
				ereturn(iterValue(yieldExpr))
			])
		);
		var resume = block(post.concat([setState(base)]));
		return [
			{ state: base, body: check },
			{ state: base + 1, body: resume }
		];
	}

	static function buildSequentialNext(yields:Array<Expr>):Expr {
		return dispatchLoop(buildSequentialArms(yields, 0));
	}

	/** Sequential yield arms starting at `base`, ending with a done state.
	 * τάξις φωνῶν· ἔσχατον ἡ σιγή. */
	static function buildSequentialArms(yields:Array<Expr>, base:Int):Array<{state:Int, body:Expr}> {
		var arms = [];
		for (i in 0...yields.length)
			arms.push({
				state: base + i,
				body: block([setState(base + i + 1), ereturn(iterValue(yields[i]))])
			});
		arms.push({ state: base + yields.length, body: ereturn(iterDone()) });
		return arms;
	}

	static function dispatchLoop(arms:Array<{state:Int, body:Expr}>):Expr {
		function branch(idx:Int):Expr {
			if (idx >= arms.length) return ereturn(iterDone());
			var arm = arms[idx];
			return eif(
				stateIs(arm.state),
				arm.body,
				branch(idx + 1)
			);
		}
		return ewhile(boolExpr(true), branch(0));
	}

	static function localNames(inits:Array<Expr>):Array<String> {
		return [for (init in inits) switch (init) {
			case EVar(n, _): n;
			default: continue;
		}];
	}

	static function rewriteStmt(e:Expr, locals:Array<String>):Expr {
		return switch (e) {
			case EBinop("=", EIdent(name), rhs) if (locals.indexOf(name) >= 0):
				binop("=", field(ident("__it"), "_" + name), rewriteLocals(rhs, locals));
			default: rewriteLocals(e, locals);
		};
	}

	static function rewriteLocals(e:Expr, locals:Array<String>):Expr {
		if (e == null) return e;
		return switch (e) {
			case EIdent(name) if (locals.indexOf(name) >= 0):
				field(ident("__it"), "_" + name);
			case EBlock(es):
				block([for (x in es) rewriteStmt(x, locals)]);
			case EBinop(op, a, b):
				binop(op, rewriteLocals(a, locals), rewriteLocals(b, locals));
			case EUnop(op, pre, a):
				unop(op, pre, rewriteLocals(a, locals));
			case ECall(c, args):
				call(rewriteLocals(c, locals), [for (a in args) rewriteLocals(a, locals)]);
			case EIf(c, a, b):
				eif(rewriteLocals(c, locals), rewriteLocals(a, locals), b != null ? rewriteLocals(b, locals) : null);
			case EWhile(c, a):
				ewhile(rewriteLocals(c, locals), rewriteLocals(a, locals));
			case EFor(n, it, a):
				efor(n, rewriteLocals(it, locals), rewriteLocals(a, locals));
			case EReturn(v):
				ereturn(v != null ? rewriteLocals(v, locals) : null);
			case EVar(n, i):
				evar(n, i != null ? rewriteLocals(i, locals) : null);
			case EArray(a, i):
				EArray(rewriteLocals(a, locals), rewriteLocals(i, locals));
			case EArrayDecl(vs):
				arrayDecl([for (v in vs) rewriteLocals(v, locals)]);
			case EObject(fs):
				object([for (f in fs) { name: f.name, e: rewriteLocals(f.e, locals) }]);
			case ETernary(c, a, b):
				ternary(rewriteLocals(c, locals), rewriteLocals(a, locals), rewriteLocals(b, locals));
			case EParent(a):
				parent(rewriteLocals(a, locals));
			case EMeta(n, args, a):
				meta(n, [for (x in args) rewriteLocals(x, locals)], rewriteLocals(a, locals));
			case ELookback(a, n):
				lookback(rewriteLocals(a, locals), rewriteLocals(n, locals));
			case EMatch(s, arms):
				match(rewriteLocals(s, locals), arms);
			case EField(a, f):
				field(rewriteLocals(a, locals), f);
			default: e;
		};
	}

	// --- utilities ---

	/** Prefer the outer stmt list; only peel nested wrappers like `{{ ... }}`.
	 * μὴ λῦε τὸν μῖτον τοῦ ἑνὸς for. */
	static function leadingBlock(body:Expr):Null<Array<Expr>> {
		return switch (body) {
			case EBlock(es):
				if (es.length == 1) switch (es[0]) {
					case EBlock(_): leadingBlock(es[0]);
					default: es;
				} else es;
			default: null;
		};
	}

	static function unwrapBlock(e:Expr):Expr {
		return switch (e) {
			case EBlock([single]): unwrapBlock(single);
			default: e;
		};
	}

	static function containsYield(e:Expr):Bool {
		if (e == null) return false;
		return switch (e) {
			case EYield(_) | EYieldStar(_): true;
			case EBlock(es): for (x in es) if (containsYield(x)) return true; false;
			case EIf(_, a, b): containsYield(a) || (b != null && containsYield(b));
			case EWhile(_, a) | EFor(_, _, a) | EFunction(_, a, _, _) | EReturn(a) | EVar(_, a)
				| EParent(a) | EMeta(_, _, a):
				a != null && containsYield(a);
			case EBinop(_, a, b): containsYield(a) || containsYield(b);
			case EUnop(_, _, a) | EArray(a, _) | EField(a, _) | ELookback(a, _): containsYield(a);
			case ECall(a, args):
				if (containsYield(a)) return true;
				for (x in args) if (containsYield(x)) return true;
				false;
			case EArrayDecl(vs): for (v in vs) if (containsYield(v)) return true; false;
			case EObject(fs): for (f in fs) if (containsYield(f.e)) return true; false;
			case ETernary(c, a, b): containsYield(c) || containsYield(a) || containsYield(b);
			case EMatch(_, arms): for (arm in arms) if (containsYield(arm.body)) return true; false;
			default: false;
		};
	}

	static function declEq(a:Decl, b:Decl):Bool {
		return a == b;
	}
}
