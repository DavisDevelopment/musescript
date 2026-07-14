package musescript.runtime;

import musescript.ast.Expr;
import musescript.ast.MatchArm;

typedef MatchResult = {
	var matched:Bool;
	var bindings:Map<String, Dynamic>;
	var ?body:Expr;
	var ?guard:Expr;
	/** Nested pattern-level guards (`PatGuard`), evaluated after binds. */
	var ?patGuards:Array<Dynamic>;
}
