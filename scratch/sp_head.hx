package musescript.parse;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.Pattern;
import musescript.ast.MatchArm;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.FnKind;
import musescript.ast.MuseNodes;
import musescript.types.BuiltinSigs;
import musescript.types.MuseType;
import musescript.types.AstSpans;
import musescript.types.SourcePositions;

/**
 * Hand-rolled recursive-descent parser for the braced typed surface:
 * `strategy` / `module` / `template` / `pipeline` / `param` / `onBar` / `when` / `use` / `|>`.
 *
 * Lowers to the same MuseProgram AST as the legacy annotation front end.
 */
class StrategyParser {
	var src:String;
	var i:Int;
	var len:Int;
	var origin:String;
	var hoisted:Array<Decl>;
	var knownSeries:Map<String, Bool>;
	var spans:AstSpans;

	public function new() {}

	public function parse(source:String, ?origin:String):MuseProgram {
		this.src = source;
		this.origin = origin != null ? origin : "<strategy>";
		this.i = 0;
		this.len = source.length;
		this.hoisted = [];
		this.knownSeries = new Map();
		this.spans = AstSpans.begin();
		try {
			var decls:Array<Decl> = [];
			var stmts:Array<Stmt> = [];
			skipWs();
			while (i < len) {
				var kw = peekIdent();
				switch (kw) {
					case "strategy":
						decls.push(parseStrategy());
					case "module":
						decls.push(parseModule());
					case "template":
						decls.push(parseTemplate());
					case "pipeline" | "search":
						decls.push(parsePipeline());
					case "param":
						decls.push(parseParamDecl());
					case "feature":
						decls.push(parseFeatureDecl());
					case "indicator":
						decls.push(parseIndicatorDecl());
					case "enum":
						decls.push(parseEnumDecl());
					case "class":
						decls.push(parseClassDecl());
					case "function":
						decls.push(parseFnDecl());
					default:
						stmts = stmts.concat(parseStmtListUntil(null));
						break;
				}
				skipWs();
			}
			var prog:MuseProgram = { decls: hoisted.concat(decls), stmts: stmts, spans: spans };
			AstSpans.end();
			return prog;
		} catch (e:Dynamic) {
			AstSpans.end();
			throw e;
		}
	}

	/** True when source looks like the new surface (not `{ @strategy ... }`). */
	public static function looksLike(source:String):Bool {
		var s = skipLeadingComments(StringTools.ltrim(source));
		if (StringTools.startsWith(s, "strategy")
			|| StringTools.startsWith(s, "module")
			|| StringTools.startsWith(s, "template")
			|| StringTools.startsWith(s, "pipeline")
			|| StringTools.startsWith(s, "search")
			|| StringTools.startsWith(s, "param ")
			|| StringTools.startsWith(s, "param\t")
			|| StringTools.startsWith(s, "feature ")
			|| StringTools.startsWith(s, "feature\t")
			|| StringTools.startsWith(s, "enum ")
			|| StringTools.startsWith(s, "enum\t")
			|| StringTools.startsWith(s, "class ")
			|| StringTools.startsWith(s, "class\t")
			|| StringTools.startsWith(s, "indicator "))
			return true;
		// A file may lead with helper `function` declarations before its `strategy` block — a
		// natural way to organize reusable logic. Sniffing only the very first token silently
		// misrouted such files to the legacy hscript parser (confusing, misattributed errors on
		// the SECOND statement of the first function body, since bare hscript requires `;`/`var`/
		// `return` that the typed surface doesn't). Peek for a bare top-of-line `strategy Name {`
		// declaration anywhere in the file; deliberately NOT a plain substring search for
		// "strategy" so it can't false-positive on the legacy `@strategy("Name")` meta annotation.
		if (StringTools.startsWith(s, "function"))
			return ~/(^|[\r\n])[ \t]*strategy[ \t]+[A-Za-z_]/.match(s);
		return false;
	}

	/** Strip leading line/block comments and blank lines so looksLike sees the first keyword. */
	static function skipLeadingComments(s:String):String {
		var t = StringTools.ltrim(s);
		while (t.length > 0) {
			if (StringTools.startsWith(t, "//")) {
				var nl = t.indexOf("\n");
				t = StringTools.ltrim(nl >= 0 ? t.substr(nl + 1) : "");
				continue;
			}
			if (StringTools.startsWith(t, "/*")) {
				var end = t.indexOf("*/");
				t = StringTools.ltrim(end >= 0 ? t.substr(end + 2) : "");
				continue;
			}
			break;
		}
		return t;
	}

