package musescript.ast;

import musescript.types.AstSpans;

/**
 * Static constructors for muse AST nodes.
 * Keeps MuseParser free of bare EIdent/CInt pollution that clashes with hscript.
 * When AstSpans.active/pending are set, constructions are auto-stamped.
 */
class MuseNodes {
	// --- Const ---

	public static inline function cint(i:Int):Const
		return CInt(i);

	public static inline function cfloat(f:Float):Const
		return CFloat(f);

	public static inline function cstring(s:String):Const
		return CString(s);

	public static inline function cbool(b:Bool):Const
		return CBool(b);

	public static inline function cnull():Const
		return CNull;

	// --- Expr ---

	public static inline function econst(c:Const):Expr
		return AstSpans.autoStamp(EConst(c));

	public static inline function ident(name:String):Expr
		return AstSpans.autoStamp(EIdent(name));

	public static inline function evar(name:String, ?init:Expr):Expr
		return AstSpans.autoStamp(EVar(name, init));

	public static inline function block(exprs:Array<Expr>):Expr
		return AstSpans.autoStamp(EBlock(exprs));

	public static inline function field(e:Expr, f:String):Expr
		return AstSpans.autoStamp(EField(e, f));

	public static inline function binop(op:String, left:Expr, right:Expr):Expr
		return AstSpans.autoStamp(EBinop(op, left, right));

	public static inline function unop(op:String, prefix:Bool, e:Expr):Expr
		return AstSpans.autoStamp(EUnop(op, prefix, e));

	public static inline function call(e:Expr, args:Array<Expr>):Expr
		return AstSpans.autoStamp(ECall(e, args));

	public static inline function eif(cond:Expr, eif:Expr, eelse:Null<Expr>):Expr
		return AstSpans.autoStamp(EIf(cond, eif, eelse));

	public static inline function ewhile(cond:Expr, body:Expr):Expr
		return AstSpans.autoStamp(EWhile(cond, body));

	public static inline function efor(name:String, it:Expr, body:Expr):Expr
		return AstSpans.autoStamp(EFor(name, it, body));

	public static inline function efunction(args:Array<String>, body:Expr, kind:FnKind, ?name:String):Expr
		return AstSpans.autoStamp(EFunction(args, body, kind, name));

	public static inline function ereturn(?e:Expr):Expr
		return AstSpans.autoStamp(EReturn(e));

	public static inline function arrayDecl(values:Array<Expr>):Expr
		return AstSpans.autoStamp(EArrayDecl(values));

	public static inline function array(e:Expr, index:Expr):Expr
		return AstSpans.autoStamp(EArray(e, index));

	public static inline function object(fields:Array<{name:String, e:Expr}>):Expr
		return AstSpans.autoStamp(EObject(fields));

	public static inline function ternary(cond:Expr, eif:Expr, eelse:Expr):Expr
		return AstSpans.autoStamp(ETernary(cond, eif, eelse));

	public static inline function parent(e:Expr):Expr
		return AstSpans.autoStamp(EParent(e));

	public static inline function meta(name:String, args:Array<Expr>, e:Expr):Expr
		return AstSpans.autoStamp(EMeta(name, args, e));

	public static inline function lookback(series:Expr, n:Expr):Expr
		return AstSpans.autoStamp(ELookback(series, n));

	public static inline function match(scrutinee:Expr, arms:Array<MatchArm>):Expr
		return AstSpans.autoStamp(EMatch(scrutinee, arms));

	public static inline function eyield(e:Expr):Expr
		return AstSpans.autoStamp(EYield(e));

	public static inline function eyieldStar(e:Expr):Expr
		return AstSpans.autoStamp(EYieldStar(e));

	public static inline function barField(name:String):Expr
		return AstSpans.autoStamp(EBarField(name));

	public static inline function enew(className:String, args:Array<Expr>):Expr
		return AstSpans.autoStamp(ENew(className, args));

	public static inline function ethis():Expr
		return AstSpans.autoStamp(EThis);

	public static inline function esuper(method:Null<String>, args:Array<Expr>):Expr
		return AstSpans.autoStamp(ESuper(method, args));

	// --- Convenience ---

	public static inline function nullExpr():Expr
		return AstSpans.autoStamp(EConst(CNull));

	public static inline function intExpr(i:Int):Expr
		return AstSpans.autoStamp(EConst(CInt(i)));

	public static inline function floatExpr(f:Float):Expr
		return AstSpans.autoStamp(EConst(CFloat(f)));

	public static inline function stringExpr(s:String):Expr
		return AstSpans.autoStamp(EConst(CString(s)));

	public static inline function boolExpr(b:Bool):Expr
		return AstSpans.autoStamp(EConst(CBool(b)));
}
