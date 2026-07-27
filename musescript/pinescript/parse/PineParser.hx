package musescript.pinescript.parse;

import musescript.types.SourcePos;
import musescript.pinescript.PineVersion;
import musescript.pinescript.lex.PineLexer;
import musescript.pinescript.lex.PineToken;
import musescript.pinescript.lex.PineToken.PineTokenKind;
import musescript.pinescript.ast.PineProgram;
import musescript.pinescript.ast.PineDecl;
import musescript.pinescript.ast.PineDecl.PineScriptKind;
import musescript.pinescript.ast.PineDecl.PineParam;
import musescript.pinescript.ast.PineStmt;
import musescript.pinescript.ast.PineStmt.PineDeclKind;
import musescript.pinescript.ast.PineExpr;
import musescript.pinescript.ast.PineExpr.PineArg;
import musescript.pinescript.ast.PineExpr.PineSwitchCase;
import musescript.pinescript.ast.PineType;
import musescript.pinescript.ast.PineType.PineBaseType;

/**
 * Recursive-descent parser with a Pratt expression core. Consumes the layout-
 * explicit token stream from PineLexer (NEWLINE / INDENT / DEDENT) and produces
 * a PineProgram. Version is sniffed up front and threaded so version-gated
 * productions (`:=`, namespaces, `switch`) resolve correctly.
 *
 * Error policy mirrors the rest of the toolchain: collect diagnostics with spans
 * rather than throwing on the first problem, so a partially-broken script still
 * yields a usable AST + a list of what went wrong. Callers check `errors`.
 */
class PineParser {
	final toks:Array<PineToken>;
	final prog:PineProgram;
	var p:Int = 0;
	public final errors:Array<{msg:String, pos:SourcePos}> = [];

	public function new(source:String, ?origin:String) {
		var version = PineVersionSniff.detect(source);
		this.toks = PineLexer.tokenize(source, origin);
		this.prog = new PineProgram();
		this.prog.version = version;
	}

	public static function parse(source:String, ?origin:String):PineProgram {
		return new PineParser(source, origin).run();
	}

	public function run():PineProgram {
		skipNewlines();
		while (!isEof()) {
			for (d in parseTopDeclBatch()) {
				switch (d) {
					case PHeader(_, _): prog.header = d;
					default:
				}
				prog.decls.push(d);
			}
			skipNewlines();
		}
		return prog;
	}

	// ── cursor ──────────────────────────────────────────────────────────────
	inline function cur():PineToken return toks[p];
	inline function kind():PineTokenKind return toks[p].kind;
	inline function isEof():Bool return kind().match(TEof);

	inline function peekKind(o:Int = 1):PineTokenKind {
		var q = p + o;
		return q < toks.length ? toks[q].kind : TEof;
	}

	function advance():PineToken {
		var t = toks[p];
		if (!isEof()) p++;
		return t;
	}

	function err(msg:String, ?pos:SourcePos):Void
		errors.push({msg: msg, pos: pos != null ? pos : cur().pos});

	function skipNewlines():Void
		while (kind().match(TNewline)) p++;

	function eat(k:PineTokenKind):Bool {
		if (Type.enumEq(kind(), k)) { p++; return true; }
		return false;
	}

	function expect(k:PineTokenKind, what:String):Bool {
		if (Type.enumEq(kind(), k)) { p++; return true; }
		err('expected $what');
		return false;
	}

	function isOp(op:String):Bool
		return switch (kind()) { case TOp(o): o == op; default: false; };

	function isKw(w:String):Bool
		return switch (kind()) { case TKeyword(k): k == w; default: false; };

	function identName():Null<String>
		return switch (kind()) { case TIdent(n): n; default: null; };

