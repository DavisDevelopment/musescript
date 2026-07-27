package musescript.pinescript.lex;

import musescript.types.SourcePos;
import musescript.pinescript.lex.PineToken;
import musescript.pinescript.lex.PineToken.PineTokens.*;

/**
 * Indentation-significant tokenizer for Pine.
 *
 * Pine delimits local blocks by layout, not braces. This lexer produces a flat
 * token stream where block structure is explicit as TIndent / TDedent, and
 * statement boundaries are TNewline — so the parser consumes a clean stream and
 * never re-scans whitespace.
 *
 * Layout rules implemented:
 *  - An indent stack starts at column 0. A logical line whose indent exceeds the
 *    stack top pushes and emits TIndent; a shallower one pops and emits TDedent
 *    (possibly several) back to a matching level.
 *  - Blank lines and comment-only lines carry no indentation signal.
 *  - Bracket depth (`(` `[`) suppresses TNewline/indent tracking, so multi-line
 *    function calls and array literals continue naturally. Trailing binary ops /
 *    `=` / `,` also soft-continue onto the next line (`x =\n  expr`, `"a" +\n  "b"`)
 *    without emitting NEWLINE/INDENT — expression parsing sees a flat stream.
 *
 * Comments: Pine has only `//` line comments (no block comments). The `//@version`
 * pragma is a comment lexically; PineVersionSniff reads it separately from source.
 */
class PineLexer {
	final src:String;
	final origin:String;
	var i:Int = 0;
	var line:Int = 1;
	var col:Int = 1;
	final indents:Array<Int> = [0];
	var bracketDepth:Int = 0;
	/** Soft line-continuation after a trailing binary op / `=` / `,` (Pine allows
	 *  `x =\n  expr` and `"a" +\n  "b"`). While set, the next logical line skips
	 *  INDENT/DEDENT/NEWLINE the same way bracket-depth continuation does. */
	var softContinue:Bool = false;
	final out:Array<PineToken> = [];

	public function new(source:String, ?origin:String) {
		this.src = source;
		this.origin = origin != null ? origin : "<pine>";
	}

	public static function tokenize(source:String, ?origin:String):Array<PineToken> {
		return new PineLexer(source, origin).run();
	}

	inline function peek(o:Int = 0):Int {
		var p = i + o;
		return p < src.length ? StringTools.fastCodeAt(src, p) : -1;
	}

	inline function here():SourcePos
		return { file: origin, line: line, column: col, pmin: i, pmax: i };

	function advance():Int {
		var c = StringTools.fastCodeAt(src, i);
		i++;
		if (c == "\n".code) { line++; col = 1; } else col++;
		return c;
	}

	function emit(kind:PineTokenKind, pos:SourcePos):Void {
		pos.pmax = i;
		out.push(tok(kind, pos));
	}

	public function run():Array<PineToken> {
		while (i < src.length) {
			lexLogicalLine();
		}
		// close any dangling block levels at EOF
		if (out.length > 0 && out[out.length - 1].kind != TNewline)
			out.push(tok(TNewline, here()));
		while (indents.length > 1) {
			indents.pop();
			out.push(tok(TDedent, here()));
		}
		out.push(tok(TEof, here()));
		return out;
	}

	/** Consume one source line's worth of tokens, handling leading layout. */
	function lexLogicalLine():Void {
		var continuing = bracketDepth > 0 || softContinue;
		softContinue = false;
		if (!continuing) {
			var indent = measureIndent();
			if (indent < 0) return; // blank / comment-only line — no layout signal
			applyIndent(indent);
		} else {
			// bracket or soft op-continuation: swallow leading ws, no layout tokens
			skipInlineWs();
		}

		var producedThisLine = false;
		while (i < src.length) {
			var c = peek();
			if (c == "\n".code) {
				advance();
				if (bracketDepth == 0) {
					if (producedThisLine && lastIsLineContinuation()) {
						// trailing `+` / `=` / `,` etc. — continue onto next line
						softContinue = true;
						return;
					}
					if (!producedThisLine && continuing) {
						// blank line mid soft-continued expression — keep continuing
						softContinue = true;
						return;
					}
					if (producedThisLine) emit(TNewline, here());
					return;
				}
				// inside brackets: newline is continuation — swallow, keep going
				break;
			}
			if (c == " ".code || c == "\t".code || c == "\r".code) { advance(); continue; }
			if (c == "/".code && peek(1) == "/".code) { skipLineComment(); continue; }

			lexToken();
			producedThisLine = true;
		}
		// reached EOF or wrapped a bracket-continued newline; loop re-enters run()
	}

