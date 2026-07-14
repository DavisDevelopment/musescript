package musescript.ast;

enum Stmt {
	OnBar(body:Array<Stmt>);
	OnTick(body:Array<Stmt>);
	OnEvent(streamName:String, body:Array<Stmt>);
	ExprStmt(e:Expr);
	Assign(name:String, e:Expr);
	ForIn(name:String, iter:Expr, body:Array<Stmt>);
	MatchFor(name:String, iter:Expr, arms:Array<MatchArm>);
	Return(e:Null<Expr>);
	Yield(e:Expr);
	YieldStar(e:Expr);
	Order(kind:OrderKind, args:Array<Expr>);
	Block(stmts:Array<Stmt>);
}