	// ── top-level ─────────────────────────────────────────────────────────────
	/** Parse one top-level construct. Returns 0..N decls (comma-chained body
	 *  statements expand to multiple `PTop`s). */
	function parseTopDeclBatch():Array<PineDecl> {
		// import user/lib/version [as alias]
		if (isKw("import")) return [parseImport()];
		// [export] type Name  |  [export] f(...) => ...
		if (isKw("export")) {
			advance();
			if (isKw("type")) return [parseTypeDef(true)];
			return [parseFuncDef(true)];
		}
		if (isKw("type")) return [parseTypeDef(false)];

		// header call: indicator(...) / strategy(...) / library(...)
		switch (kind()) {
			case TIdent(n) if (n == "indicator" || n == "strategy" || n == "library" || n == "study"):
				if (peekKind().match(TLParen)) return [parseHeader(n)];
			default:
		}

		// function def:  name(params) =>  ...
		if (identName() != null && peekKind().match(TLParen) && looksLikeFuncDef())
			return [parseFuncDef(false)];

		// otherwise a per-bar body statement (may be comma-chained decls)
		var stmts = parseStatementLine();
		return [for (s in stmts) PTop(s)];
	}

	function parseTopDecl():Null<PineDecl> {
		var batch = parseTopDeclBatch();
		return batch.length > 0 ? batch[0] : null;
	}

	/** Distinguish `name(params) =>` (def) from `name(args)` (call) by scanning
	 *  to the matching `)` and checking for a following `=>`. */
	function looksLikeFuncDef():Bool {
		var depth = 0, q = p + 1;
		while (q < toks.length) {
			switch (toks[q].kind) {
				case TLParen: depth++;
				case TRParen: depth--; if (depth == 0) { q++; break; }
				case TEof: return false;
				default:
			}
			q++;
		}
		return q < toks.length && toks[q].kind.match(TOp("=>"));
	}

	function parseHeader(name:String):PineDecl {
		var pos = cur().pos;
		advance(); // name
		var args = parseCallArgs();
		var kind = switch (name) {
			case "strategy": SkStrategy;
			case "library": SkLibrary;
			default: SkIndicator; // indicator / study
		};
		return prog.stamp(PHeader(kind, args), pos);
	}

	function parseImport():PineDecl {
		var pos = cur().pos;
		advance(); // import
		var user = identName(); if (user != null) advance();
		// user/lib/version — the '/' isn't a lexer token here; Pine writes it as
		// separate idents/ints joined by '/', but our lexer sees '/' as TOp("/").
		var lib = "";
		var version = 0;
		if (isOp("/")) { advance(); lib = identName() != null ? identName() : ""; if (lib != "") advance(); }
		if (isOp("/")) { advance(); switch (kind()) { case TInt(v): version = v; advance(); default: }; }
		var alias:Null<String> = null;
		if (isKw("as") == false && identName() == "as") { advance(); alias = identName(); if (alias != null) advance(); }
		return prog.stamp(PImport(user != null ? user : "", lib, version, alias), pos);
	}

	function parseTypeDef(exported:Bool):PineDecl {
		var pos = cur().pos;
		advance(); // type
		var name = identName() != null ? identName() : "?";
		advance();
		var fields:Array<{name:String, ty:musescript.pinescript.ast.PineType.PineType, ?def:PineExpr}> = [];
		if (eat(TNewline) && eat(TIndent)) {
			while (!kind().match(TDedent) && !isEof()) {
				// `float x = expr` — declared type then name
				var ty = tryParseType();
				var fname = identName();
				if (fname != null) {
					advance();
					var def:Null<PineExpr> = null;
					if (isOp("=")) { advance(); def = parseExpr(); }
					fields.push({name: fname, ty: ty != null ? ty : anyType(), def: def});
				}
				skipNewlines();
			}
			eat(TDedent);
		}
		return prog.stamp(PTypeDef(name, fields, exported), pos);
	}

	function parseFuncDef(exported:Bool):PineDecl {
		var pos = cur().pos;
		var name = identName(); advance();
		var params = parseParamList();
		expect(TOp("=>"), "'=>'");
		var body = parseBodyBlockOrSingle();
		return prog.stamp(PFunc(name, params, body, exported), pos);
	}

