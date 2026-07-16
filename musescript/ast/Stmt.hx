package musescript.ast;

enum Stmt {
	OnBar(body:Array<Stmt>);
	OnPosition(body:Array<Stmt>);
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
	/** Sugared `when cond: action` — desugars to if(cond) action. */
	When(cond:Expr, body:Array<Stmt>);
	/** Module inclusion — resolved by ModuleExpand before compile. */
	Use(module:String, args:Array<{name:String, value:Expr}>);
}
