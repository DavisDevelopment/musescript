package musescript.ast;

/**
 * Expression nodes. On the once-floated idea of merging the whole AST enum
 * constellation (Expr/Stmt/Decl/Const/Pattern/MatchArm/OrderKind/FnKind)
 * into one file: DECIDED AGAINST. Haxe resolves these per-module regardless,
 * ~40 sites import them individually, and one-enum-per-file keeps diffs and
 * blame local. If a real parser rewrite lands (see ROADMAP.md) the AST gets
 * revisited wholesale then — not as a cosmetic file merge before it.
 */

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

	/** `new ClassName(args)` — instantiate a `ClassDecl`. */
	ENew(className:String, args:Array<Expr>);

	/** `this` inside a method/ctor body — the receiving instance. Optional
	 * elsewhere: bare field reads/writes resolve like `this.field` without it. */
	EThis;

	/** P3: `super(args)` (method:null — chains to the parent ctor) or
	 * `super.method(args)` (method set — calls the parent's version, bypassing
	 * the child's own override). Resolved relative to the LEXICAL class the
	 * currently-executing method/ctor is defined in, not the runtime instance's
	 * most-derived `__class`. */
	ESuper(method:Null<String>, args:Array<Expr>);
}