	function parseParamList():Array<PineParam> {
		var out:Array<PineParam> = [];
		expect(TLParen, "'('");
		while (!kind().match(TRParen) && !isEof()) {
			var ty = tryParseType();
			var nm = identName();
			if (nm == null) { advance(); continue; }
			advance();
			var def:Null<PineExpr> = null;
			if (isOp("=")) { advance(); def = parseExpr(); }
			out.push({name: nm, ty: ty, def: def});
			if (!eat(TComma)) break;
		}
		expect(TRParen, "')'");
		return out;
	}

	// ── statements ─────────────────────────────────────────────────────────────
	/** Parse one logical statement line. Pine allows comma-chained decls/assigns
	 *  on a single line (`var float a = na, var float b = na` / `x = 1, y = 2`),
	 *  which expand to multiple statements. */
	function parseStatementLine():Array<PineStmt> {
		if (isKw("if")) return [parseIf()];
		if (isKw("for")) return [parseFor()];
		if (isKw("while")) return [parseWhile()];
		if (isKw("switch")) { var sw = parseSwitchTail(); return [PSwitch(sw.subject, sw.cases)]; }
		if (isKw("break")) { advance(); return [PBreak]; }
		if (isKw("continue")) { advance(); return [PContinue]; }
		if (isKw("return")) { advance(); return [PReturn(atStmtEnd() ? null : parseExpr())]; }

		// var / varip / typed decl:  [var|varip] [type] name = expr
		var decl:Null<PineDeclKind> = null;
		if (isKw("var")) { advance(); decl = DkVar; }
		else if (isKw("varip")) { advance(); decl = DkVarip; }

		// tuple destructuring: `[a, b] = expr`
		if (kind().match(TLBracket) && isTupleAssign()) return [parseTupleAssign(decl)];

		var declTy = tryParseType();

		// plain/annotated assignment, reassignment, or compound assign (+= -= *= /= %=)
		var nm = identName();
		if (nm != null && isAssignOp(peekKind())) {
			var out:Array<PineStmt> = [];
			out.push(parseOneAssign(nm, decl, declTy));
			// comma-chained: `, [var|varip] [type] name = expr` / `, name := expr`
			while (eat(TComma)) {
				var d2:Null<PineDeclKind> = null;
				if (isKw("var")) { advance(); d2 = DkVar; }
				else if (isKw("varip")) { advance(); d2 = DkVarip; }
				var ty2 = tryParseType();
				var nm2 = identName();
				if (nm2 == null || !isAssignOp(peekKind())) {
					err("expected assignment after ','");
					break;
				}
				out.push(parseOneAssign(nm2, d2 != null ? d2 : (decl != null ? decl : DkLet), ty2));
			}
			return out;
		}

		// bare expression statement (plot(...), a function call, an if-expr, ...)
		var sp = cur().pos;
		var e = parseExpr();
		return e != null ? [prog.stamp(PExpr(e), sp)] : [];
	}

	function parseOneAssign(nm:String, decl:Null<PineDeclKind>, declTy:Null<musescript.pinescript.ast.PineType.PineType>):PineStmt {
		var pos = cur().pos;
		advance(); // name
		var opKind = kind();
		advance(); // = / := / += / ...
		var rhs = parseExpr();
		return switch (opKind) {
			case TOp(":="): prog.stamp(PReassign(nm, rhs), pos);
			case TOp("+="): prog.stamp(PReassign(nm, PBinop("+", PIdent(nm), rhs)), pos);
			case TOp("-="): prog.stamp(PReassign(nm, PBinop("-", PIdent(nm), rhs)), pos);
			case TOp("*="): prog.stamp(PReassign(nm, PBinop("*", PIdent(nm), rhs)), pos);
			case TOp("/="): prog.stamp(PReassign(nm, PBinop("/", PIdent(nm), rhs)), pos);
			case TOp("%="): prog.stamp(PReassign(nm, PBinop("%", PIdent(nm), rhs)), pos);
			default: // '='
				prog.stamp(PAssign(nm, rhs, decl != null ? decl : DkLet, declTy), pos);
		};
	}

