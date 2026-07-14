package musescript.ast;

typedef MatchArm = {
	var pattern:Pattern;
	var ?guard:Expr;
	var body:Expr;
}
