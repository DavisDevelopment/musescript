package musescript.parse;

import hscript.Expr;

/**
 * Native tokenizer + parser for the legacy annotation dialect — ROADMAP.md
 * "Native front end", Stage B.
 *
 * Emits the exact same hscript-shaped AST (`hscript.Expr`, hscriptPos records)
 * as the vendored `hscript.Parser`, so MuseParser's battle-tested lowering is
 * reused unchanged and parity is gated purely on parse behavior. The vendored
 * parser is the SPEC: every method here mirrors its namesake, including its
 * quirks (unary-minus const folding, float exponent arithmetic, comprehension
 * temp naming, `->` lambda reinterpretation, semicolon-after-block leniency).
 *
 * Config is baked to MuseParser's settings: allowTypes, allowMetadata,
 * allowJSON all true.
 *
 * Constructs the legacy dialect never uses (XML markup, `#` preprocessor)
 * throw `NativeUnsupported`, which MuseParser catches to fall back to the
 * vendored parser — counted, never silent (see MuseParser.nativeFallbacks).
 * Real syntax errors throw hscript.Expr.Error exactly like the vendored path.
 */
class NativeUnsupported {
	public var what:String;
	public function new(what:String) this.what = what;
	public function toString():String return 'NativeParser: unsupported construct: $what';
}

enum NToken {
	TEof;
	TConst(c:Const);
	TId(s:String);
	TOp(s:String);
	TPOpen;
	TPClose;
	TBrOpen;
	TBrClose;
	TDot;
	TQuestionDot;
	TComma;
	TSemicolon;
	TBkOpen;
	TBkClose;
	TQuestion;
	TDoubleDot;
	TMeta(s:String);
}

class NativeParser {
	// ── tokenizer state ──────────────────────────────────────────────────────
	var input:String;
	var readPos:Int;
	var char:Int;
	var line:Int;
	var origin:String;
	var tokens:Array<{t:NToken, min:Int, max:Int}>;
	var tokenMin:Int;
	var tokenMax:Int;
	var oldTokenMin:Int;
	var oldTokenMax:Int;
	var uid:Int = 0;

	static var opPriority:Map<String, Int>;
	static var opRightAssoc:Map<String, Bool>;
	static var ops:Array<Bool>;
	static var idents:Array<Bool>;

	static function initTables():Void {
		if (opPriority != null) return;
		var priorities = [
			["%"],
			["*", "/"],
			["+", "-"],
			["<<", ">>", ">>>"],
			["|", "&", "^"],
			["==", "!=", ">", "<", ">=", "<="],
			["..."],
			["&&"],
			["||"],
			["=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", ">>>=", "|=", "&=", "^=", "=>"],
			["->"],
			["in", "is"]
		];
		opPriority = new Map();
		opRightAssoc = new Map();
		for (i in 0...priorities.length)
			for (x in priorities[i]) {
				opPriority.set(x, i);
				if (i == 9) opRightAssoc.set(x, true);
			}
		for (x in ["!", "++", "--", "~"])
			opPriority.set(x, x == "++" || x == "--" ? -1 : -2);
		ops = [];
		idents = [];
		var opChars = "+*/-=!><&|^%~";
		var identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
		for (i in 0...opChars.length) ops[opChars.charCodeAt(i)] = true;
		for (i in 0...identChars.length) idents[identChars.charCodeAt(i)] = true;
	}

	public function new() {
		initTables();
	}

	public function parseString(s:String, ?origin:String = "hscript", ?position:Int = 0):Expr {
		this.origin = origin;
		this.input = s;
		this.readPos = 0;
		this.char = -1;
		this.line = 1;
		this.tokens = [];
		this.tokenMin = this.oldTokenMin = position;
		this.tokenMax = this.oldTokenMax = position;
		this.uid = 0;
		var a = new Array<Expr>();
		while (true) {
			var tk = token();
			if (tk == TEof) break;
			push(tk);
			parseFullExpr(a);
		}
		return if (a.length == 1) a[0] else mk(EBlock(a), 0);
	}

	// ── infrastructure (mirrors hscript.Parser) ──────────────────────────────

