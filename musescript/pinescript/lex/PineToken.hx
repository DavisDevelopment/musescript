package musescript.pinescript.lex;

import musescript.types.SourcePos;

/**
 * Lexical token kinds for Pine. Pine is indentation-significant (like Python):
 * local blocks — function bodies, `if`/`for`/`while`/`switch` bodies — are
 * delimited by INDENT/DEDENT rather than braces. The lexer emits NEWLINE at
 * statement boundaries and INDENT/DEDENT at block-nesting changes so the parser
 * never has to re-derive layout.
 */
enum PineTokenKind {
	// literals
	TInt(v:Int);
	TFloat(v:Float);
	TString(v:String);
	TBool(v:Bool);
	TColor(hex:String);          // #RRGGBB / #RRGGBBAA color literal
	TIdent(name:String);         // bare or the leading segment of a namespaced id
	TKeyword(word:String);       // if for while switch var varip import export etc.

	// punctuation / operators
	TOp(op:String);              // + - * / % == != < > <= >= = := => and or not ? :
	TLParen; TRParen;            // ( )
	TLBracket; TRBracket;        // [ ]  — history-ref and tuple/array
	TComma; TDot; TColon;        // , . :  (`:` also appears in ternary and switch)

	// layout
	TNewline;                    // logical statement terminator
    TIndent;                     // block open  (deeper indentation)
	TDedent;                     // block close (shallower indentation)
	TEof;
}

typedef PineToken = {
	var kind:PineTokenKind;
	var pos:SourcePos;
}

class PineTokens {
	public static inline function tok(kind:PineTokenKind, pos:SourcePos):PineToken
		return { kind: kind, pos: pos };

	/** Reserved words that are NOT namespaced stdlib calls — true keywords. */
	public static final KEYWORDS:Map<String, Bool> = [
		"if" => true, "else" => true, "for" => true, "to" => true, "by" => true,
		"while" => true, "switch" => true, "var" => true, "varip" => true,
		"import" => true, "export" => true, "type" => true, "method" => true,
		"and" => true, "or" => true, "not" => true, "true" => true, "false" => true,
		"na" => true, "continue" => true, "break" => true, "return" => true,
	];

	public static inline function isKeyword(w:String):Bool
		return KEYWORDS.exists(w);

	public static function describe(k:PineTokenKind):String {
		return switch (k) {
			case TInt(v): 'int($v)';
			case TFloat(v): 'float($v)';
			case TString(v): 'str("$v")';
			case TBool(v): 'bool($v)';
			case TColor(h): 'color($h)';
			case TIdent(n): 'ident($n)';
			case TKeyword(w): 'kw($w)';
			case TOp(o): 'op($o)';
			case TLParen: "(";
			case TRParen: ")";
			case TLBracket: "[";
			case TRBracket: "]";
			case TComma: ",";
			case TDot: ".";
			case TColon: ":";
			case TNewline: "\\n";
			case TIndent: ">INDENT";
			case TDedent: "<DEDENT";
			case TEof: "<eof>";
		};
	}
}