	/** True when the last emitted token invites a soft line-continuation
	 *  (expression continues on the next physical line). Does NOT include `=>`
	 *  — function bodies still need INDENT layout. */
	function lastIsLineContinuation():Bool {
		if (out.length == 0) return false;
		return switch (out[out.length - 1].kind) {
			case TOp(o) if (
				o == "+" || o == "-" || o == "*" || o == "/" || o == "%"
				|| o == "=" || o == ":=" || o == "?" || o == ":"
				|| o == "and" || o == "or"
				|| o == "==" || o == "!=" || o == "<" || o == ">" || o == "<=" || o == ">="
			): true;
			case TComma: true;
			case TKeyword(w) if (w == "and" || w == "or"): true;
			default: false;
		};
	}

	/** Returns indentation width (spaces, tab=1) of the coming line, or -1 if the
	 *  line is blank or comment-only (no layout meaning). Positions at first
	 *  significant char when a real line. */
	function measureIndent():Int {
		var width = 0;
		var j = i;
		while (j < src.length) {
			var c = StringTools.fastCodeAt(src, j);
			if (c == " ".code) { width++; j++; }
			else if (c == "\t".code) { width++; j++; }
			else break;
		}
		// classify what follows the whitespace
		if (j >= src.length) { i = j; col += (j - i); return -1; }
		var c = StringTools.fastCodeAt(src, j);
		if (c == "\n".code || c == "\r".code) {
			// blank line — consume through the newline, no signal
			while (i < j) advance();
			if (peek() == "\r".code) advance();
			if (peek() == "\n".code) advance();
			return -1;
		}
		if (c == "/".code && j + 1 < src.length && StringTools.fastCodeAt(src, j + 1) == "/".code) {
			// comment-only line — consume through newline, no signal
			while (i < j) advance();
			skipLineComment();
			if (peek() == "\n".code) advance();
			return -1;
		}
		while (i < j) advance();
		return width;
	}

	function applyIndent(indent:Int):Void {
		var top = indents[indents.length - 1];
		if (indent > top) {
			indents.push(indent);
			out.push(tok(TIndent, here()));
		} else if (indent < top) {
			while (indents.length > 1 && indents[indents.length - 1] > indent) {
				indents.pop();
				out.push(tok(TDedent, here()));
			}
		}
	}

	inline function skipInlineWs():Void {
		while (true) {
			var c = peek();
			if (c == " ".code || c == "\t".code || c == "\r".code) advance();
			else break;
		}
	}

	function skipLineComment():Void {
		while (i < src.length && peek() != "\n".code) advance();
	}

	function lexToken():Void {
		var start = here();
		var c = peek();

		// string literal — single or double quoted
		if (c == "\"".code || c == "'".code) { lexString(c, start); return; }
		// color literal #RRGGBB[AA]
		if (c == "#".code && isHex(peek(1))) { lexColor(start); return; }
		// number
		if (isDigit(c) || (c == ".".code && isDigit(peek(1)))) { lexNumber(start); return; }
		// identifier / keyword
		if (isIdentStart(c)) { lexIdent(start); return; }

		// punctuation / operators
		switch (c) {
			case "(".code: advance(); bracketDepth++; emit(TLParen, start);
			case ")".code: advance(); if (bracketDepth > 0) bracketDepth--; emit(TRParen, start);
			case "[".code: advance(); bracketDepth++; emit(TLBracket, start);
			case "]".code: advance(); if (bracketDepth > 0) bracketDepth--; emit(TRBracket, start);
			case ",".code: advance(); emit(TComma, start);
			case ".".code: advance(); emit(TDot, start);
			default: lexOperator(start);
		}
	}

