package musescript.ast;

/**
 * Static constructors for muse AST nodes.
 * Keeps MuseParser free of bare EIdent/CInt pollution that clashes with hscript.
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
		return EConst(c);

	public static inline function ident(name:String):Expr
		return EIdent(name);

	public static inline function evar(name:String, ?init:Expr):Expr
		return EVar(name, init);

	public static inline function block(exprs:Array<Expr>):Expr
		return EBlock(exprs);

	public static inline function field(e:Expr, f:String):Expr
		return EField(e, f);

	public static inline function binop(op:String, left:Expr, right:Expr):Expr
		return EBinop(op, left, right);

	public static inline function unop(op:String, prefix:Bool, e:Expr):Expr
		return EUnop(op, prefix, e);

	public static inline function call(e:Expr, args:Array<Expr>):Expr
		return ECall(e, args);

	public static inline function eif(cond:Expr, eif:Expr, eelse:Null<Expr>):Expr
		return EIf(cond, eif, eelse);

	public static inline function ewhile(cond:Expr, body:Expr):Expr
		return EWhile(cond, body);

	public static inline function efor(name:String, it:Expr, body:Expr):Expr
		return EFor(name, it, body);

	public static inline function efunction(args:Array<String>, body:Expr, kind:FnKind, ?name:String):Expr
		return EFunction(args, body, kind, name);

	public static inline function ereturn(?e:Expr):Expr
		return EReturn(e);

	public static inline function arrayDecl(values:Array<Expr>):Expr
		return EArrayDecl(values);

	public static inline function object(fields:Array<{name:String, e:Expr}>):Expr
		return EObject(fields);

	public static inline function ternary(cond:Expr, eif:Expr, eelse:Expr):Expr
		return ETernary(cond, eif, eelse);

	public static inline function parent(e:Expr):Expr
		return EParent(e);

	public static inline function meta(name:String, args:Array<Expr>, e:Expr):Expr
		return EMeta(name, args, e);

	public static inline function lookback(series:Expr, n:Expr):Expr
		return ELookback(series, n);

	public static inline function match(scrutinee:Expr, arms:Array<MatchArm>):Expr
		return EMatch(scrutinee, arms);

	public static inline function eyield(e:Expr):Expr
		return EYield(e);

	public static inline function eyieldStar(e:Expr):Expr
		return EYieldStar(e);

	public static inline function barField(name:String):Expr
		return EBarField(name);

	// --- Convenience ---

	public static inline function nullExpr():Expr
		return EConst(CNull);

	public static inline function intExpr(i:Int):Expr
		return EConst(CInt(i));

	public static inline function floatExpr(f:Float):Expr
		return EConst(CFloat(f));

	public static inline function stringExpr(s:String):Expr
		return EConst(CString(s));

	public static inline function boolExpr(b:Bool):Expr
		return EConst(CBool(b));
}
