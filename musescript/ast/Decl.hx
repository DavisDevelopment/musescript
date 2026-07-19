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
	
	/**
	 * Statement template — expands at call sites into stmt lists (onBar/onPosition/when/…).
	 * Declared without `-> RetType`; invoked as a bare statement: `TrailingStop(0.05)`.
	 */
	StmtTemplateDecl(name:String, params:Array<{name:String, ty:String}>, body:Array<Stmt>);

	/**
	 * Algebraic enum (Haxe-flavored). Each variant is a tag with an optional
	 * positional payload. Nullary variants construct a shared singleton value,
	 * n-ary variants a constructor; both produce the canonical tagged record
	 * `{ __tag: "<Variant>", args: [...] }` that `match` (PatternMatcher) reads.
	 */
	EnumDecl(name:String, variants:Array<{name:String, args:Array<String>}>);

	/**
	 * Class (Haxe-flavored, P2: no inheritance yet — `parent` is parsed but
	 * unused until P3). Instances are anon records carrying field values plus
	 * `__class: "<Name>"`; methods live on this decl's own registry, dispatched
	 * by `__class`, never copied per-instance. `this` is optional inside
	 * method/ctor bodies (bare `field` resolves like `this.field`).
	 */
	ClassDecl(name:String, parent:Null<String>, fields:Array<{name:String, def:Null<Expr>}>,
		methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>,
		ctor:Null<{args:Array<String>, body:Expr}>);
}