	/** @deprecated prefer parseStatementLine — kept for any single-stmt call sites */
	function parseStatement():Null<PineStmt> {
		var xs = parseStatementLine();
		return xs.length > 0 ? xs[0] : null;
	}

	function atStmtEnd():Bool
		return kind().match(TNewline) || kind().match(TDedent) || isEof();

	static function isAssignOp(k:PineTokenKind):Bool {
		return switch (k) {
			case TOp("=") | TOp(":=") | TOp("+=") | TOp("-=") | TOp("*=") | TOp("/=") | TOp("%="): true;
			default: false;
		};
	}

	/** A `[` at statement start is a tuple-assign iff a matching `]` is followed
	 *  by `=` / `:=`. Otherwise it's an array-literal expression statement. */
	function isTupleAssign():Bool {
		var depth = 0, q = p;
		while (q < toks.length) {
			switch (toks[q].kind) {
				case TLBracket: depth++;
				case TRBracket: depth--; if (depth == 0) { q++; break; }
				case TEof: return false;
				default:
			}
			q++;
		}
		return q < toks.length && (toks[q].kind.match(TOp("=")) || toks[q].kind.match(TOp(":=")));
	}

	function parseTupleAssign(decl:Null<PineDeclKind>):PineStmt {
		var pos = cur().pos;
		advance(); // [
		var names:Array<String> = [];
		while (!kind().match(TRBracket) && !isEof()) {
			var n = identName();
			if (n != null) { names.push(n); advance(); }
			if (!eat(TComma)) break;
		}
		expect(TRBracket, "']'");
		expect(TOp("="), "'='");
		return prog.stamp(PTupleAssign(names, parseExpr(), decl), pos);
	}

	function parseIf():PineStmt {
		var pos = cur().pos;
		advance(); // if
		var cond = parseExpr();
		var then = parseBodyBlockOrSingle();
		var elifs:Array<{cond:PineExpr, body:Array<PineStmt>}> = [];
		var els:Null<Array<PineStmt>> = null;
		// `else if` / `else` at the same indentation appear as top tokens after DEDENT
		while (isKw("else") || (kind().match(TNewline) && peekIsElse())) {
			skipNewlines();
			if (!isKw("else")) break;
			advance(); // else
			if (isKw("if")) { advance(); var c = parseExpr(); elifs.push({cond: c, body: parseBodyBlockOrSingle()}); }
			else { els = parseBodyBlockOrSingle(); break; }
		}
		return prog.stamp(PIf(cond, then, elifs, els), pos);
	}

	function peekIsElse():Bool {
		var q = p;
		while (q < toks.length && toks[q].kind.match(TNewline)) q++;
		return q < toks.length && toks[q].kind.match(TKeyword("else"));
	}

	function parseFor():PineStmt {
		var pos = cur().pos;
		advance(); // for
		// for [i, v] in arr   |   for i = 0 to n [by s]
		if (kind().match(TLBracket)) {
			advance();
			var vars:Array<String> = [];
			while (!kind().match(TRBracket) && !isEof()) {
				var n = identName(); if (n != null) { vars.push(n); advance(); }
				if (!eat(TComma)) break;
			}
			expect(TRBracket, "']'");
			if (isKw("in")) advance();
			var iter = parseExpr();
			return prog.stamp(PForIn(vars, iter, parseBodyBlockOrSingle()), pos);
		}
		var v = identName(); if (v != null) advance();
		if (isKw("in")) {
			advance();
			var iter = parseExpr();
			return prog.stamp(PForIn([v], iter, parseBodyBlockOrSingle()), pos);
		}
		expect(TOp("="), "'='");
		var from = parseExpr();
		if (isKw("to")) advance();
		else err("expected 'to'");
		var to = parseExpr();
		var step:Null<PineExpr> = null;
		if (isKw("by")) { advance(); step = parseExpr(); }
		return prog.stamp(PForTo(v, from, to, step, parseBodyBlockOrSingle()), pos);
	}

