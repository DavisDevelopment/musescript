package musescript.types;

/**
 * Optional source span for diagnostics. Additive — AST nodes do not require pos.
 */
typedef SourcePos = {
	var ?file:String;
	var ?line:Int;
	var ?pmin:Int;
	var ?pmax:Int;
}
