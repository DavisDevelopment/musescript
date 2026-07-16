package musescript.parse;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;
import musescript.ast.FnKind;
import musescript.ast.MuseNodes;

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

	public function new() {}

	public function parse(source:String, ?origin:String):MuseProgram {
		this.src = source;
		this.origin = origin != null ? origin : "<strategy>";
		this.i = 0;
		this.len = source.length;
		this.hoisted = [];
		this.knownSeries = new Map();
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
				case "function":
					decls.push(parseFnDecl());
				default:
					stmts = stmts.concat(parseStmtListUntil(null));
					break;
			}
			skipWs();
		}
		return { decls: hoisted.concat(decls), stmts: stmts };
	}

	/** True when source looks like the new surface (not `{ @strategy ... }`). */
	public static function looksLike(source:String):Bool {
		var s = StringTools.ltrim(source);
		return StringTools.startsWith(s, "strategy")
			|| StringTools.startsWith(s, "module")
			|| StringTools.startsWith(s, "template")
			|| StringTools.startsWith(s, "pipeline")
			|| StringTools.startsWith(s, "search")
			|| StringTools.startsWith(s, "param ")
			|| StringTools.startsWith(s, "param\t")
			|| StringTools.startsWith(s, "feature ")
			|| StringTools.startsWith(s, "feature\t")
			|| StringTools.startsWith(s, "indicator ");
	}

	function parseStrategy():Decl {
		expectIdent("strategy");
		var name = expectIdentValue();
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
		match(";");
		var opts:ParamOpts = { ty: ty };
		return ParamDecl(name, def, opts);
	}

	function parseIndicatorDecl():Decl {
		expectIdent("indicator");
		var d = parseValueDeclAfterKeyword();
		switch (d) {
			case IndicatorDecl(name, _, body):
				if (isSeriesExpr(body)) knownSeries.set(name, true);
			default:
		}
		return d;
	}

	function parseFeatureDecl():Decl {
		expectIdent("feature");
		return parseValueDeclAfterKeyword();
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
		if (matchIdent("onBar") || matchIdent("on")) {
			if (peekIdent() == "bar") expectIdentValue();
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return OnBar(body);
		}
		if (matchIdent("onPosition")) {
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return OnPosition(body);
		}
		if (matchIdent("onTick")) {
			expect("{");
			var body = parseStmtListUntil("}");
			expect("}");
			return OnTick(body);
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
			return When(cond, body);
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
			case Assign(n, e): MuseNodes.binop("=", MuseNodes.ident(n), e);
			case Order(kind, args):
				var n = switch (kind) { case Long: "long"; case Short: "short"; case Flat: "flat"; case Close: "close"; };
				MuseNodes.call(MuseNodes.ident(n), args);
			case When(c, body):
				MuseNodes.eif(c, MuseNodes.block([for (x in body) stmtAsExpr(x)]), null);
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
		var left = parsePipe();
		if (match("=")) {
			return MuseNodes.binop("=", left, parseAssign());
		}
		return left;
	}

	function parsePipe():Expr {
		var left = parseOr();
		while (match("|>")) {
			var right = parseOr();
			left = desugarPipe(left, right);
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
		var left = parseAnd();
		while (true) {
			if (match("||")) left = MuseNodes.binop("||", left, parseAnd());
			else break;
		}
		return left;
	}

	function parseAnd():Expr {
		var left = parseCmp();
		while (true) {
			if (match("&&")) left = MuseNodes.binop("&&", left, parseCmp());
			else break;
		}
		return left;
	}

	function parseCmp():Expr {
		var left = parseAdd();
		while (true) {
			if (match(">=")) left = MuseNodes.binop(">=", left, parseAdd());
			else if (match("<=")) left = MuseNodes.binop("<=", left, parseAdd());
			else if (match("==")) left = MuseNodes.binop("==", left, parseAdd());
			else if (match("!=")) left = MuseNodes.binop("!=", left, parseAdd());
			else if (match(">")) left = MuseNodes.binop(">", left, parseAdd());
			else if (match("<")) left = MuseNodes.binop("<", left, parseAdd());
			else break;
		}
		return left;
	}

	function parseAdd():Expr {
		var left = parseMul();
		while (true) {
			if (match("+")) left = MuseNodes.binop("+", left, parseMul());
			else if (match("-")) left = MuseNodes.binop("-", left, parseMul());
			else break;
		}
		return left;
	}

	function parseMul():Expr {
		var left = parseUnary();
		while (true) {
			if (match("*")) left = MuseNodes.binop("*", left, parseUnary());
			else if (match("/")) left = MuseNodes.binop("/", left, parseUnary());
			else if (match("%")) left = MuseNodes.binop("%", left, parseUnary());
			else break;
		}
		return left;
	}

	function parseUnary():Expr {
		if (match("!")) return MuseNodes.unop("!", true, parseUnary());
		if (match("-")) return MuseNodes.unop("-", true, parseUnary());
		return parsePostfix();
	}

	function parsePostfix():Expr {
		var e = parsePrimary();
		while (true) {
			if (match("(")) {
				var args:Array<Expr> = [];
				if (!check(")")) {
					do args.push(parseExpr()) while (match(","));
				}
				expect(")");
				e = MuseNodes.call(e, args);
			} else if (match("[")) {
				var idx = parseExpr();
				expect("]");
				e = shouldLookback(e) ? MuseNodes.lookback(e, idx) : MuseNodes.array(e, idx);
			} else if (match(".")) {
				var f = expectIdentValue();
				e = MuseNodes.field(e, f);
			} else break;
		}
		return e;
	}

	function parsePrimary():Expr {
		skipWs();
		if (i >= len) throw err("unexpected end of input");
		var c = src.charAt(i);
		if (c == "(") {
			i++;
			var e = parseExpr();
			expect(")");
			return MuseNodes.parent(e);
		}
		if (c == '"') return MuseNodes.stringExpr(parseString());
		if (c == "'") return MuseNodes.stringExpr(parseString());
		if (c == "[") {
			i++;
			var values:Array<Expr> = [];
			if (!check("]")) {
				do values.push(parseExpr()) while (match(","));
			}
			expect("]");
			return MuseNodes.arrayDecl(values);
		}
		if (isDigit(c) || (c == "." && i + 1 < len && isDigit(src.charAt(i + 1))))
			return parseNumber();
		if (c == "{") {
			i++;
			var es = [for (s in parseStmtListUntil("}")) stmtAsExpr(s)];
			expect("}");
			return MuseNodes.block(es);
		}
		var id = expectIdentValue();
		if (id == "true") return MuseNodes.boolExpr(true);
		if (id == "false") return MuseNodes.boolExpr(false);
		if (id == "null") return MuseNodes.nullExpr();
		if (isBarField(id)) return MuseNodes.barField(id);
		return MuseNodes.ident(id);
	}

	function isBarField(n:String):Bool {
		return n == "open" || n == "high" || n == "low" || n == "close" || n == "volume"
			|| n == "time" || n == "bar_index" || n == "hl2" || n == "hlc3" || n == "ohlc4";
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

	function isSeriesCall(name:String):Bool {
		return name == "sma" || name == "ema" || name == "rsi" || name == "atr"
			|| name == "wma" || name == "rma" || name == "stdev"
			|| name == "highest" || name == "lowest" || name == "mom"
			|| name == "roc" || name == "change" || name == "pct_change"
			|| name == "vwap" || name == "hl2" || name == "hlc3" || name == "ohlc4";
	}

	function parseNumber():Expr {
		var start = i;
		while (i < len && (isDigit(src.charAt(i)) || src.charAt(i) == ".")) i++;
		var s = src.substring(start, i);
		if (s.indexOf(".") >= 0) return MuseNodes.floatExpr(Std.parseFloat(s));
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

	function err(msg:String):String {
		return 'StrategyParser($origin@$i): $msg';
	}
}
