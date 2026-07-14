package musescript.ast;

enum Decl {
	StrategyDecl(name:String, body:Array<Stmt>);
	IndicatorDecl(name:String, args:Array<String>, body:Expr);
	ParamDecl(name:String, defaultValue:Null<Expr>, opts:ParamOpts);
	FnDecl(name:Null<String>, args:Array<String>, body:Expr, kind:FnKind);
	MacroDecl(name:String, body:Array<Stmt>);
}