	inline function expr(e:Expr):ExprDef {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	inline function pmin(e:Expr):Int {
		#if hscriptPos
		return e == null ? 0 : e.pmin;
		#else
		return 0;
		#end
	}

	inline function pmax(e:Expr):Int {
		#if hscriptPos
		return e == null ? 0 : e.pmax;
		#else
		return 0;
		#end
	}

	inline function mk(e:ExprDef, ?pmin:Int, ?pmax:Int):Expr {
		#if hscriptPos
		if (e == null) return null;
		if (pmin == null) pmin = tokenMin;
		if (pmax == null) pmax = tokenMax;
		return { e: e, pmin: pmin, pmax: pmax, origin: origin, line: line };
		#else
		return e;
		#end
	}

	function error(err:ErrorDef, pmin:Int, pmax:Int):Void {
		#if hscriptPos
		throw new Error(err, pmin, pmax, origin, line);
		#else
		throw err;
		#end
	}

	function invalidChar(c:Int):Void {
		error(EInvalidChar(c), readPos - 1, readPos - 1);
	}

	function unexpected(tk:NToken):Dynamic {
		error(EUnexpected(tokenString(tk)), tokenMin, tokenMax);
		return null;
	}

	function unsupported(what:String):Dynamic {
		throw new NativeUnsupported(what);
	}

	inline function push(tk:NToken):Void {
		tokens.push({ t: tk, min: tokenMin, max: tokenMax });
		tokenMin = oldTokenMin;
		tokenMax = oldTokenMax;
	}

	inline function ensure(tk:NToken):Void {
		var t = token();
		if (!Type.enumEq(t, tk)) unexpected(t);
	}

	inline function ensureToken(tk:NToken):Void {
		var t = token();
		if (!Type.enumEq(t, tk)) unexpected(t);
	}

	function maybe(tk:NToken):Bool {
		var t = token();
		if (Type.enumEq(t, tk)) return true;
		push(t);
		return false;
	}

	function getIdent():String {
		var tk = token();
		return switch (tk) {
			case TId(id): id;
			default:
				unexpected(tk);
				null;
		};
	}

	// ── statement/expression parsing (mirrors hscript.Parser) ────────────────

	function isBlock(e:Expr):Bool {
		if (e == null) return false;
		return switch (expr(e)) {
			case EBlock(_), EObject(_), ESwitch(_): true;
			case EFunction(_, e, _, _): isBlock(e);
			case EVar(_, t, e): e != null ? isBlock(e) : t != null ? t.match(CTAnon(_)) : false;
			case EIf(_, e1, e2): if (e2 != null) isBlock(e2) else isBlock(e1);
			case EBinop(_, _, e): isBlock(e);
			case EUnop(_, prefix, e): !prefix && isBlock(e);
			case EWhile(_, e): isBlock(e);
			case EDoWhile(_, e): isBlock(e);
			case EFor(_, _, e), EForGen(_, e): isBlock(e);
			case EReturn(e): e != null && isBlock(e);
			case ETry(_, _, _, e): isBlock(e);
			case EMeta(_, _, e): isBlock(e);
			default: false;
		};
	}

	function parseFullExpr(exprs:Array<Expr>):Void {
		var e = parseExpr();
		exprs.push(e);
		var tk = token();
		// var a, b, c; chains onto extra EVars
		while (tk == TComma && e != null && expr(e).match(EVar(_))) {
			e = parseStructure("var");
			exprs.push(e);
			tk = token();
		}
		if (tk != TSemicolon && tk != TEof) {
			if (isBlock(e))
				push(tk);
			else
				unexpected(tk);
		}
	}

	function parseObject(p1:Int):Expr {
		var fl = new Array<{name:String, e:Expr}>();
		while (true) {
			var tk = token();
			var id = null;
			switch (tk) {
				case TId(i): id = i;
				case TConst(c):
					switch (c) {
						case CString(s): id = s;
						default: unexpected(tk);
					}
				case TBrClose:
					break;
				default:
					unexpected(tk);
					break;
			}
			ensure(TDoubleDot);
			fl.push({ name: id, e: parseExpr() });
			tk = token();
			switch (tk) {
				case TBrClose: break;
				case TComma:
				default: unexpected(tk);
			}
		}
		return parseExprNext(mk(EObject(fl), p1));
	}

	function parseExpr():Expr {
		var tk = token();
		var p1 = tokenMin;
		switch (tk) {
			case TId(id):
				var e = parseStructure(id);
				if (e == null)
					e = mk(EIdent(id));
				return parseExprNext(e);
			case TConst(c):
				return parseExprNext(mk(EConst(c)));
			case TPOpen:
				tk = token();
				if (Type.enumEq(tk, TPClose)) {
					ensureToken(TOp("->"));
					var eret = parseExpr();
					return mkLambda([], eret, p1);
				}
				push(tk);
				var e = parseExpr();
				tk = token();
				switch (tk) {
					case TPClose:
						return parseExprNext(mk(EParent(e), p1, tokenMax));
					case TDoubleDot:
						var t = parseType();
						tk = token();
						switch (tk) {
							case TPClose:
								return parseExprNext(mk(ECheckType(e, t), p1, tokenMax));
							case TComma:
								switch (expr(e)) {
									case EIdent(v): return parseLambda([{ name: v, t: t }], pmin(e));
									default:
								}
							default:
						}
					case TComma:
						switch (expr(e)) {
							case EIdent(v): return parseLambda([{ name: v }], pmin(e));
							default:
						}
					default:
				}
				return unexpected(tk);
			case TBrOpen:
				tk = token();
				switch (tk) {
					case TBrClose:
						return parseExprNext(mk(EObject([]), p1));
					case TId(_):
						var tk2 = token();
						push(tk2);
						push(tk);
						switch (tk2) {
							case TDoubleDot:
								return parseExprNext(parseObject(p1));
							default:
						}
					case TConst(c):
						switch (c) {
							case CString(_):
								var tk2 = token();
								push(tk2);
								push(tk);
								switch (tk2) {
									case TDoubleDot:
										return parseExprNext(parseObject(p1));
									default:
								}
							default:
								push(tk);
						}
					default:
						push(tk);
				}
				var a = new Array<Expr>();
				while (true) {
					parseFullExpr(a);
					tk = token();
					if (Type.enumEq(tk, TBrClose))
						break;
					push(tk);
				}
				return mk(EBlock(a), p1);
			case TOp(op):
				if (op == "-") {
					var start = tokenMin;
					var e = parseExpr();
					if (e == null)
						return makeUnop(op, e);
					switch (expr(e)) {
						case EConst(CInt(i)):
							return mk(EConst(CInt(-i)), start, pmax(e));
						case EConst(CFloat(f)):
							return mk(EConst(CFloat(-f)), start, pmax(e));
						default:
							return makeUnop(op, e);
					}
				}
				if (opPriority.get(op) < 0)
					return makeUnop(op, parseExpr());
				if (op == "<")
					return unsupported("XML markup literal");
				return unexpected(tk);
			case TBkOpen:
				var a = new Array<Expr>();
				tk = token();
				var first = true;
				while (!Type.enumEq(tk, TBkClose)) {
					if (!first) {
						if (!Type.enumEq(tk, TComma))
							unexpected(tk);
						else {
							tk = token();
							if (Type.enumEq(tk, TBkClose))
								break;
						}
					}
					first = false;
					push(tk);
					a.push(parseExpr());
					tk = token();
				}
				if (a.length == 1 && a[0] != null)
					switch (expr(a[0])) {
						case EFor(_), EWhile(_), EDoWhile(_):
							var tmp = "__a_" + (uid++);
							var e = mk(EBlock([
								mk(EVar(tmp, null, mk(EArrayDecl([]), p1)), p1),
								mapCompr(tmp, a[0]),
								mk(EIdent(tmp), p1),
							]), p1);
							return parseExprNext(e);
						default:
					}
				return parseExprNext(mk(EArrayDecl(a), p1));
			case TMeta(id):
				var args = parseMetaArgs();
				return mk(EMeta(id, args, parseExpr()), p1);
			default:
				return unexpected(tk);
		}
	}

	function parseLambda(args:Array<Argument>, pmin:Int):Expr {
		while (true) {
			var id = getIdent();
			var t = maybe(TDoubleDot) ? parseType() : null;
			args.push({ name: id, t: t });
			var tk = token();
			switch (tk) {
				case TComma:
				case TPClose:
					break;
				default:
					unexpected(tk);
					break;
			}
		}
		ensureToken(TOp("->"));
		var eret = parseExpr();
		return mkLambda(args, eret, pmin);
	}

	function mkLambda(args:Array<Argument>, eret:Expr, p:Int):Expr {
		return mk(EFunction(args, mk(EMeta(":lambda", [], mk(EReturn(eret), pmin(eret))), p)), p);
	}

	function parseMetaArgs():Null<Array<Expr>> {
		var tk = token();
		if (!Type.enumEq(tk, TPOpen)) {
			push(tk);
			return null;
		}
		var args = [];
		tk = token();
		if (!Type.enumEq(tk, TPClose)) {
			push(tk);
			while (true) {
				args.push(parseExpr());
				switch (token()) {
					case TComma:
					case TPClose:
						break;
					case tk:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function mapCompr(tmp:String, e:Expr):Expr {
		if (e == null) return null;
		var edef = switch (expr(e)) {
			case EFor(v, it, e2): EFor(v, it, mapCompr(tmp, e2));
			case EForGen(it, e2): EForGen(it, mapCompr(tmp, e2));
			case EWhile(cond, e2): EWhile(cond, mapCompr(tmp, e2));
			case EDoWhile(cond, e2): EDoWhile(cond, mapCompr(tmp, e2));
			case EIf(cond, e1, e2) if (e2 == null): EIf(cond, mapCompr(tmp, e1), null);
			case EBlock([e]): EBlock([mapCompr(tmp, e)]);
			case EParent(e2): EParent(mapCompr(tmp, e2));
			default:
				ECall(mk(EField(mk(EIdent(tmp), pmin(e), pmax(e)), "push"), pmin(e), pmax(e)), [e]);
		}
		return mk(edef, pmin(e), pmax(e));
	}

	function makeUnop(op:String, e:Expr):Expr {
		return switch (expr(e)) {
			case EBinop(bop, e1, e2): mk(EBinop(bop, makeUnop(op, e1), e2), pmin(e1), pmax(e2));
			case ETernary(e1, e2, e3): mk(ETernary(makeUnop(op, e1), e2, e3), pmin(e1), pmax(e3));
			default: mk(EUnop(op, true, e), pmin(e), pmax(e));
		};
	}

	function makeBinop(op:String, e1:Expr, e:Expr):Expr {
		return switch (expr(e)) {
			case EBinop(op2, e2, e3):
				var delta = opPriority.get(op) - opPriority.get(op2);
				if (delta < 0 || (delta == 0 && !opRightAssoc.exists(op)))
					mk(EBinop(op2, makeBinop(op, e1, e2), e3), pmin(e1), pmax(e3));
				else
					mk(EBinop(op, e1, e), pmin(e1), pmax(e));
			case ETernary(e2, e3, e4):
				if (opRightAssoc.exists(op))
					mk(EBinop(op, e1, e), pmin(e1), pmax(e));
				else
					mk(ETernary(makeBinop(op, e1, e2), e3, e4), pmin(e1), pmax(e));
			default:
				mk(EBinop(op, e1, e), pmin(e1), pmax(e));
		};
	}

	function parseStructure(id:String):Null<Expr> {
		var p1 = tokenMin;
		return switch (id) {
			case "if":
				ensure(TPOpen);
				var cond = parseExpr();
				ensure(TPClose);
				var e1 = parseExpr();
				var e2 = null;
				var semic = false;
				var tk = token();
				if (tk == TSemicolon) {
					semic = true;
					tk = token();
				}
				if (Type.enumEq(tk, TId("else")))
					e2 = parseExpr();
				else {
					push(tk);
					if (semic) push(TSemicolon);
				}
				mk(EIf(cond, e1, e2), p1, (e2 == null) ? tokenMax : pmax(e2));
			case "var", "final":
				var ident = getIdent();
				var tk = token();
				var t = null;
				if (tk == TDoubleDot) {
					t = parseType();
					tk = token();
				}
				var e = null;
				switch (tk) {
					case TOp("="): e = parseExpr();
					case TOp(_): unexpected(tk);
					case TComma | TSemicolon: push(tk);
					case _ if (t != null): push(tk);
					default: unexpected(tk);
				}
				mk(EVar(ident, t, e), p1, (e == null) ? tokenMax : pmax(e));
			case "while":
				var econd = parseExpr();
				var e = parseExpr();
				mk(EWhile(econd, e), p1, pmax(e));
			case "do":
				var e = parseExpr();
				var tk = token();
				switch (tk) {
					case TId("while"): // valid
					default: unexpected(tk);
				}
				var econd = parseExpr();
				mk(EDoWhile(econd, e), p1, pmax(econd));
			case "for":
				ensure(TPOpen);
				var eit = parseExpr();
				ensure(TPClose);
				var e = parseExpr();
				switch (expr(eit)) {
					case EBinop("in", ev, eit2):
						switch (expr(ev)) {
							case EIdent(v):
								return mk(EFor(v, eit2, e), p1, pmax(e));
							default:
						}
					default:
				}
				mk(EForGen(eit, e), p1, pmax(e));
			case "break": mk(EBreak);
			case "continue": mk(EContinue);
			case "else": unexpected(TId(id));
			case "inline":
				if (!maybe(TId("function"))) unexpected(TId("inline"));
				return parseStructure("function");
			case "function":
				var tk = token();
				var name = null;
				switch (tk) {
					case TId(id2): name = id2;
					default: push(tk);
				}
				var inf = parseFunctionDecl();
				mk(EFunction(inf.args, inf.body, name, inf.ret), p1, pmax(inf.body));
			case "return":
				var tk = token();
				push(tk);
				var e = if (tk == TSemicolon) null else parseExpr();
				mk(EReturn(e), p1, if (e == null) tokenMax else pmax(e));
			case "new":
				var a = new Array<String>();
				a.push(getIdent());
				while (true) {
					var tk = token();
					switch (tk) {
						case TDot:
							a.push(getIdent());
						case TPOpen:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				var args = parseExprList(TPClose);
				mk(ENew(a.join("."), args), p1);
			case "throw":
				var e = parseExpr();
				mk(EThrow(e), p1, pmax(e));
			case "try":
				var e = parseExpr();
				ensureToken(TId("catch"));
				ensure(TPOpen);
				var vname = getIdent();
				ensure(TDoubleDot);
				var t = parseType();
				ensure(TPClose);
				var ec = parseExpr();
				mk(ETry(e, vname, t, ec), p1, pmax(ec));
			case "switch":
				var e = parseExpr();
				var def = null, cases = [];
				ensure(TBrOpen);
				while (true) {
					var tk = token();
					switch (tk) {
						case TId("case"):
							var c = { values: [], expr: null };
							cases.push(c);
							while (true) {
								var ev = parseExpr();
								c.values.push(ev);
								tk = token();
								switch (tk) {
									case TComma: // next value
									case TDoubleDot: break;
									default:
										unexpected(tk);
										break;
								}
							}
							var exprs = [];
							while (true) {
								tk = token();
								push(tk);
								switch (tk) {
									case TId("case"), TId("default"), TBrClose: break;
									default: parseFullExpr(exprs);
								}
							}
							c.expr = if (exprs.length == 1) exprs[0]
								else if (exprs.length == 0) mk(EBlock([]), tokenMin, tokenMin)
								else mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TId("default"):
							if (def != null) unexpected(tk);
							ensure(TDoubleDot);
							var exprs = [];
							while (true) {
								tk = token();
								push(tk);
								switch (tk) {
									case TId("case"), TId("default"), TBrClose: break;
									default: parseFullExpr(exprs);
								}
							}
							def = if (exprs.length == 1) exprs[0]
								else if (exprs.length == 0) mk(EBlock([]), tokenMin, tokenMin)
								else mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TBrClose:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				mk(ESwitch(e, cases, def), p1, tokenMax);
			case "cast":
				var tk = token();
				if (Type.enumEq(tk, TPOpen)) {
					var e = parseExpr();
					ensure(TComma);
					var t = parseType();
					mk(ECast(e, t), p1, tokenMax);
				} else {
					push(tk);
					var e = parseExpr();
					mk(ECast(e, null), p1, tokenMax);
				}
			default:
				null;
		};
	}

	function parseExprNext(e1:Expr):Expr {
		var tk = token();
		switch (tk) {
			case TOp(op):
				if (op == "->") {
					// single-arg reinterpretation of `f -> e`, `(f) -> e`, `(f:T) -> e`
					switch (expr(e1)) {
						case EIdent(i):
							var eret = parseExpr();
							return mkLambda([{ name: i }], eret, pmin(e1));
						case EParent(inner):
							switch (expr(inner)) {
								case EIdent(i):
									var eret = parseExpr();
									return mkLambda([{ name: i }], eret, pmin(e1));
								default:
							}
						case ECheckType(inner, t):
							switch (expr(inner)) {
								case EIdent(i):
									var eret = parseExpr();
									return mkLambda([{ name: i, t: t }], eret, pmin(e1));
								default:
							}
						default:
					}
					unexpected(tk);
				}
				if (opPriority.get(op) == -1) {
					if (isBlock(e1) || switch (expr(e1)) { case EParent(_): true; default: false; }) {
						push(tk);
						return e1;
					}
					return parseExprNext(mk(EUnop(op, false, e1), pmin(e1)));
				}
				return makeBinop(op, e1, parseExpr());
			case TId(op) if (opPriority.exists(op)):
				return parseExprNext(makeBinop(op, e1, parseExpr()));
			case TDot:
				var field = getIdent();
				return parseExprNext(mk(EField(e1, field), pmin(e1)));
			case TQuestionDot:
				var field = getIdent();
				var tmp = "__a_" + (uid++);
				var e = mk(EBlock([
					mk(EVar(tmp, null, e1), pmin(e1), pmax(e1)),
					mk(ETernary(
						mk(EBinop("==", mk(EIdent(tmp), pmin(e1), pmax(e1)), mk(EIdent("null"), pmin(e1), pmax(e1)))),
						mk(EIdent("null"), pmin(e1), pmax(e1)),
						mk(EField(mk(EIdent(tmp), pmin(e1), pmax(e1)), field), pmin(e1))
					))
				]), pmin(e1));
				return parseExprNext(e);
			case TPOpen:
				return parseExprNext(mk(ECall(e1, parseExprList(TPClose)), pmin(e1)));
			case TBkOpen:
				var e2 = parseExpr();
				ensure(TBkClose);
				return parseExprNext(mk(EArray(e1, e2), pmin(e1)));
			case TQuestion:
				var e2 = parseExpr();
				ensure(TDoubleDot);
				var e3 = parseExpr();
				return mk(ETernary(e1, e2, e3), pmin(e1), pmax(e3));
			default:
				push(tk);
				return e1;
		}
	}

	function parseFunctionArgs():Array<Argument> {
		var args = new Array<Argument>();
		var tk = token();
		if (!Type.enumEq(tk, TPClose)) {
			var done = false;
			while (!done) {
				var name = null, opt = false;
				switch (tk) {
					case TQuestion:
						opt = true;
						tk = token();
					default:
				}
				switch (tk) {
					case TId(id): name = id;
					default:
						unexpected(tk);
						break;
				}
				var arg:Argument = { name: name };
				args.push(arg);
				if (opt) arg.opt = true;
				if (maybe(TDoubleDot))
					arg.t = parseType();
				if (maybe(TOp("=")))
					arg.value = parseExpr();
				tk = token();
				switch (tk) {
					case TComma:
						tk = token();
					case TPClose:
						done = true;
					default:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function parseFunctionDecl():{args:Array<Argument>, ret:Null<CType>, body:Expr} {
		ensure(TPOpen);
		var args = parseFunctionArgs();
		var ret = null;
		var tk = token();
		if (tk != TDoubleDot)
			push(tk);
		else
			ret = parseType();
		return { args: args, ret: ret, body: parseExpr() };
	}

	function parsePath():Array<String> {
		var path = [getIdent()];
		while (true) {
			var t = token();
			if (t != TDot) {
				push(t);
				break;
			}
			path.push(getIdent());
		}
		return path;
	}

	function parseType():CType {
		var t = token();
		switch (t) {
			case TId(_):
				push(t);
				var path = parsePath();
				var params = null;
				t = token();
				switch (t) {
					case TOp(op):
						if (op == "<") {
							params = [];
							while (true) {
								switch (token()) {
									case TConst(c):
										params.push(CTExpr(mk(EConst(c))));
									case tk:
										push(tk);
										params.push(parseType());
								}
								t = token();
								switch (t) {
									case TComma: continue;
									case TOp(op2):
										if (op2 == ">") break;
										if (op2.charCodeAt(0) == ">".code) {
											tokens.push({ t: TOp(op2.substr(1)), min: tokenMax - op2.length - 1, max: tokenMax });
											break;
										}
										unexpected(t);
									default:
										unexpected(t);
								}
							}
						} else
							push(t);
					default:
						push(t);
				}
				return parseTypeNext(CTPath(path, params));
			case TPOpen:
				var a = token();
				var b = token();
				push(b);
				push(a);
				function withReturn(args:Array<CType>):CType {
					switch (token()) {
						case TOp("->"):
						case t2: unexpected(t2);
					}
					return CTFun(args, parseType());
				}
				switch [a, b] {
					case [TPClose, _] | [TId(_), TDoubleDot]:
						var args = [for (arg in parseFunctionArgs()) {
							CTNamed(arg.name, if (arg.opt == true) CTOpt(arg.t) else arg.t);
						}];
						return withReturn(args);
					default:
						var t2 = parseType();
						return switch (token()) {
							case TComma:
								var args = [t2];
								while (true) {
									args.push(parseType());
									if (!maybe(TComma)) break;
								}
								ensure(TPClose);
								withReturn(args);
							case TPClose:
								parseTypeNext(CTParent(t2));
							case t3:
								unexpected(t3);
						};
				}
			case TBrOpen:
				var fields = [];
				while (true) {
					t = token();
					switch (t) {
						case TBrClose: break;
						case TId("var"), TId("final"):
							var name = getIdent();
							ensure(TDoubleDot);
							fields.push({ name: name, t: parseType(), meta: null });
							ensure(TSemicolon);
						case TId(name):
							ensure(TDoubleDot);
							fields.push({ name: name, t: parseType(), meta: null });
							t = token();
							switch (t) {
								case TComma:
								case TBrClose: break;
								default: unexpected(t);
							}
						default:
							unexpected(t);
							break;
					}
				}
				return parseTypeNext(CTAnon(fields));
			default:
				return unexpected(t);
		}
	}

	function parseTypeNext(t:CType):CType {
		var tk = token();
		switch (tk) {
			case TOp(op):
				if (op != "->") {
					push(tk);
					return t;
				}
			default:
				push(tk);
				return t;
		}
		var t2 = parseType();
		return switch (t2) {
			case CTFun(args, _):
				args.unshift(t);
				t2;
			default:
				CTFun([t], t2);
		};
	}

	function parseExprList(etk:NToken):Array<Expr> {
		var args = new Array<Expr>();
		var tk = token();
		if (Type.enumEq(tk, etk))
			return args;
		push(tk);
		while (true) {
			args.push(parseExpr());
			tk = token();
			switch (tk) {
				case TComma:
				default:
					if (Type.enumEq(tk, etk)) break;
					unexpected(tk);
					break;
			}
		}
		return args;
	}

	// ── tokenizer (mirrors hscript.Parser's _token) ──────────────────────────

	inline function readChar():Int {
		return StringTools.fastCodeAt(input, readPos++);
	}

	function token():NToken {
		var t = tokens.pop();
		if (t != null) {
			tokenMin = t.min;
			tokenMax = t.max;
			return t.t;
		}
		oldTokenMin = tokenMin;
		oldTokenMax = tokenMax;
		tokenMin = (this.char < 0) ? readPos : readPos - 1;
		var t2 = _token();
		tokenMax = (this.char < 0) ? readPos - 1 : readPos - 2;
		return t2;
	}

	function _token():NToken {
		var char;
		if (this.char < 0)
			char = readChar();
		else {
			char = this.char;
			this.char = -1;
		}
		while (true) {
			if (StringTools.isEof(char)) {
				this.char = char;
				return TEof;
			}
			switch (char) {
				case 0:
					return TEof;
				case 32, 9, 13:
					tokenMin++;
				case 10:
					line++;
					tokenMin++;
				case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
					var n = (char - 48) * 1.0;
					var exp = 0.;
					while (true) {
						char = readChar();
						exp *= 10;
						switch (char) {
							case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
								n = n * 10 + (char - 48);
							case "e".code, "E".code:
								var tk = token();
								var pow:Null<Int> = null;
								switch (tk) {
									case TConst(CInt(e)): pow = e;
									case TOp("-"):
										tk = token();
										switch (tk) {
											case TConst(CInt(e)): pow = -e;
											default: push(tk);
										}
									default:
										push(tk);
								}
								if (pow == null)
									invalidChar(char);
								if (exp == 0)
									exp = 10;
								return TConst(CFloat((Math.pow(10, pow) / exp) * n * 10));
							case ".".code:
								if (exp > 0) {
									// '0...' range op after an int
									if (exp == 10 && readChar() == ".".code) {
										push(TOp("..."));
										var i = Std.int(n);
										return TConst((i == n) ? CInt(i) : CFloat(n));
									}
									invalidChar(char);
								}
								exp = 1.;
							case "x".code:
								if (n > 0 || exp > 0)
									invalidChar(char);
								var h = 0;
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
											h = (h << 4) + char - 48;
										case 65, 66, 67, 68, 69, 70:
											h = (h << 4) + (char - 55);
										case 97, 98, 99, 100, 101, 102:
											h = (h << 4) + (char - 87);
										default:
											this.char = char;
											return TConst(CInt(h));
									}
								}
							default:
								this.char = char;
								var i = Std.int(n);
								return TConst((exp > 0) ? CFloat(n * 10 / exp) : ((i == n) ? CInt(i) : CFloat(n)));
						}
					}
				case ";".code: return TSemicolon;
				case "(".code: return TPOpen;
				case ")".code: return TPClose;
				case ",".code: return TComma;
				case ".".code:
					char = readChar();
					switch (char) {
						case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
							var n = char - 48;
							var exp = 1;
							while (true) {
								char = readChar();
								exp *= 10;
								switch (char) {
									case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
										n = n * 10 + (char - 48);
									default:
										this.char = char;
										return TConst(CFloat(n / exp));
								}
							}
						case ".".code:
							char = readChar();
							if (char != ".".code)
								invalidChar(char);
							return TOp("...");
						default:
							this.char = char;
							return TDot;
					}
				case "{".code: return TBrOpen;
				case "}".code: return TBrClose;
				case "[".code: return TBkOpen;
				case "]".code: return TBkClose;
				case "'".code, '"'.code: return TConst(CString(readString(char)));
				case "?".code:
					char = readChar();
					if (char == ".".code)
						return TQuestionDot;
					this.char = char;
					return TQuestion;
				case ":".code: return TDoubleDot;
				case "=".code:
					char = readChar();
					if (char == "=".code)
						return TOp("==");
					else if (char == ">".code)
						return TOp("=>");
					this.char = char;
					return TOp("=");
				case "@".code:
					char = readChar();
					if (idents[char] || char == ":".code) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (!idents[char]) {
								this.char = char;
								return TMeta(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				case "#".code:
					return unsupported("# preprocessor");
				default:
					if (ops[char]) {
						var op = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (StringTools.isEof(char)) char = 0;
							if (!ops[char]) {
								this.char = char;
								return TOp(op);
							}
							var pop = op;
							op += String.fromCharCode(char);
							if (!opPriority.exists(op) && opPriority.exists(pop)) {
								if (op == "//" || op == "/*")
									return tokenComment(op, char);
								this.char = char;
								return TOp(pop);
							}
						}
					}
					if (idents[char]) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (StringTools.isEof(char)) char = 0;
							if (!idents[char]) {
								this.char = char;
								return TId(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
			}
			char = readChar();
		}
		return null;
	}

	function tokenComment(op:String, char:Int):NToken {
		var c = op.charCodeAt(1);
		if (c == "/".code) { // single-line
			while (char != "\r".code && char != "\n".code) {
				char = readChar();
				if (StringTools.isEof(char)) break;
			}
			this.char = char;
			return token();
		}
		if (c == "*".code) { // multi-line
			var old = line;
			if (op == "/**/") {
				this.char = char;
				return token();
			}
			while (true) {
				while (char != "*".code) {
					if (char == "\n".code) line++;
					char = readChar();
					if (StringTools.isEof(char)) {
						line = old;
						error(EUnterminatedComment, tokenMin, tokenMin);
						break;
					}
				}
				char = readChar();
				if (StringTools.isEof(char)) {
					line = old;
					error(EUnterminatedComment, tokenMin, tokenMin);
					break;
				}
				if (char == "/".code)
					break;
			}
			return token();
		}
		this.char = char;
		return TOp(op);
	}

	function readString(until:Int):String {
		var b = new StringBuf();
		var esc = false;
		var old = line;
		var p1 = readPos - 1;
		while (true) {
			var c = readChar();
			if (StringTools.isEof(c)) {
				line = old;
				error(EUnterminatedString, p1, p1);
				break;
			}
			if (esc) {
				esc = false;
				switch (c) {
					case "n".code: b.addChar("\n".code);
					case "r".code: b.addChar("\r".code);
					case "t".code: b.addChar("\t".code);
					case "'".code, '"'.code, "\\".code: b.addChar(c);
					case "/".code: b.addChar(c);
					case "u".code:
						var k = 0;
						for (_ in 0...4) {
							k <<= 4;
							var h = readChar();
							switch (h) {
								case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
									k += h - 48;
								case 65, 66, 67, 68, 69, 70:
									k += h - 55;
								case 97, 98, 99, 100, 101, 102:
									k += h - 87;
								default:
									if (StringTools.isEof(h)) {
										line = old;
										error(EUnterminatedString, p1, p1);
									}
									invalidChar(h);
							}
						}
						b.addChar(k);
					default:
						invalidChar(c);
				}
			} else if (c == 92)
				esc = true;
			else if (c == until)
				break;
			else {
				if (c == 10) line++;
				b.addChar(c);
			}
		}
		return b.toString();
	}

	function tokenString(tk:NToken):String {
		return switch (tk) {
			case TEof: "<eof>";
			case TConst(c):
				switch (c) {
					case CInt(v): Std.string(v);
					case CFloat(f): Std.string(f);
					case CString(s): '"' + s + '"';
				}
			case TId(s): s;
			case TOp(s): s;
			case TPOpen: "(";
			case TPClose: ")";
			case TBrOpen: "{";
			case TBrClose: "}";
			case TDot: ".";
			case TQuestionDot: "?.";
			case TComma: ",";
			case TSemicolon: ";";
			case TBkOpen: "[";
			case TBkClose: "]";
			case TQuestion: "?";
			case TDoubleDot: ":";
			case TMeta(s): "@" + s;
		};
	}
}