	function parseStrategy():Decl {
		expectIdent("strategy");
		var name = expectIdentValue();
		// `strategy Name(p0 = 1.0, p1: Float = 2.0) { ... }` — normal function-argument notation
		// as sugar for the equivalent `param p0 = 1.0; param p1: Float = 2.0;` statements inside
		// the body (see parseParamDecl); mirrors parseModule's identical `(name [: ty] [= def],
		// ...)` signature syntax just below. Only the plain name/type/default trio is supported
		// here, not the `{ min: .. max: .. }` extended-options block (that reads awkwardly
		// crammed into a comma-separated argument list) — use the body-statement `param` form
		// for those. Both forms are fully interchangeable and freely mixable in the same
		// strategy; this just desugars to identical `ParamDecl`s pushed onto the same `hoisted`
		// list the body-statement form already uses, so every downstream consumer (checker,
		// interp, both backends) needs no changes at all.
		if (match("(")) {
			if (!check(")")) {
				do {
					var pn = expectIdentValue();
					var pty:Null<String> = null;
					if (match(":")) pty = expectIdentValue();
					var pdef:Null<Expr> = null;
					if (match("=")) pdef = parseExpr();
					hoisted.push(ParamDecl(pn, pdef, { ty: pty }));
				} while (match(","));
			}
			expect(")");
		}
		expect("{");
		var body:Array<Stmt> = [];
		skipWs();
		while (i < len && !check("}")) {
			var kw = peekIdent();
			if (kw == "param") {
				hoisted.push(parseParamDecl());
			} else if (kw == "indicator" || kw == "feature") {
				// value-typed binding: indicator/feature maFast = sma(close, fast)
				expectIdent(kw);
				var iname = expectIdentValue();
				var ity:Null<String> = null;
				if (match(":")) ity = expectIdentValue();
				expect("=");
				var ibody = parseExpr();
				match(";");
				body.push(Assign(iname, ibody));
				if (kw == "indicator" && isSeriesExpr(ibody)) knownSeries.set(iname, true);
			} else {
				body.push(parseStmt());
			}
			skipWs();
		}
		expect("}");
		return StrategyDecl(name, body);
	}

	function parseModule():Decl {
		expectIdent("module");
		var name = expectIdentValue();
		var params:Array<{name:String, ty:Null<String>, def:Null<Expr>}> = [];
		if (match("(")) {
			if (!check(")")) {
				do {
					var pn = expectIdentValue();
					var ty:Null<String> = null;
					if (match(":")) ty = expectIdentValue();
					var def:Null<Expr> = null;
					if (match("=")) def = parseExpr();
					params.push({ name: pn, ty: ty, def: def });
				} while (match(","));
			}
			expect(")");
		}
		expect("{");
		var body = parseStmtListUntil("}");
		expect("}");
		return ModuleDecl(name, params, body);
	}

	function parseTemplate():Decl {
		expectIdent("template");
		var name = expectIdentValue();
		expect("(");
		var params:Array<{name:String, ty:String}> = [];
		if (!check(")")) {
			do {
				var pn = expectIdentValue();
				expect(":");
				var ty = expectIdentValue();
				params.push({ name: pn, ty: ty });
			} while (match(","));
		}
		expect(")");
		// Expr templates: `template f(...) -> Ret { expr }`
		// Stmt templates: `template f(...) { onBar/onPosition/when/... }`
		if (match("->")) {
			var retTy = expectIdentValue();
			expect("{");
			var body = parseExpr();
			skipWs();
			if (match(";")) {}
			expect("}");
			return TemplateDecl(name, params, retTy, body);
		}
		expect("{");
		var stmts = parseStmtListUntil("}");
		expect("}");
		return StmtTemplateDecl(name, params, stmts);
	}

	function parsePipeline():Decl {
		var kw = expectIdentValue(); // pipeline | search
		var name = "discover";
		if (!check("{")) name = expectIdentValue();
		expect("{");
		var body = parseStmtListUntil("}");
		expect("}");
		return MacroDecl(name != null ? name : kw, body);
	}

	function parseParamDecl():Decl {
		expectIdent("param");
		var name = expectIdentValue();
		var ty:Null<String> = null;
		if (match(":")) ty = expectIdentValue();
		var def:Null<Expr> = null;
		if (match("=")) def = parseExpr();
		var opts:ParamOpts = { ty: ty };
		if (match("{")) {
			if (!check("}")) {
				do {
					var key = expectIdentValue();
					expect(":");
					var val = parseExpr();
					switch (key) {
						case "min": opts.min = constNum(val);
						case "max": opts.max = constNum(val);
						case "step": opts.step = constNum(val);
						case "tune": opts.tune = constStr(val);
						default:
							throw err('unknown param option "$key" (expected min/max/step/tune)');
					}
				} while (match(","));
			}
			expect("}");
		}
		match(";");
		return ParamDecl(name, def, opts);
	}

	function constNum(e:Expr):Null<Float> {
		return switch (e) {
			case EConst(CInt(n)): n;
			case EConst(CFloat(n)): n;
			case EUnop("-", true, inner):
				var v = constNum(inner);
				v != null ? -v : null;
			default: null;
		};
	}

	function constStr(e:Expr):Null<String> {
		return switch (e) {
			case EConst(CString(s)): s;
			case EIdent(s): s;
			default: null;
		};
	}

	/**
	 * `indicator name(args) = expr` (single-expression value form, unchanged) OR
	 * `indicator function name(args) { ...stmts...; return v; }` (statement-block form,
	 * matching parseFnDecl's own `function name(args) { ... }` body-parsing exactly — the
	 * block form supports `state.foo`/`bar_index`/`close[i]` lookback across bars, the same
	 * capability the LEGACY `@indicator("name") function(args) {...}` annotation syntax
	 * already has via MuseParser.readIndicator; both produce the identical `IndicatorDecl`
	 * AST, so nothing downstream needs to know which spelling was used).
	 */
	function parseIndicatorDecl():Decl {
		expectIdent("indicator");
		var d = matchIdent("function") ? parseIndicatorFunctionBody() : parseValueDeclAfterKeyword();
		switch (d) {
			case IndicatorDecl(name, _, body):
				if (isSeriesExpr(body)) knownSeries.set(name, true);
			default:
		}
		return d;
	}

