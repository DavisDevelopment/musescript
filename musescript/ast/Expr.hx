package musescript.ast;

enum Expr {
	EConst(c:Const);
	EIdent(name:String);
	EVar(name:String, ?init:Expr);
	EBlock(exprs:Array<Expr>);
	EField(e:Expr, f:String);
	EBinop(op:String, left:Expr, right:Expr);
	EUnop(op:String, prefix:Bool, e:Expr);
	ECall(e:Expr, args:Array<Expr>);
	EIf(cond:Expr, eif:Expr, eelse:Null<Expr>);
	EWhile(cond:Expr, body:Expr);
	EFor(name:String, it:Expr, body:Expr);
	EFunction(args:Array<String>, body:Expr, kind:FnKind, ?name:String);
	EReturn(e:Null<Expr>);
	EArray(e:Expr, index:Expr);
	EArrayDecl(values:Array<Expr>);
	EObject(fields:Array<{name:String, e:Expr}>);
	ETernary(cond:Expr, eif:Expr, eelse:Expr);
	EParent(e:Expr);
	EMeta(name:String, args:Array<Expr>, e:Expr);
	ELookback(series:Expr, n:Expr);
	EMatch(scrutinee:Expr, arms:Array<MatchArm>);
	EYield(e:Expr);
	EYieldStar(e:Expr);
	EBarField(name:String);
}