	function parseWhile():PineStmt {
		var pos = cur().pos;
		advance();
		var cond = parseExpr();
		return prog.stamp(PWhile(cond, parseBodyBlockOrSingle()), pos);
	}

	// `switch` shared tail for both statement and expression positions.
	function parseSwitchTail():{subject:Null<PineExpr>, cases:Array<PineSwitchCase>} {
		advance(); // switch
		var subject:Null<PineExpr> = atBlockStart() ? null : parseExpr();
		var cases:Array<PineSwitchCase> = [];
		if (eat(TNewline) && eat(TIndent)) {
			while (!kind().match(TDedent) && !isEof()) {
				// `pattern => body`  or default `=> body`
				var pat:Null<PineExpr> = isOp("=>") ? null : parseExpr();
				expect(TOp("=>"), "'=>'");
				cases.push({pattern: pat, body: parseBodyBlockOrSingle()});
				skipNewlines();
			}
			eat(TDedent);
		}
		return {subject: subject, cases: cases};
	}

	inline function atBlockStart():Bool
		return kind().match(TNewline) || kind().match(TIndent);

	/** Parse either an indented block (NEWLINE INDENT stmts DEDENT) or a single
	 *  inline statement (Pine allows `if x` followed by one line, or same-line). */
	function parseBodyBlockOrSingle():Array<PineStmt> {
		if (kind().match(TNewline) && peekKind().match(TIndent)) {
			advance(); advance(); // NEWLINE INDENT
			var body:Array<PineStmt> = [];
			while (!kind().match(TDedent) && !isEof()) {
				for (s in parseStatementLine()) body.push(s);
				skipNewlines();
			}
			eat(TDedent);
			return body;
		}
		// single inline statement (may still be comma-chained)
		return parseStatementLine();
	}

	// ── expressions (Pratt) ─────────────────────────────────────────────────────
	public function parseExpr():PineExpr
		return parseTernary();

	function parseTernary():PineExpr {
		var c = parseBinary(0);
		if (isOp("?")) {
			advance();
			var t = parseTernary();
			expect(TColon, "':'");
			var f = parseTernary();
			return PTernary(c, t, f);
		}
		return c;
	}

	// precedence table, low → high
	static final PREC:Array<Array<String>> = [
		["or"],
		["and"],
		["==", "!=", "<", ">", "<=", ">="],
		["+", "-"],
		["*", "/", "%"],
	];

	function parseBinary(level:Int):PineExpr {
		if (level >= PREC.length) return parseUnary();
		var left = parseBinary(level + 1);
		while (true) {
			var op = curOpOrWord();
			if (op == null || PREC[level].indexOf(op) < 0) break;
			advance();
			var right = parseBinary(level + 1);
			left = PBinop(op, left, right);
		}
		return left;
	}

	/** `and`/`or` are keywords, arithmetic/comparison are TOp — unify lookup. */
	function curOpOrWord():Null<String> {
		return switch (kind()) {
			case TOp(o): o;
			case TKeyword(k) if (k == "and" || k == "or"): k;
			default: null;
		};
	}

	function parseUnary():PineExpr {
		if (isOp("-")) { advance(); return PUnop("-", parseUnary()); }
		if (isOp("+")) { advance(); return parseUnary(); }
		if (isKw("not")) { advance(); return PUnop("not", parseUnary()); }
		return parsePostfix();
	}

	function parsePostfix():PineExpr {
		var e = parsePrimary();
		while (true) {
			switch (kind()) {
				case TDot:
					advance();
					var f = identName();
					if (f != null) { advance(); e = PField(e, f); }
					else break;
				case TOp("<") if (looksLikeGenericArgs()):
					// `array.new<float>()` / `map.new<float, int>()` — skip type
					// args; lowering doesn't need them for UnknownBuiltin emit.
					skipGenericArgs();
					if (kind().match(TLParen)) {
						var args = parseCallArgs();
						e = PCall(e, args);
					}
				case TLParen:
					var args = parseCallArgs();
					e = PCall(e, args);
				case TLBracket:
					// history reference e[n]
					advance();
					var n = parseExpr();
					expect(TRBracket, "']'");
					e = PHistory(e, n);
				default:
					break;
			}
		}
		return e;
	}

