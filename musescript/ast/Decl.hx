package musescript.ast;

enum Decl {
	StrategyDecl(name:String, body:Array<Stmt>);
	IndicatorDecl(name:String, args:Array<String>, body:Expr);
	ParamDecl(name:String, defaultValue:Null<Expr>, opts:ParamOpts);
	FnDecl(name:Null<String>, args:Array<String>, body:Expr, kind:FnKind);
	MacroDecl(name:String, body:Array<Stmt>);
	/** Composable module — flattened via `use` before backends see it. */
	ModuleDecl(name:String, params:Array<{name:String, ty:Null<String>, def:Null<Expr>}>, body:Array<Stmt>);
	/** Typed AST template — expands before type-check. */
	TemplateDecl(name:String, params:Array<{name:String, ty:String}>, retTy:String, body:Expr);
}