	function lexString(quote:Int, start:SourcePos):Void {
		advance(); // opening quote
		var buf = new StringBuf();
		while (i < src.length) {
			var c = peek();
			if (c == "\\".code) {
				advance();
				var e = advance();
				buf.addChar(switch (e) {
					case "n".code: "\n".code;
					case "t".code: "\t".code;
					case "r".code: "\r".code;
					case "\\".code: "\\".code;
					case _: e;
				});
			} else if (c == quote) {
				advance();
				emit(TString(buf.toString()), start);
				return;
			} else {
				buf.addChar(advance());
			}
		}
		// unterminated — emit what we have (parser reports the error with span)
		emit(TString(buf.toString()), start);
	}

	function lexColor(start:SourcePos):Void {
		advance(); // '#'
		var buf = new StringBuf();
		while (isHex(peek())) buf.addChar(advance());
		emit(TColor(buf.toString()), start);
	}

	function lexNumber(start:SourcePos):Void {
		var buf = new StringBuf();
		var isFloat = false;
		while (isDigit(peek())) buf.addChar(advance());
		if (peek() == ".".code && isDigit(peek(1))) {
			isFloat = true;
			buf.addChar(advance());
			while (isDigit(peek())) buf.addChar(advance());
		}
		// scientific notation 1e6 / 1.2e-3
		if (peek() == "e".code || peek() == "E".code) {
			isFloat = true;
			buf.addChar(advance());
			if (peek() == "+".code || peek() == "-".code) buf.addChar(advance());
			while (isDigit(peek())) buf.addChar(advance());
		}
		var s = buf.toString();
		if (isFloat) emit(TFloat(Std.parseFloat(s)), start);
		else emit(TInt(Std.parseInt(s)), start);
	}

	function lexIdent(start:SourcePos):Void {
		var buf = new StringBuf();
		while (isIdentPart(peek())) buf.addChar(advance());
		var word = buf.toString();
		if (word == "true") emit(TBool(true), start);
		else if (word == "false") emit(TBool(false), start);
		else if (isKeyword(word)) emit(TKeyword(word), start);
		else emit(TIdent(word), start);
	}

	function lexOperator(start:SourcePos):Void {
		// try two-char operators first
		var c0 = peek(), c1 = peek(1);
		var two = twoCharOp(c0, c1);
		if (two != null) { advance(); advance(); emit(TOp(two), start); return; }

		switch (c0) {
			case ":".code: advance(); emit(TColon, start); // ternary/switch colon
			case "+".code | "-".code | "*".code | "/".code | "%".code
			   | "<".code | ">".code | "=".code | "?".code:
				advance(); emit(TOp(String.fromCharCode(c0)), start);
			default:
				// unknown char — consume and skip to avoid infinite loop
				advance();
		}
	}

	function twoCharOp(a:Int, b:Int):Null<String> {
		return switch [a, b] {
			case ["=".code, "=".code]: "==";
			case ["!".code, "=".code]: "!=";
			case ["<".code, "=".code]: "<=";
			case [">".code, "=".code]: ">=";
			case [":".code, "=".code]: ":=";  // reassignment (v4+)
			case ["=".code, ">".code]: "=>";  // function def / arrow
			case ["+".code, "=".code]: "+=";
			case ["-".code, "=".code]: "-=";
			case ["*".code, "=".code]: "*=";
			case ["/".code, "=".code]: "/=";
			case ["%".code, "=".code]: "%=";
			case _: null;
		};
	}

	// ── char classes ──────────────────────────────────────────────────────────
	inline function isDigit(c:Int):Bool return c >= "0".code && c <= "9".code;
	inline function isHex(c:Int):Bool
		return isDigit(c) || (c >= "a".code && c <= "f".code) || (c >= "A".code && c <= "F".code);
	inline function isIdentStart(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code;
	inline function isIdentPart(c:Int):Bool
		return isIdentStart(c) || isDigit(c);
}