	/** True when `<...>` at the cursor is a generic type-arg list followed by `(`,
	 *  not a comparison (`a < b`). */
	function looksLikeGenericArgs():Bool {
		if (!isOp("<")) return false;
		var depth = 0, q = p;
		while (q < toks.length) {
			switch (toks[q].kind) {
				case TOp("<"): depth++;
				case TOp(">"):
					depth--;
					if (depth == 0) {
						q++;
						return q < toks.length && toks[q].kind.match(TLParen);
					}
				case TEof | TNewline | TIndent | TDedent:
					return false;
				case TOp(o) if (o == "+" || o == "-" || o == "*" || o == "/" || o == "%"
					|| o == "==" || o == "!=" || o == "<=" || o == ">=" || o == "?"):
					// comparison / arithmetic inside `<...>` ⇒ not type args
					if (depth == 1) return false;
				default:
			}
			q++;
		}
		return false;
	}

	function skipGenericArgs():Void {
		if (!isOp("<")) return;
		var depth = 0;
		while (!isEof()) {
			switch (kind()) {
				case TOp("<"): depth++; advance();
				case TOp(">"):
					depth--;
					advance();
					if (depth == 0) return;
				default:
					advance();
			}
		}
	}

	function parseCallArgs():Array<PineArg> {
		var out:Array<PineArg> = [];
		expect(TLParen, "'('");
		while (!kind().match(TRParen) && !isEof()) {
			// named arg?  name = value  (only when next is '=' and not '==')
			var name:Null<String> = null;
			if (identName() != null && peekKind().match(TOp("="))) {
				name = identName();
				advance(); advance(); // name '='
			}
			var v = parseExpr();
			out.push({name: name, value: v});
			if (!eat(TComma)) break;
		}
		expect(TRParen, "')'");
		return out;
	}

	function parsePrimary():PineExpr {
		var t = cur();
		switch (t.kind) {
			case TInt(v): advance(); return PInt(v);
			case TFloat(v): advance(); return PFloat(v);
			case TString(v): advance(); return PString(v);
			case TBool(v): advance(); return PBool(v);
			case TColor(h): advance(); return PColor(h);
			case TKeyword("na"): advance(); return PNa;
			case TKeyword("if"): return parseIfExpr();
			case TKeyword("switch"):
				var sw = parseSwitchTail();
				return PSwitchExpr(sw.subject, sw.cases);
			case TIdent(n): advance(); return PIdent(n);
			case TLParen:
				advance();
				var e = parseExpr();
				expect(TRParen, "')'");
				return e;
			case TLBracket:
				// tuple / array literal in expression position
				advance();
				var items:Array<PineExpr> = [];
				while (!kind().match(TRBracket) && !isEof()) {
					items.push(parseExpr());
					if (!eat(TComma)) break;
				}
				expect(TRBracket, "']'");
				return PTuple(items);
			default:
				err('unexpected token ${musescript.pinescript.lex.PineToken.PineTokens.describe(t.kind)}');
				advance();
				return PNa;
		}
	}

	function parseIfExpr():PineExpr {
		advance(); // if
		var cond = parseExpr();
		var t = parseBodyBlockOrSingle();
		var f:Null<Array<PineStmt>> = null;
		if (peekIsElse() || isKw("else")) {
			skipNewlines();
			if (isKw("else")) { advance(); f = parseBodyBlockOrSingle(); }
		}
		return PIfExpr(cond, t, f);
	}

