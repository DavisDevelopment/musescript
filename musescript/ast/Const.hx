package musescript.ast;

/**
 * Literal constants. Deliberately minimal: color literals (`#ff0000`) and date
 * literals (`2026-01-01`) were considered and REJECTED as Const kinds — both
 * are domain values, not lexical primitives. Colors flow through plot/chart
 * builtins as strings; dates are Floats (epoch time on `bar.time`) with
 * string parsing at the data boundary. Growing the literal set would ripple
 * through every backend (JS/Py/WASM emitters, checker, JSON AST) for zero
 * added expressiveness. Revisit only if a new backend-visible primitive type
 * (not a notation convenience) actually appears.
 */
enum Const {
	CInt(v:Int);
	CFloat(v:Float);
	CString(v:String);
	CBool(v:Bool);
	CNull;
}