	function parseIndicatorFunctionBody():Decl {
		var name = expectIdentValue();
		expect("(");
		var args:Array<String> = [];
		if (!check(")")) {
			do args.push(expectIdentValue()) while (match(","));
		}
		expect(")");
		expect("{");
		var body = MuseNodes.block([for (s in parseStmtListUntil("}")) stmtAsExpr(s)]);
		expect("}");
		return IndicatorDecl(name, args, body);
	}

	function parseFeatureDecl():Decl {
		expectIdent("feature");
		return parseValueDeclAfterKeyword();
	}

	/** `enum Name { Variant; Variant(arg, ...); ... }` — Haxe-flavored algebraic enum. */
	function parseEnumDecl():Decl {
		expectIdent("enum");
		var name = expectIdentValue();
		expect("{");
		var variants:Array<{name:String, args:Array<String>}> = [];
		skipWs();
		while (i < len && !check("}")) {
			var vn = expectIdentValue();
			var args:Array<String> = [];
			if (match("(")) {
				if (!check(")")) {
					do args.push(expectIdentValue()) while (match(","));
				}
				expect(")");
			}
			match(";");
			variants.push({ name: vn, args: args });
			skipWs();
		}
		expect("}");
		return EnumDecl(name, variants);
	}

	/**
	 * `class Name [extends Parent] { [param p [: Type] [= expr]] field [: Type] [= expr]; new(args) {...} [static] function m(args) {...} ... }`
	 *
	 * `Parent` may be a dotted path (`muse.Strat`, `muse.Indicator`). Those two roots turn the
	 * class into a strategy or indicator declaration — see `ClassStrategyLower`, which flattens
	 * the inheritance chain at compile time so the result reaches the backends as an ordinary
	 * `StrategyDecl`/`IndicatorDecl`. Any other parent is an ordinary class, unchanged.
	 *
	 * `param` inside a class body hoists exactly as it does inside `strategy`, so the two
	 * surfaces declare parameters the same way.
	 */
	function parseClassDecl():Decl {
		expectIdent("class");
		var name = expectIdentValue();
		var parent:Null<String> = null;
		if (matchIdent("extends")) parent = parseDottedName();
		expect("{");
		var fields:Array<{name:String, def:Null<Expr>}> = [];
		var methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}> = [];
		var ctor:Null<{args:Array<String>, body:Expr}> = null;
		skipWs();
		while (i < len && !check("}")) {
			if (peekIdent() == "param") {
				hoisted.push(parseParamDecl());
				skipWs();
				continue;
			}
			var isStatic = matchIdent("static");
			if (matchIdent("new")) {
				expect("(");
				var args:Array<String> = [];
				if (!check(")")) do args.push(expectIdentValue()) while (match(","));
				expect(")");
				expect("{");
				var body = MuseNodes.block([for (s in parseStmtListUntil("}")) stmtAsExpr(s)]);
				expect("}");
				ctor = { args: args, body: body };
			} else if (matchIdent("function")) {
				var mname = expectIdentValue();
				expect("(");
				var args:Array<String> = [];
				if (!check(")")) do args.push(expectIdentValue()) while (match(","));
				expect(")");
				expect("{");
				var body = MuseNodes.block([for (s in parseStmtListUntil("}")) stmtAsExpr(s)]);
				expect("}");
				methods.push({ name: mname, args: args, body: body, isStatic: isStatic });
			} else {
				var fname = expectIdentValue();
				if (match(":")) expectIdentValue(); // type annotation, not tracked yet
				var def:Null<Expr> = null;
				if (match("=")) def = parseExpr();
				match(";");
				fields.push({ name: fname, def: def });
			}
			skipWs();
		}
		expect("}");
		return ClassDecl(name, parent, fields, methods, ctor);
	}

	/** `Ident ("." Ident)*` — a type path such as `muse.Strat`. Bare names stay bare. */
	function parseDottedName():String {
		var buf = expectIdentValue();
		while (check(".")) {
			expect(".");
			buf += "." + expectIdentValue();
		}
		return buf;
	}

	function parseValueDeclAfterKeyword():Decl {
		var name = expectIdentValue();
		var args:Array<String> = [];
		if (match("(")) {
			if (!check(")")) {
				do args.push(expectIdentValue()) while (match(","));
			}
			expect(")");
		}
		expect("=");
		var body = parseExpr();
		match(";");
		return IndicatorDecl(name, args, body);
	}

	function parseFnDecl():Decl {
		expectIdent("function");
		var name = expectIdentValue();
		expect("(");
		var args:Array<String> = [];
		if (!check(")")) {
			do args.push(expectIdentValue()) while (match(","));
		}
		expect(")");
		expect("{");
		var bodyExpr = MuseNodes.block([for (s in parseStmtListUntil("}")) stmtAsExpr(s)]);
		expect("}");
		return FnDecl(name, args, bodyExpr, Normal);
	}

	/** `(cond) { block } [else if (cond) { block }]* [else { block }]?` -- the leading `if`
	 * keyword has already been consumed by the caller (both parsePrimary's expression-position
	 * case and parseStmt's statement-position case below share this). Recurses on `else if`
	 * for the chain, matching the standard else-if mental model. */
	function parseIfExpr():Expr {
		expect("(");
		var cond = parseExpr();
		expect(")");
		var thenBranch = parseBraceBlock();
		var elseBranch:Null<Expr> = null;
		if (matchIdent("else")) {
			elseBranch = matchIdent("if") ? parseIfExpr() : parseBraceBlock();
		}
		return MuseNodes.eif(cond, thenBranch, elseBranch);
	}

	/** `{ stmt; stmt; ... }` as a single block expression -- same construction parsePrimary's
	 * own `{`-disambiguation (object literal vs. block) already uses for its block case. */
	function parseBraceBlock():Expr {
		expect("{");
		var es = [for (s in parseStmtListUntil("}")) stmtAsExpr(s)];
		expect("}");
		return MuseNodes.block(es);
	}

	/** Optional `()` / `(bar)` right after `onBar`/`on` -- consumed and ignored either way
	 * (both spellings have meant "the on-bar hook" since before this parenthesized form
	 * existed; the parens are purely a syntax preference, not a real argument list). */
	function parseOnBarParens():Void {
		if (match("(")) {
			if (!check(")")) expectIdentValue();
			expect(")");
		}
	}

	/** Optional `when (cond)` guard clause immediately after `onBar()`/`on(bar)`, BEFORE the
	 * `{`. Reuses the `when` keyword in a new position (not the general-conditional statement
	 * position `when cond: {...}` already has) -- see the else-if-chain doc comment above. */
	function parseOnBarGuard():Null<Expr> {
		if (!matchIdent("when")) return null;
		expect("(");
		var cond = parseExpr();
		expect(")");
		return cond;
	}

	/** Folds a run of `(guard, body)` onBar branches into ONE nested if/else-if/else Stmt --
	 * a trailing branch with `guard == null` becomes the base `else` value; every guarded
	 * branch before it becomes another `else if` link, evaluated in declaration order so the
	 * FIRST true guard wins (not "every true guard runs"). */
	function buildOnBarGuardChain(branches:Array<{guard:Null<Expr>, body:Array<Stmt>}>):Stmt {
		var idx = branches.length - 1;
		var expr:Null<Expr> = null;
		if (branches[idx].guard == null) {
			expr = MuseNodes.block([for (s in branches[idx].body) stmtAsExpr(s)]);
			idx--;
		}
		while (idx >= 0) {
			var b = branches[idx];
			var thenExpr = MuseNodes.block([for (s in b.body) stmtAsExpr(s)]);
			expr = MuseNodes.eif(b.guard, thenExpr, expr);
			idx--;
		}
		return ExprStmt(expr);
	}

	function parseStmtListUntil(end:Null<String>):Array<Stmt> {
		var out:Array<Stmt> = [];
		skipWs();
		while (i < len && (end == null || !check(end))) {
			out.push(parseStmt());
			skipWs();
			if (end == null && i >= len) break;
		}
		return out;
	}

	function parseStmt():Stmt {
		skipWs();
		var stmtStart = i;
		if (matchIdent("onBar") || matchIdent("on")) {
			if (peekIdent() == "bar") expectIdentValue();
			parseOnBarParens();
			var guard = parseOnBarGuard();
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			if (guard == null) {
				// No guard on THIS block -- an unguarded onBar can only ever be a trailing
				// fallback, never the start of a chain, so it stays an ordinary, independently
				// concatenated OnBar (today's behavior, byte-for-byte, for files that never use
				// `when` guards at all).
				return stampStmt(stmtStart, OnBar(body));
			}
			// A guarded onBar() opens an else-if CHAIN: keep consuming immediately-following
			// onBar(...) blocks (guarded -> another else-if link; one trailing unguarded ->
			// the else fallback, which ends the chain) and fold them into ONE OnBar wrapping a
			// single nested if/else-if/else expression (see parseIfExpr's doc comment for why
			// that's semantically "first matching guard wins", not "every true guard runs").
			var branches:Array<{guard:Null<Expr>, body:Array<Stmt>}> = [{guard: guard, body: body}];
			while (matchIdent("onBar") || matchIdent("on")) {
				if (peekIdent() == "bar") expectIdentValue();
				parseOnBarParens();
				var g = parseOnBarGuard();
				expect("{");
				var b = parseStmtListUntil("}");
				expect("}");
				branches.push({guard: g, body: b});
				if (g == null) break;
			}
			return stampStmt(stmtStart, OnBar([buildOnBarGuardChain(branches)]));
		}
		if (matchIdent("onPosition")) {
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return stampStmt(stmtStart, OnPosition(body));
		}
		var tickStart = i;
		if (matchIdent("onTick")) {
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return stampStmt(tickStart, OnTick(body));
		}
		var eventStart = i;
		if (matchIdent("onEvent")) {
			var stream = "events";
			if (match("(")) {
				skipWs();
				if (check('"') || check("'")) stream = parseString();
				else stream = expectIdentValue();
				expect(")");
			}
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return stampStmt(eventStart, OnEvent(stream, body));
		}
		if (matchIdent("when")) {
			var cond = parseExpr();
			expect(":");
			var body:Array<Stmt>;
			if (check("{")) {
				expect("{");
				body = parseStmtListUntil("}");
				expect("}");
			} else {
				body = [parseStmt()];
			}
			return stampStmt(stmtStart, When(cond, body));
		}
		// General `if (cond) { ... } [else if ...]* [else { ... }]?` at statement position --
		// see parseIfExpr's doc comment. `when` (above) stays the no-else spelling; `if` is the
		// general, else-capable one.
		if (matchIdent("if")) {
			return stampStmt(stmtStart, ExprStmt(parseIfExpr()));
		}
		if (matchIdent("for")) {
			expect("(");
			var name = expectIdentValue();
			expectIdent("in");
			var iter = parseExpr();
			expect(")");
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return stampStmt(stmtStart, ForIn(name, iter, body));
		}
		if (matchIdent("return")) {
			skipWs();
			if (check("}") || check(";")) {
				match(";");
				return stampStmt(stmtStart, Return(null));
			}
			var e = parseExpr();
			match(";");
			return stampStmt(stmtStart, Return(e));
		}
		if (matchIdent("use")) {
			var mod = expectIdentValue();
			var args:Array<{name:String, value:Expr}> = [];
			if (match("(")) {
				if (!check(")")) {
					do {
						var an = expectIdentValue();
						expect("=");
						args.push({ name: an, value: parseExpr() });
					} while (match(","));
				}
				expect(")");
			}
			match(";");
			return Use(mod, args);
		}
		var e = parseExpr();
		match(";");
		return switch (e) {
			case EBinop("=", EIdent(n), v):
				if (isSeriesExpr(v)) knownSeries.set(n, true);
				Assign(n, v);
			case ECall(EIdent("long"), args): Order(Long, args);
			case ECall(EIdent("short"), args): Order(Short, args);
			case ECall(EIdent("flat"), args) | ECall(EIdent("close"), args): Order(Flat, args);
			case EIf(c, eif, null):
				When(c, [exprStmt(eif)]);
			default: ExprStmt(e);
		};
	}

	function exprStmt(e:Expr):Stmt {
		return switch (e) {
			case ECall(EIdent("long"), args): Order(Long, args);
			case ECall(EIdent("short"), args): Order(Short, args);
			case ECall(EIdent("flat"), args) | ECall(EIdent("close"), args): Order(Flat, args);
			case EBinop("=", EIdent(n), v): Assign(n, v);
			default: ExprStmt(e);
		};
	}

	function stmtAsExpr(s:Stmt):Expr {
		return switch (s) {
			case ExprStmt(e): e;
			case Return(e): MuseNodes.ereturn(e);
			case Assign(n, e): MuseNodes.binop("=", MuseNodes.ident(n), e);
			case Order(kind, args):
				var n = switch (kind) { case Long: "long"; case Short: "short"; case Flat: "flat"; case Close: "close"; };
				MuseNodes.call(MuseNodes.ident(n), args);
			case When(c, body):
				MuseNodes.eif(c, MuseNodes.block([for (x in body) stmtAsExpr(x)]), null);
			case ForIn(name, iter, body):
				MuseNodes.efor(name, iter, MuseNodes.block([for (x in body) stmtAsExpr(x)]));
			case Block(ss):
				MuseNodes.block([for (x in ss) stmtAsExpr(x)]);
			default:
				MuseNodes.nullExpr();
		};
	}

	// --- expressions ---

	function parseExpr():Expr {
		return parseAssign();
	}

	function parseAssign():Expr {
		var start = i;
		var left = parsePipe();
		if (match("=")) {
			return stampExpr(start, MuseNodes.binop("=", left, parseAssign()));
		}
		return left;
	}

	function parsePipe():Expr {
		var start = i;
		var left = parseOr();
		while (match("|>")) {
			var right = parseOr();
			left = stampExpr(start, desugarPipe(left, right));
		}
		return left;
	}

	function desugarPipe(left:Expr, right:Expr):Expr {
		return switch (right) {
			case EIdent(n): MuseNodes.call(MuseNodes.ident(n), [left]);
			case ECall(callee, args): MuseNodes.call(callee, [left].concat(args));
			default: MuseNodes.call(right, [left]);
		};
	}

	function parseOr():Expr {
		var start = i;
		var left = parseAnd();
		while (true) {
			if (match("||")) left = stampExpr(start, MuseNodes.binop("||", left, parseAnd()));
			else break;
		}
		return left;
	}

	function parseAnd():Expr {
		var start = i;
		var left = parseCmp();
		while (true) {
			if (match("&&")) left = stampExpr(start, MuseNodes.binop("&&", left, parseCmp()));
			else break;
		}
		return left;
	}

	function parseCmp():Expr {
		var start = i;
		var left = parseAdd();
		while (true) {
			if (match(">=")) left = stampExpr(start, MuseNodes.binop(">=", left, parseAdd()));
			else if (match("<=")) left = stampExpr(start, MuseNodes.binop("<=", left, parseAdd()));
			else if (match("==")) left = stampExpr(start, MuseNodes.binop("==", left, parseAdd()));
			else if (match("!=")) left = stampExpr(start, MuseNodes.binop("!=", left, parseAdd()));
			else if (match(">")) left = stampExpr(start, MuseNodes.binop(">", left, parseAdd()));
			else if (match("<")) left = stampExpr(start, MuseNodes.binop("<", left, parseAdd()));
			else break;
		}
		return left;
	}

	function parseAdd():Expr {
		var start = i;
		var left = parseMul();
		while (true) {
			if (match("+")) left = stampExpr(start, MuseNodes.binop("+", left, parseMul()));
			else if (match("-")) left = stampExpr(start, MuseNodes.binop("-", left, parseMul()));
			else break;
		}
		return left;
	}

	function parseMul():Expr {
		var start = i;
		var left = parseUnary();
		while (true) {
			if (match("*")) left = stampExpr(start, MuseNodes.binop("*", left, parseUnary()));
			else if (match("/")) left = stampExpr(start, MuseNodes.binop("/", left, parseUnary()));
			else if (match("%")) left = stampExpr(start, MuseNodes.binop("%", left, parseUnary()));
			else break;
		}
		return left;
	}

	function parseUnary():Expr {
		var start = i;
		if (match("!")) return stampExpr(start, MuseNodes.unop("!", true, parseUnary()));
		if (match("-")) return stampExpr(start, MuseNodes.unop("-", true, parseUnary()));
		return parsePostfix();
	}

	function parsePostfix():Expr {
		var start = i;
		var e = parsePrimary();
		while (true) {
			if (match("(")) {
				var args:Array<Expr> = [];
				if (!check(")")) {
					do args.push(parseExpr()) while (match(","));
				}
				expect(")");
				e = stampExpr(start, MuseNodes.call(e, args));
			} else if (match("[")) {
				var idx = parseExpr();
				expect("]");
				e = stampExpr(start, shouldLookback(e) ? MuseNodes.lookback(e, idx) : MuseNodes.array(e, idx));
			} else if (match(".")) {
				var f = expectIdentValue();
				e = stampExpr(start, MuseNodes.field(e, f));
			} else break;
		}
		return e;
	}

	function parsePrimary():Expr {
		skipWs();
		if (i >= len) throw err("unexpected end of input");
		var start = i;
		var c = src.charAt(i);
		if (c == "(") {
			var arrowArgs = tryParseArrowParams();
			if (arrowArgs != null) {
				expect("=>");
				return stampExpr(start, MuseNodes.efunction(arrowArgs, parseLambdaBody(), Normal, null));
			}
			i++;
			var e = parseExpr();
			expect(")");
			if (check("=>"))
				throw err("arrow parameters must be bare identifiers");
			return stampExpr(start, MuseNodes.parent(e));
		}
		if (c == '"') return stampExpr(start, MuseNodes.stringExpr(parseString()));
		if (c == "'") return stampExpr(start, MuseNodes.stringExpr(parseString()));
		if (c == "[") {
			i++;
			var values:Array<Expr> = [];
			if (!check("]")) {
				do values.push(parseExpr()) while (match(","));
			}
			expect("]");
			return stampExpr(start, MuseNodes.arrayDecl(values));
		}
		if (isDigit(c) || (c == "." && i + 1 < len && isDigit(src.charAt(i + 1))))
			return stampExpr(start, parseNumber());
		if (c == "{") {
			i++;
			if (looksLikeObjectLiteral()) {
				var fields:Array<{name:String, e:Expr}> = [];
				do {
					skipWs();
					var fname = expectIdentValue();
					expect(":");
					fields.push({ name: fname, e: parseExpr() });
				} while (match(","));
				expect("}");
				return stampExpr(start, MuseNodes.object(fields));
			}
			var es = [for (s in parseStmtListUntil("}")) stmtAsExpr(s)];
			expect("}");
			return stampExpr(start, MuseNodes.block(es));
		}
		// Author hole: `?` (untyped) or `?Bool` / `?Scalar` / `?Series`. Lowers (via
		// CorpusSeed) to a synthesis hole the engine fills under the honest gate. Encoded as
		// EMeta("__hole", [tyString], seed) so an UNFILLED sketch is still a valid runnable
		// program — any pass ignorant of __hole just evaluates the seed. Domain/name are P1.
		if (c == "?") {
			i++;
			var ty = matchIdent("Bool") ? "Bool"
				: matchIdent("Scalar") ? "Scalar"
				: matchIdent("Series") ? "Series" : "";
			var seed:Expr = switch (ty) {
				case "Bool": MuseNodes.boolExpr(true);
				case "Series": MuseNodes.ident("close");
				default: MuseNodes.floatExpr(0.0);
			};
			return stampExpr(start, MuseNodes.meta("__hole", [MuseNodes.stringExpr(ty)], seed));
		}
		var id = expectIdentValue();
		// General `if (cond) { ... } [else if (cond) { ... }]* [else { ... }]?`, building a
		// nested EIf chain -- the SAME node `when cond: { ... }` already desugars to (minus
		// `else`), so every backend (interp/JS/checker) already handles this correctly with
		// zero downstream changes. `when` is kept working (large existing corpus, and it's
		// reused as the onBar() guard-clause keyword below) -- `if` is just no longer rejected.
		if (id == "if") return stampExpr(start, parseIfExpr());
		if (id == "true") return stampExpr(start, MuseNodes.boolExpr(true));
		if (id == "false") return stampExpr(start, MuseNodes.boolExpr(false));
		if (id == "null") return stampExpr(start, MuseNodes.nullExpr());
		if (id == "this") return stampExpr(start, MuseNodes.ethis());
		if (id == "super") {
			var method:Null<String> = null;
			if (match(".")) method = expectIdentValue();
			expect("(");
			var args:Array<Expr> = [];
			if (!check(")")) {
				do args.push(parseExpr()) while (match(","));
			}
			expect(")");
			return stampExpr(start, MuseNodes.esuper(method, args));
		}
		if (id == "new") {
			var cname = expectIdentValue();
			expect("(");
			var args:Array<Expr> = [];
			if (!check(")")) {
				do args.push(parseExpr()) while (match(","));
			}
			expect(")");
			return stampExpr(start, MuseNodes.enew(cname, args));
		}
		if (id == "function") return stampExpr(start, parseFunctionLambda());
		// `match(scrut) [ pat => body, ... ]` — committed only when a `[` follows
		// the paren group (so a user value/call named `match(x)` stays a call).
		if (id == "match" && check("(")) {
			var save = i;
			expect("(");
			var scrut = parseExpr();
			expect(")");
			if (check("[")) return stampExpr(start, parseMatchArmsExpr(scrut));
			i = save; // not a match — fall through so postfix `(...)` parses it as a call
		}
		if (isBarField(id)) return stampExpr(start, MuseNodes.barField(id));
		// Bare-ident arrow: `x => body`
		if (check("=>")) {
			expect("=>");
			return stampExpr(start, MuseNodes.efunction([id], parseLambdaBody(), Normal, null));
		}
		return stampExpr(start, MuseNodes.ident(id));
	}

	/** `[ pat [if guard] => body, ... ]` after `match(scrut)`. */
	function parseMatchArmsExpr(scrut:Expr):Expr {
		expect("[");
		var arms:Array<MatchArm> = [];
		skipWs();
		if (!check("]")) {
			do {
				skipWs();
				if (check("]")) break;
				var pat = parseArmPattern();
				var guard:Null<Expr> = null;
				if (matchIdent("if")) guard = parseExpr();
				expect("=>");
				var body = parseExpr();
				arms.push({ pattern: pat, guard: guard, body: body });
			} while (match(","));
		}
		expect("]");
		return MuseNodes.match(scrut, arms);
	}

	/**
	 * One match-arm pattern. Haxe-flavored: a Capitalized identifier is an enum
	 * tag (nullary, or a constructor when followed by `(...)`); a lowercase
	 * identifier binds; `_` wildcards; literals match by value.
	 */
	function parseArmPattern():Pattern {
		skipWs();
		var c = src.charAt(i);
		if (c == '"' || c == "'") return PatLit(CString(parseString()));
		if (isDigit(c) || (c == "." && i + 1 < len && isDigit(src.charAt(i + 1)))) {
			return switch (parseNumber()) {
				case EConst(cc): PatLit(cc);
				default: PatWild;
			};
		}
		var id = expectIdentValue();
		if (id == "_") return PatWild;
		if (id == "true") return PatLit(CBool(true));
		if (id == "false") return PatLit(CBool(false));
		if (id == "null") return PatLit(CNull);
		if (check("(")) {
			expect("(");
			var subs:Array<Pattern> = [];
			if (!check(")")) do subs.push(parseArmPattern()) while (match(","));
			expect(")");
			return PatTag(id, subs);
		}
		var first = id.charAt(0);
		var isTag = first >= "A" && first <= "Z";
		return isTag ? PatTag(id, []) : PatBind(id);
	}

	function isBarField(n:String):Bool {
		return n == "open" || n == "high" || n == "low" || n == "close" || n == "volume"
			|| n == "time" || n == "bar_index" || n == "hl2" || n == "hlc3" || n == "ohlc4"
			// Palette.AUX_FIELDS — offline PIT aux / fund columns on Bar.data
			|| n == "revenue" || n == "pe" || n == "eps" || n == "sentiment"
			|| n == "market_cap" || n == "book_value" || n == "dividend_yield";
	}

	/**
	 * After consuming `{`: object literal iff next tokens are `ident :`.
	 * Statement openers (`when cond:` …) put non-`:` tokens after the first
	 * ident, so blocks keep parsing as blocks. Position is restored.
	 */
	function looksLikeObjectLiteral():Bool {
		var save = i;
		skipWs();
		var id = readIdent();
		var isObj = false;
		if (id != null) {
			skipWs();
			isObj = i < len && src.charAt(i) == ":";
		}
		i = save;
		return isObj;
	}

	/**
	 * Anonymous `function(a, b) …` in expression position.
	 * Fat-arrow forms (`x => …`, `(a, b) => …`) are handled in `parsePrimary`.
	 */
	function parseFunctionLambda():Expr {
		expect("(");
		var args:Array<String> = [];
		if (!check(")")) {
			do args.push(expectIdentValue()) while (match(","));
		}
		expect(")");
		return MuseNodes.efunction(args, parseLambdaBody(), Normal, null);
	}

	/** Shared body for `function(...)` and `=>` lambdas. */
	function parseLambdaBody():Expr {
		skipWs();
		if (check("{")) {
			expect("{");
			var body = MuseNodes.block([for (s in parseStmtListUntil("}")) stmtAsExpr(s)]);
			expect("}");
			return body;
		}
		if (matchIdent("return")) return MuseNodes.ereturn(parseExpr());
		return parseExpr();
	}

	/**
	 * Lookahead: `( )` / `(a)` / `(a, b)` followed by `=>`.
	 * On success consumes through `)` and returns arg names; otherwise restores `i`.
	 * Non-ident params (e.g. `(a+1) =>`) leave the stream unrestored only when
	 * the opener looked like a param list then failed — those throw.
	 */
	function tryParseArrowParams():Null<Array<String>> {
		var save = i;
		skipWs();
		if (i >= len || src.charAt(i) != "(") return null;
		i++; // (
		skipWs();
		var args:Array<String> = [];
		if (!check(")")) {
			while (true) {
				skipWs();
				var id = readIdent();
				if (id == null) {
					i = save;
					return null;
				}
				args.push(id);
				skipWs();
				if (match(",")) continue;
				break;
			}
		}
		if (!match(")")) {
			i = save;
			return null;
		}
		skipWs();
		if (!check("=>")) {
			i = save;
			return null;
		}
		return args;
	}

	function shouldLookback(e:Expr):Bool {
		return switch (e) {
			case EBarField(_): true;
			case EIdent(n): knownSeries.exists(n);
			case ECall(EIdent(n), _): isSeriesCall(n);
			case EParent(inner): shouldLookback(inner);
			default: false;
		};
	}

	function isSeriesExpr(e:Expr):Bool {
		return switch (e) {
			case EBarField(_): true;
			case EIdent(n): knownSeries.exists(n);
			case ECall(EIdent(n), _): isSeriesCall(n);
			case EParent(inner): isSeriesExpr(inner);
			default: false;
		};
	}

	/** True when a call returns Series so `x[1]` should desugar to lookback. */
	function isSeriesCall(name:String):Bool {
		var sig = BuiltinSigs.get(name);
		return sig != null && sig.ret.match(TSeries);
	}

	function parseNumber():Expr {
		var start = i;
		while (i < len && (isDigit(src.charAt(i)) || src.charAt(i) == ".")) i++;
		// Scientific notation: 1e-6 / 2.5E+3 (hscript parity).
		if (i < len) {
			var ec = src.charAt(i);
			if (ec == "e" || ec == "E") {
				var j = i + 1;
				if (j < len) {
					var s = src.charAt(j);
					if (s == "+" || s == "-") j++;
				}
				if (j < len && isDigit(src.charAt(j))) {
					i = j;
					while (i < len && isDigit(src.charAt(i))) i++;
				}
			}
		}
		var s = src.substring(start, i);
		var hasFrac = s.indexOf(".") >= 0 || s.indexOf("e") >= 0 || s.indexOf("E") >= 0;
		if (hasFrac) return MuseNodes.floatExpr(Std.parseFloat(s));
		return MuseNodes.intExpr(Std.parseInt(s));
	}

	function parseString():String {
		var quote = src.charAt(i++);
		var buf = new StringBuf();
		while (i < len) {
			var c = src.charAt(i++);
			if (c == quote) break;
			if (c == "\\") {
				var n = src.charAt(i++);
				buf.add(switch (n) {
					case "n": "\n";
					case "t": "\t";
					case "r": "\r";
					default: n;
				});
			} else buf.add(c);
		}
		return buf.toString();
	}

	// --- lexer helpers ---

	function skipWs():Void {
		while (i < len) {
			var c = src.charAt(i);
			if (c == " " || c == "\t" || c == "\r" || c == "\n") { i++; continue; }
			if (c == "/" && i + 1 < len && src.charAt(i + 1) == "/") {
				i += 2;
				while (i < len && src.charAt(i) != "\n") i++;
				continue;
			}
			if (c == "/" && i + 1 < len && src.charAt(i + 1) == "*") {
				i += 2;
				while (i + 1 < len && !(src.charAt(i) == "*" && src.charAt(i + 1) == "/")) i++;
				i += 2;
				continue;
			}
			break;
		}
	}

	function peekIdent():Null<String> {
		skipWs();
		var save = i;
		var id = readIdent();
		i = save;
		return id;
	}

	function readIdent():Null<String> {
		if (i >= len) return null;
		var c = src.charAt(i);
		if (!isIdentStart(c)) return null;
		var start = i++;
		while (i < len && isIdentPart(src.charAt(i))) i++;
		return src.substring(start, i);
	}

	function matchIdent(want:String):Bool {
		skipWs();
		var save = i;
		var id = readIdent();
		if (id == want) return true;
		i = save;
		return false;
	}

	function expectIdent(want:String):Void {
		if (!matchIdent(want)) throw err('expected `$want`');
	}

	function expectIdentValue():String {
		skipWs();
		var id = readIdent();
		if (id == null) throw err("expected identifier");
		return id;
	}

	function match(tok:String):Bool {
		skipWs();
		if (StringTools.startsWith(src.substr(i), tok)) {
			// multi-char ops: ensure >= isn't matched as >
			if (tok == ">" && (startsAt(i, ">=") || startsAt(i, "|>"))) return false;
			if (tok == "<" && startsAt(i, "<=")) return false;
			if (tok == "=" && (startsAt(i, "==") || startsAt(i, "=>"))) return false;
			if (tok == "!" && startsAt(i, "!=")) return false;
			if (tok == "-" && startsAt(i, "->")) return false;
			i += tok.length;
			return true;
		}
		return false;
	}

	function startsAt(pos:Int, tok:String):Bool {
		return StringTools.startsWith(src.substr(pos), tok);
	}

	function check(tok:String):Bool {
		skipWs();
		return StringTools.startsWith(src.substr(i), tok);
	}

	function expect(tok:String):Void {
		if (!match(tok)) throw err('expected `$tok`');
	}

	function isIdentStart(c:String):Bool {
		var code = c.charCodeAt(0);
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || c == "_";
	}

	function isIdentPart(c:String):Bool {
		return isIdentStart(c) || isDigit(c);
	}

	function isDigit(c:String):Bool {
		var code = c.charCodeAt(0);
		return code >= 48 && code <= 57;
	}

	function stampExpr(start:Int, e:Expr):Expr {
		if (spans != null)
			spans.stampExpr(e, SourcePositions.fromOffset(src, start, origin, i));
		return e;
	}

	function stampStmt(start:Int, s:Stmt):Stmt {
		if (spans != null)
			spans.stampStmt(s, SourcePositions.fromOffset(src, start, origin, i));
		return s;
	}

	function err(msg:String):String {
		return 'StrategyParser($origin@$i): $msg';
	}
}