	// ── type annotations ────────────────────────────────────────────────────────
	static final TYPE_WORDS:Map<String, musescript.pinescript.ast.PineType.PineBaseType> = [
		"int" => TyInt, "float" => TyFloat, "bool" => TyBool, "string" => TyString,
		"color" => TyColor, "line" => TyLine, "label" => TyLabel, "box" => TyBox,
		"table" => TyTable,
	];

	static final TYPE_QUALS:Map<String, musescript.pinescript.ast.PineType.PineQualifier> = [
		"series" => QSeries, "simple" => QSimple, "const" => QConst, "input" => QInput,
	];

	/** Optionally consume a Pine type annotation used as a declaration /
	 *  parameter prefix. Accepts:
	 *    float x
	 *    series float source
	 *    simple int period
	 *    float[] arr          (array-of form)
	 * Returns null when the current token is a value, not a type. */
	function tryParseType():Null<musescript.pinescript.ast.PineType.PineType> {
		var save = p;
		var qual = QSeries;

		// optional qualifier: series|simple|const|input — only when followed by a type word
		switch (kind()) {
			case TIdent(n) if (TYPE_QUALS.exists(n) && peekIsTypeWord()):
				qual = TYPE_QUALS.get(n);
				advance();
			default:
		}

		var base:Null<musescript.pinescript.ast.PineType.PineBaseType> = null;
		switch (kind()) {
			case TIdent(n) if (n == "array" && peekKind().match(TOp("<"))):
				// array<T>  (v5+ generic form)
				advance(); // array
				advance(); // <
				var el = parseTypeNameAsBase();
				if (!isOp(">")) { p = save; return null; }
				advance(); // >
				base = TyArray(el != null ? el : TyUnknown);
			case TIdent(n) if (n == "matrix" && peekKind().match(TOp("<"))):
				advance(); // matrix
				advance(); // <
				var el = parseTypeNameAsBase();
				if (!isOp(">")) { p = save; return null; }
				advance(); // >
				base = TyMatrix(el != null ? el : TyUnknown);
			case TIdent(n) if (TYPE_WORDS.exists(n) && typeWordIsAnnotation()):
				advance();
				base = TYPE_WORDS.get(n);
			case TIdent(n) if (typeWordIsAnnotation()):
				// user-defined type as annotation: `Pivot x` / `var Pivot p = ...`
				advance();
				base = TyUserType(n);
			default:
				p = save;
				return null;
		}

		// optional `[]` → array-of (Pine `float[]` / `var float[] xs`)
		if (kind().match(TLBracket) && peekKind().match(TRBracket)) {
			advance(); // [
			advance(); // ]
			base = TyArray(base);
		}

		return {qual: qual, base: base};
	}

	function peekIsTypeWord():Bool {
		return switch (peekKind()) {
			case TIdent(n) if (TYPE_WORDS.exists(n) || n == "array" || n == "matrix"): true;
			case TIdent(_): true; // UDT name after qualifier: `series Pivot`
			default: false;
		};
	}

	/** Consume a bare type name used inside `array<T>` / `matrix<T>`. */
	function parseTypeNameAsBase():Null<musescript.pinescript.ast.PineType.PineBaseType> {
		return switch (kind()) {
			case TIdent(n) if (TYPE_WORDS.exists(n)):
				advance();
				TYPE_WORDS.get(n);
			case TIdent(n):
				advance();
				TyUserType(n);
			default:
				null;
		};
	}

	/** True when the token after the current type-word looks like a binding
	 *  (`float x`, `float[] xs`, `array<T> xs`) rather than a value use
	 *  (`color.new`, `float(x)`, `array.get`). */
	function typeWordIsAnnotation():Bool {
		return switch (peekKind()) {
			case TIdent(_): true;
			case TLBracket: true;
			case TOp("<"): true; // array<T>
			default: false;
		};
	}

	/** @deprecated use typeWordIsAnnotation — kept for any external callers */
	function identAfterIsBinding():Bool return typeWordIsAnnotation();

	inline function anyType():musescript.pinescript.ast.PineType.PineType
		return {qual: QSeries, base: TyUnknown};
}

